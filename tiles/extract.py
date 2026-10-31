"""OSM PBF에서 지도 표현에 쓸 지형지물만 뽑아 중간 파일(pickle)로 저장.

렌더링(render.py)과 분리한 이유: PBF 1회 읽기가 수 분 걸리므로 축척별 규칙을
바꿀 때마다 다시 읽지 않기 위함.

사용: python extract.py <south-korea-latest.osm.pbf> <features.pkl>
"""

import pickle
import sys
from collections import Counter

import osmium

from areas import AREAS

MAJOR = {"motorway", "trunk", "motorway_link", "trunk_link"}
ARTERIAL = {"primary", "primary_link"}
COLLECTOR = {"secondary", "secondary_link", "tertiary", "tertiary_link"}
LOCAL = {"residential", "unclassified", "living_street"}
PATH = {"footway", "path", "pedestrian", "cycleway", "steps", "track", "bridleway"}
WATER_AREA_TAGS = (
    ("natural", "water"),
    ("waterway", "riverbank"),
    ("landuse", "reservoir"),
    ("landuse", "basin"),
)
GREEN_TAGS = (
    ("leisure", "park"),
    ("landuse", "forest"),
    ("natural", "wood"),
    ("leisure", "golf_course"),
    ("leisure", "garden"),
    ("landuse", "cemetery"),
)


def road_class(tags):
    h = tags.get("highway")
    if h in MAJOR:
        return "major"
    if h in ARTERIAL:
        return "arterial"
    if h in COLLECTOR:
        return "collector"
    if h in LOCAL:
        return "local"
    if h in PATH:
        return "path"
    return None


def in_any_area(lon, lat):
    for a in AREAS:
        if a["west"] <= lon <= a["east"] and a["south"] <= lat <= a["north"]:
            return True
    return False


class Handler(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.lines = []  # (cls, [(lon, lat), ...])
        self.polys = []  # (cls, outer_ring, [inner_ring, ...])
        self.points = []  # (cls, lon, lat)

    def node(self, n):
        t = n.tags
        if t.get("railway") != "station" and t.get("public_transport") != "station":
            return
        if not n.location.valid() or not in_any_area(n.location.lon, n.location.lat):
            return
        if t.get("station") == "subway" or t.get("subway") == "yes":
            self.points.append(("subway_station", n.location.lon, n.location.lat))
        elif t.get("railway") == "station":
            self.points.append(("rail_station", n.location.lon, n.location.lat))

    def way(self, w):
        t = w.tags
        cls = road_class(t)
        if cls is None:
            rw = t.get("railway")
            in_tunnel = t.get("tunnel") in ("yes", "building_passage")
            if rw in ("rail", "light_rail", "narrow_gauge", "subway") and not in_tunnel:
                cls = "rail"
            elif t.get("waterway") in ("river", "canal"):
                cls = "river"
            elif t.get("waterway") == "stream":
                cls = "stream"
        if cls is None:
            return
        coords = []
        hit = False
        for n in w.nodes:
            if not n.location.valid():
                continue
            lon, lat = n.location.lon, n.location.lat
            coords.append((lon, lat))
            if not hit and in_any_area(lon, lat):
                hit = True
        if hit and len(coords) >= 2:
            self.lines.append((cls, coords))

    def area(self, a):
        t = a.tags
        cls = None
        for k, v in WATER_AREA_TAGS:
            if t.get(k) == v:
                cls = "water"
                break
        if cls is None:
            for k, v in GREEN_TAGS:
                if t.get(k) == v:
                    cls = "green"
                    break
        if cls is None:
            return
        for ring in a.outer_rings():
            outer = [(n.lon, n.lat) for n in ring if n.location.valid()]
            if len(outer) < 4 or not any(in_any_area(lon, lat) for lon, lat in outer):
                continue
            inners = []
            for ir in a.inner_rings(ring):
                inner = [(n.lon, n.lat) for n in ir if n.location.valid()]
                if len(inner) >= 4:
                    inners.append(inner)
            self.polys.append((cls, outer, inners))


def main(src, dst):
    h = Handler()
    h.apply_file(src, locations=True, idx="flex_mem")
    with open(dst, "wb") as f:
        pickle.dump(
            {"lines": h.lines, "polys": h.polys, "points": h.points}, f, protocol=5
        )
    print("lines", Counter(c for c, _ in h.lines))
    print("polys", Counter(c for c, _, _ in h.polys))
    print("points", Counter(c for c, _, _ in h.points))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
