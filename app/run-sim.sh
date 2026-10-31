#!/usr/bin/env bash
# 시뮬레이터에 PRG 올리기. 사용: ./run-sim.sh [instinct2]
# 시뮬레이터 창은 포커스를 뺏지 않도록 run-nofocus.vbs(최소화)로 띄운다.
set -e
cd "$(dirname "$0")"
ROOT="$HOME/Documents/garmin-instinct-map"
SDK="${CIQ_SDK:-$ROOT/vendor/sdk/9.3.0}"
DEV="${1:-instinct2}"
PRG="$PWD/bin/MonoMap-$DEV.prg"
[ -f "$PRG" ] || { echo "먼저 ./build.sh $DEV 로 빌드하세요"; exit 1; }
if ! tasklist | grep -qi simulator.exe; then
    wscript //B //Nologo "$(cygpath -w "$HOME/.claude/bin/run-nofocus.vbs")" '/min:CIQ 시뮬레이터' "$(cygpath -w "$SDK/bin/simulator.exe")" &
    sleep 6
fi
export PATH="/c/Program Files/Microsoft/jdk-17.0.21.21-hotspot/bin:$PATH"
"$SDK/bin/monkeydo" "$(cygpath -w "$PRG")" "$DEV"
