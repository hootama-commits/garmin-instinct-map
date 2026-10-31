"""타일을 만들 영역(경위도 상자). 렌더러·추출기가 공유.

- seoul: 서울시 전역(행정 경계 바깥 여유 포함)
- gimpo_home: 김포 대곶면 본가 반경 약 5km [미검증 좌표 — 대곶면 중심 근사]
"""

AREAS = [
    {"name": "seoul", "west": 126.76, "south": 37.42, "east": 127.19, "north": 37.71},
    {
        "name": "gimpo_home",
        "west": 126.50,
        "south": 37.60,
        "east": 126.63,
        "north": 37.71,
    },
]
ZOOMS = (13, 14, 15, 16)
TILE = 128
