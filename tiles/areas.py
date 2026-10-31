"""타일을 만들 영역(경위도 상자). 렌더러·추출기가 공유.

maxz = 그 영역에서 만들 가장 큰 축척(생략하면 16). 넓은 영역은 15까지만 만들어 용량을 줄임.
- capital: 서울·인천·경기 수도권 전체(축척 15까지)
- seoul: 서울시 전역(행정 경계 바깥 여유 포함)
- incheon: 인천 본토·영종·강화 남부
- gimpo_home: 김포 대곶면 본가 반경 약 5km [미검증 좌표 — 대곶면 중심 근사]
"""

AREAS = [
    {
        "name": "capital",
        "west": 126.30,
        "south": 36.90,
        "east": 127.90,
        "north": 38.30,
        "maxz": 15,
    },
    {"name": "seoul", "west": 126.76, "south": 37.42, "east": 127.19, "north": 37.71},
    {"name": "incheon", "west": 126.35, "south": 37.28, "east": 126.82, "north": 37.62},
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
