"""타일을 시계가 직접 그리는 선 좌표 JSON으로 내보낸다.

이 폰·시계 조합은 이미지 요청(-300)이 막혀 있고 일반 웹 요청(JSON)만 통과해서 쓴다.
파일 = {"a": [[코드, 점, 점, ...], ...]}, 그리는 순서 = PRIORITY 순.
점 = (x+8)*256 + (y+8), x·y는 타일 안 좌표(-MARGIN..TILE+MARGIN).
코드: 1~3 실선(펜 굵기) · 4 점선(점만 찍음) · 10+r 역 기호 고리(반지름 r) · 20+r 원판(반지름 r)
"""

import json
import os

import numpy as np
from shapely.geometry import LineString, box

from render import MARGIN, STYLE, TILE, resample

OFF = 8


def _pack(x, y):
    return (int(x) + OFF) * 256 + (int(y) + OFF)


def _round_pts(xy):
    out = []
    for x, y in xy:
        p = (int(round(x)), int(round(y)))
        if not out or out[-1] != p:
            out.append(p)
    return out


def _clip(xy, win):
    """폴리라인을 윈도 안으로 자른 조각들(각각 반올림 좌표 목록, 점 2개 이상)."""
    g = LineString(xy)
    if g.is_empty or not g.intersects(win):
        return []
    c = g.intersection(win)
    parts = [c] if c.geom_type == "LineString" else list(getattr(c, "geoms", []))
    out = []
    for part in parts:
        if part.geom_type != "LineString":
            continue
        pts = _round_pts(part.coords)
        if len(pts) >= 2:
            out.append(pts)
    return out


def _dash_pieces(xy):
    s, rp = resample(xy, 1.0)
    if s is None:
        return []
    on = (s % 7.0) < 4.0
    pieces, first = [], None
    for i in range(len(rp)):
        if on[i] and first is None:
            first = i
        if (not on[i] or i == len(rp) - 1) and first is not None:
            last = i if on[i] else i - 1
            if last > first:
                pieces.append(np.array([rp[first], rp[last]]))
            first = None
    return pieces


def tile_ops(items, z, tx, ty, kept):
    ox, oy = tx * TILE, ty * TILE
    win = box(-MARGIN, -MARGIN, TILE + MARGIN, TILE + MARGIN)
    ops = []

    def line_op(code, xy):
        for pts in _clip(xy, win):
            ops.append([code] + [_pack(x, y) for x, y in pts])

    for _, cls, kind, data in items:
        if cls not in kept:
            continue
        width, pattern = STYLE[cls][z]
        if kind == "line":
            xy = data - (ox, oy)
            if pattern == "solid":
                line_op(width, xy)
            elif pattern == "dash":
                for piece in _dash_pieces(xy):
                    line_op(width, piece)
            else:  # dot
                _, rp = resample(xy, 3.0)
                if rp is None:
                    continue
                pts = [
                    (int(round(x)), int(round(y)))
                    for x, y in rp
                    if -MARGIN <= x <= TILE + MARGIN and -MARGIN <= y <= TILE + MARGIN
                ]
                if pts:
                    ops.append([4] + [_pack(x, y) for x, y in pts])
        elif kind == "poly":
            outer, inners = data
            for ring in [outer] + list(inners):
                r = ring - (ox, oy)
                line_op(max(width, 1), np.vstack([r, r[:1]]))
        else:
            px, py = data[0] - ox, data[1] - oy
            if -MARGIN <= px <= TILE + MARGIN and -MARGIN <= py <= TILE + MARGIN:
                base = 10 if pattern == "ring" else 20
                ops.append([base + width, _pack(round(px), round(py))])
    return ops


def make_emitter(vec_dir):
    def emit(items, z, tx, ty, kept):
        ops = tile_ops(items, z, tx, ty, kept)
        if not ops:
            return
        d = os.path.join(vec_dir, str(z), str(tx))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, f"{ty}.json"), "w", encoding="utf-8") as f:
            json.dump({"a": ops}, f, separators=(",", ":"))

    return emit
