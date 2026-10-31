"""원하는 위치의 지도를 추가한다: 중심 좌표 + 반경(km) → areas.py에 등록 → 그 지역 벡터 타일만 생성.

사용: python add_area.py <이름> <위도> <경도> <반경km> [--features tiles/data/features.pkl] [--vec-dir ../docs/v]
예)   python add_area.py jeju_airport 33.5113 126.4930 8
이름은 영문·숫자·밑줄만. 같은 이름이 있으면 범위를 덮어쓴다.
한국 밖 지역은 먼저 그 나라의 OSM 추출(.pbf)을 받아 extract.py로 features.pkl을 다시 만들어야 한다.
끝나면 생성된 docs/v를 커밋·푸시하면 시계가 그 지역 타일을 받는다(GitHub Pages 반영 1~2분).
"""

import argparse
import math
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AREAS_PY = os.path.join(HERE, "areas.py")


def bbox(lat, lon, radius_km):
    dlat = radius_km / 111.32
    dlon = radius_km / (111.32 * math.cos(math.radians(lat)))
    return lon - dlon, lat - dlat, lon + dlon, lat + dlat


def register(name, west, south, east, north):
    src = open(AREAS_PY, encoding="utf-8").read()
    entry = (
        f'    {{"name": "{name}", "west": {west:.4f}, "south": {south:.4f}, '
        f'"east": {east:.4f}, "north": {north:.4f}}},\n'
    )
    old = re.search(rf'    \{{"name": "{name}".*?\}},\n', src, re.S)
    if old:
        src = src.replace(old.group(0), entry, 1)
    else:
        marker = "]\nZOOMS"
        assert marker in src, "areas.py 형식이 달라 자동 등록 불가"
        src = src.replace(marker, entry + marker, 1)
    open(AREAS_PY, "w", encoding="utf-8").write(src)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("lat", type=float)
    ap.add_argument("lon", type=float)
    ap.add_argument("radius_km", type=float)
    ap.add_argument(
        "--features",
        default=os.path.expanduser(
            "~/Documents/garmin-instinct-map/tiles/data/features.pkl"
        ),
    )
    ap.add_argument("--vec-dir", default=os.path.join(HERE, "..", "docs", "v"))
    a = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", a.name):
        sys.exit("이름은 영문·숫자·밑줄만 쓸 수 있습니다")
    if not 0.5 <= a.radius_km <= 40:
        sys.exit("반경은 0.5~40km 사이로 (넓을수록 타일이 제곱으로 늘어남)")
    w, s, e, n = bbox(a.lat, a.lon, a.radius_km)
    register(a.name, w, s, e, n)
    print(f"등록: {a.name} 서{w:.4f} 남{s:.4f} 동{e:.4f} 북{n:.4f}")
    cmd = [
        sys.executable,
        "-X",
        "utf8",
        os.path.join(HERE, "render.py"),
        a.features,
        os.path.join(HERE, "..", "docs", "t"),
        "--vec-dir",
        a.vec_dir,
        "--no-png",
        "--only",
        a.name,
    ]
    subprocess.run(cmd, check=True, cwd=HERE)


if __name__ == "__main__":
    main()
