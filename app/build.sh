#!/usr/bin/env bash
# 인스팅트2용 PRG 빌드. 사용: ./build.sh [instinct2|instinct2s|instinct2x]
# 전제: vendor/sdk/9.3.0 압축 해제 · SDK 관리자로 기기 정의 받음(%APPDATA%/Garmin/ConnectIQ/Devices) · OpenJDK 17
set -e
cd "$(dirname "$0")"
ROOT="$HOME/Documents/garmin-instinct-map"
SDK="${CIQ_SDK:-$ROOT/vendor/sdk/9.3.0}"
JAVA="${CIQ_JAVA:-/c/Program Files/Microsoft/jdk-17.0.21.21-hotspot/bin/java.exe}"
DEV="${1:-instinct2}"
mkdir -p bin
"$JAVA" -Xms1g -Dfile.encoding=UTF-8 -jar "$(cygpath -w "$SDK/bin/monkeybrains.jar")" \
    -o "$(cygpath -w "$PWD/bin/MonoMap-$DEV.prg")" \
    -f "$(cygpath -w "$PWD/monkey.jungle")" \
    -y "$(cygpath -w "$ROOT/keys/developer_key.der")" \
    -d "$DEV" -w -l 0
ls -la bin
