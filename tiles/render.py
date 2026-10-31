"""추출물(features.pkl) → 축척별 1비트 128px 타일 PNG.

축척별 표현 규칙(핵심): STYLE 표에 있는 축척에서만 그 등급을 그리고, PRIORITY 뒤쪽
등급은 타일 잉크 비율이 INK_MAX를 넘으면 생략한다(뭉개짐 방지). 글자는 그리지 않는다.
잉크가 전혀 없는 타일은 파일을 만들지 않는다(시계 앱은 404를 빈 땅으로 취급).

사용: python render.py <features.pkl> <출력 폴더 docs/t> [--zooms 13,14,15,16]
      [--preview 37.5000,126.9100]  # 신풍역 둘레 176px 미리보기를 preview/ 에 저장
"""

import argparse
import math
import os
import pickle
import time

import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import LineString, LinearRing

from areas import AREAS, TILE, ZOOMS

MARGIN = 6  # 선 두께가 타일 경계에서 잘리지 않도록 그릴 때 두는 여유(px)
INK_MAX = 0.35  # 밀도 가드: 타일 잉크 비율 상한
MIN_PX = 3.0  # 화면에서 이보다 작은 선·면은 생략
SIMPLIFY_PX = 0.7  # 선 단순화 허용 오차(px)

# 등급 → {축척: (선 두께, 무늬)}. 표에 없는 축척에서는 그리지 않음
STYLE = {
    "major": {13: (2, "solid"), 14: (2, "solid"), 15: (3, "solid"), 16: (3, "solid")},
    "arterial": {
        13: (1, "solid"),
        14: (2, "solid"),
        15: (2, "solid"),
        16: (2, "solid"),
    },
    "collector": {14: (1, "solid"), 15: (1, "solid"), 16: (2, "solid")},
    "local": {15: (1, "solid"), 16: (1, "solid")},
    "path": {16: (1, "dot")},
    "rail": {13: (1, "dash"), 14: (1, "dash"), 15: (1, "dash"), 16: (2, "dash")},
    "river": {13: (2, "solid"), 14: (2, "solid"), 15: (2, "solid"), 16: (3, "solid")},
    "stream": {15: (1, "solid"), 16: (1, "solid")},
    "water": {13: (0, "fill"), 14: (0, "fill"), 15: (0, "fill"), 16: (0, "fill")},
    "green": {15: (1, "outline"), 16: (1, "outline")},
    "subway_station": {14: (2, "ring"), 15: (3, "ring"), 16: (4, "ring")},
    "rail_station": {
        13: (2, "disc"),
        14: (2, "disc"),
        15: (3, "disc"),
        16: (3, "disc"),
    },
}
# 그리는 순서 = 중요도. DROPPABLE_FROM 이후 등급만 밀도 가드로 생략 가능
PRIORITY = [
    "water",
    "river",
    "major",
    "rail",
    "arterial",
    "subway_station",
    "rail_station",
    "collector",
    "stream",
    "green",
    "local",
    "path",
]
DROPPABLE_FROM = PRIORITY.index("collector")


def world_px(lon, lat, z):
    """경위도 → 웹 메르카토르 월드 픽셀(256px 기준 축척 z)."""
    n = 256.0 * (1 << z)
    x = (np.asarray(lon) + 180.0) / 360.0 * n
    lat_r = np.radians(np.asarray(lat))
    y = (1.0 - np.log(np.tan(lat_r) + 1.0 / np.cos(lat_r)) / math.pi) / 2.0 * n
    return x, y


