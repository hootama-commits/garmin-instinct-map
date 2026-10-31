#!/usr/bin/env bash
# 시계(USB 대용량 저장장치)에 PRG 복사. 사용: ./install.sh [instinct2] [드라이브 문자, 기본 D]
set -e
cd "$(dirname "$0")"
DEV="${1:-instinct2}"
DRV="${2:-D}"
PRG="bin/MonoMap-$DEV.prg"
DST="/$(echo "$DRV" | tr 'A-Z' 'a-z')/GARMIN/APPS"
[ -f "$PRG" ] || { echo "먼저 ./build.sh $DEV 로 빌드하세요"; exit 1; }
[ -d "$DST" ] || { echo "시계 폴더 $DST 없음 — USB 연결과 드라이브 문자 확인"; exit 1; }
cp -v "$PRG" "$DST/MonoMap.prg"
echo "복사 완료. 시계를 안전 제거하면 앱 목록(활동 → 더보기)에 Mono Map이 나타남"