def allowed_tiles(z):
    out = set()
    for a in AREAS:
        x0, y0 = world_px(a["west"], a["north"], z)
        x1, y1 = world_px(a["east"], a["south"], z)
        for tx in range(int(x0 // TILE), int(x1 // TILE) + 1):
            for ty in range(int(y0 // TILE), int(y1 // TILE) + 1):
                out.add((tx, ty))
    return out


def simplify_line(xy, closed=False):
    if len(xy) < 2:
        return xy
    try:
        g = LinearRing(xy) if closed and len(xy) >= 4 else LineString(xy)
        s = g.simplify(SIMPLIFY_PX, preserve_topology=True)
        return np.asarray(s.coords)
    except Exception:
        return xy


def tiles_for_bbox(xmin, ymin, xmax, ymax, pad):
    return [
        (tx, ty)
        for tx in range(int((xmin - pad) // TILE), int((xmax + pad) // TILE) + 1)
        for ty in range(int((ymin - pad) // TILE), int((ymax + pad) // TILE) + 1)
    ]


def bucket_features(feats, z, allowed):
    """축척 z에서 각 타일에 그릴 지형지물 목록을 만든다. {tile: [(priority, cls, kind, data)]}"""
    buckets = {}

    def add(xmin, ymin, xmax, ymax, pad, item):
        for t in tiles_for_bbox(xmin, ymin, xmax, ymax, pad):
            if t in allowed:
                buckets.setdefault(t, []).append(item)

    for cls, coords in feats["lines"]:
        st = STYLE[cls].get(z)
        if st is None:
            continue
        arr = np.asarray(coords)
        x, y = world_px(arr[:, 0], arr[:, 1], z)
        xy = simplify_line(np.column_stack([x, y]))
        if len(xy) < 2:
            continue
        seg = np.diff(xy, axis=0)
        if float(np.hypot(seg[:, 0], seg[:, 1]).sum()) < MIN_PX:
            continue
        add(
            xy[:, 0].min(),
            xy[:, 1].min(),
            xy[:, 0].max(),
            xy[:, 1].max(),
            st[0] + 2,
            (PRIORITY.index(cls), cls, "line", xy),
        )

    for cls, outer, inners in feats["polys"]:
        st = STYLE[cls].get(z)
        if st is None:
            continue
        arr = np.asarray(outer)
        x, y = world_px(arr[:, 0], arr[:, 1], z)
        oxy = simplify_line(np.column_stack([x, y]), closed=True)
        if len(oxy) < 3 or max(np.ptp(oxy[:, 0]), np.ptp(oxy[:, 1])) < MIN_PX:
            continue
        ixys = []
        for inner in inners:
            a2 = np.asarray(inner)
            ix, iy = world_px(a2[:, 0], a2[:, 1], z)
            ixy = simplify_line(np.column_stack([ix, iy]), closed=True)
            if len(ixy) >= 3 and max(np.ptp(ixy[:, 0]), np.ptp(ixy[:, 1])) >= MIN_PX:
                ixys.append(ixy)
        add(
            oxy[:, 0].min(),
            oxy[:, 1].min(),
            oxy[:, 0].max(),
            oxy[:, 1].max(),
            2,
            (PRIORITY.index(cls), cls, "poly", (oxy, ixys)),
        )

    for cls, lon, lat in feats["points"]:
        st = STYLE[cls].get(z)
        if st is None:
            continue
        x, y = world_px(lon, lat, z)
        add(
            float(x),
            float(y),
            float(x),
            float(y),
            st[0] + 2,
            (PRIORITY.index(cls), cls, "point", (float(x), float(y))),
        )

    for items in buckets.values():
        items.sort(key=lambda it: it[0])
    return buckets


def resample(xy, step):
    """폴리라인을 step 간격으로 다시 찍는다(점선·파선용). 누적 길이 s와 점 좌표를 반환."""
    seg = np.diff(xy, axis=0)
    ln = np.hypot(seg[:, 0], seg[:, 1])
    cum = np.concatenate([[0.0], np.cumsum(ln)])
    total = cum[-1]
    if total <= 0:
        return None, None
    s = np.arange(0.0, total, step)
    px = np.interp(s, cum, xy[:, 0])
    py = np.interp(s, cum, xy[:, 1])
    return s, np.column_stack([px, py])


def draw_line(d, xy, width, pattern):
    pts = [tuple(p) for p in xy]
    if pattern == "solid":
        d.line(pts, fill=255, width=width)
    elif pattern == "dash":
        s, rp = resample(xy, 1.0)
        if s is None:
            return
        on = (s % 7.0) < 4.0
        start = None
        for i in range(len(rp)):
            if on[i] and start is None:
                start = i
            if (not on[i] or i == len(rp) - 1) and start is not None:
                end = i if on[i] else i - 1
                if end > start:
                    d.line([tuple(rp[start]), tuple(rp[end])], fill=255, width=width)
                start = None
    elif pattern == "dot":
        s, rp = resample(xy, 3.0)
        if s is None:
            return
        d.point([tuple(p) for p in rp], fill=255)


def render_tile(items, z, tx, ty):
    """한 타일을 그린다. 잉크 불리언 배열(TILE×TILE) 또는 비어 있으면 None."""
    size = TILE + 2 * MARGIN
    ox, oy = tx * TILE - MARGIN, ty * TILE - MARGIN
    ink = np.zeros((size, size), dtype=bool)
    yy, xx = np.mgrid[0:size, 0:size]
    water_pattern = ((yy + oy) % 3 == 0) & ((xx + ox) % 3 == 0)
    core = (slice(MARGIN, MARGIN + TILE), slice(MARGIN, MARGIN + TILE))
    core_area = float(TILE * TILE)

    i = 0
    while i < len(items):
        pri = items[i][0]
        cls = items[i][1]
        width, pattern = STYLE[cls][z]
        layer_img = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(layer_img)
        erase = None  # 역 기호 안쪽처럼 기존 잉크를 지울 영역
        while i < len(items) and items[i][1] == cls:
            _, _, kind, data = items[i]
            if kind == "line":
                draw_line(d, data - (ox, oy), width, pattern)
            elif kind == "poly":
                oxy, ixys = data
                opts = [tuple(p) for p in oxy - (ox, oy)]
                if pattern == "fill":
                    d.polygon(opts, fill=255)
                    for ixy in ixys:
                        d.polygon([tuple(p) for p in ixy - (ox, oy)], fill=0)
                else:  # outline
                    d.line(opts + opts[:1], fill=255, width=width)
                    for ixy in ixys:
                        ipts = [tuple(p) for p in ixy - (ox, oy)]
                        d.line(ipts + ipts[:1], fill=255, width=width)
            else:  # point
                px, py = data[0] - ox, data[1] - oy
                r = width
                if pattern == "ring":
                    if erase is None:
                        erase = Image.new("L", (size, size), 0)
                    ImageDraw.Draw(erase).ellipse(
                        [px - r, py - r, px + r, py + r], fill=255
                    )
                    d.ellipse([px - r, py - r, px + r, py + r], outline=255, width=1)
                else:
                    d.ellipse([px - r, py - r, px + r, py + r], fill=255)
            i += 1
        layer = np.asarray(layer_img) > 0
        if pattern == "fill":
            layer &= water_pattern
        candidate = ink.copy()
        if erase is not None:
            candidate &= ~(np.asarray(erase) > 0)
        candidate |= layer
        if pri >= DROPPABLE_FROM and candidate[core].sum() / core_area > INK_MAX:
            continue  # 밀도 가드: 이 등급은 이 타일에서 생략
        ink = candidate

    core_ink = ink[core]
    return core_ink if core_ink.any() else None


def save_tile(core_ink, out_dir, z, tx, ty):
    img = Image.fromarray(np.where(core_ink, 0, 255).astype(np.uint8)).convert("1")
    d = os.path.join(out_dir, str(z), str(tx))
    os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, f"{ty}.png"), optimize=True)


def render_all(feats, out_dir, zooms):
    stats = {}
    for z in zooms:
        t0 = time.time()
        allowed = allowed_tiles(z)
        buckets = bucket_features(feats, z, allowed)
        written = 0
        for (tx, ty), items in buckets.items():
            core = render_tile(items, z, tx, ty)
            if core is not None:
                save_tile(core, out_dir, z, tx, ty)
                written += 1
        stats[z] = (len(allowed), written, time.time() - t0)
        print(
            f"z{z}: 영역 타일 {len(allowed)} · 기록 {written} · {stats[z][2]:.0f}s",
            flush=True,
        )
    return stats


def preview(out_dir, lat, lon, zooms, dst_dir):
    """시계 화면(176px) 크기로 타일을 이어 붙여 3배 확대 미리보기 저장."""
    os.makedirs(dst_dir, exist_ok=True)
    for z in zooms:
        cx, cy = world_px(lon, lat, z)
        cx, cy = float(cx), float(cy)
        canvas = Image.new("L", (176, 176), 255)
        x0, y0 = cx - 88, cy - 88
        for tx in range(int(x0 // TILE), int((x0 + 176) // TILE) + 1):
            for ty in range(int(y0 // TILE), int((y0 + 176) // TILE) + 1):
                p = os.path.join(out_dir, str(z), str(tx), f"{ty}.png")
                if os.path.exists(p):
                    canvas.paste(
                        Image.open(p).convert("L"),
                        (int(tx * TILE - x0), int(ty * TILE - y0)),
                    )
        d = ImageDraw.Draw(canvas)
        d.polygon([(88, 82), (84, 92), (92, 92)], fill=0)  # 현재 위치 삼각형
        canvas.resize((176 * 3, 176 * 3), Image.NEAREST).save(
            os.path.join(dst_dir, f"z{z}.png")
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("features")
    ap.add_argument("out_dir")
    ap.add_argument("--zooms", default=",".join(map(str, ZOOMS)))
    ap.add_argument("--preview", default=None, help="lat,lon")
    ap.add_argument("--preview-only", action="store_true")
    a = ap.parse_args()
    zooms = [int(s) for s in a.zooms.split(",")]
    if not a.preview_only:
        with open(a.features, "rb") as f:
            feats = pickle.load(f)
        render_all(feats, a.out_dir, zooms)
    if a.preview:
        lat, lon = (float(s) for s in a.preview.split(","))
        preview(
            a.out_dir,
            lat,
            lon,
            zooms,
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview"),
        )


if __name__ == "__main__":
    main()
