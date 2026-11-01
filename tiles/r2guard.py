"""R2 무료 한도 안전장치: 모든 R2 업로드는 이 도구로만 한다.

한도(Cloudflare R2 무료, 청구 주기 매월 31일 시작 기준): 쓰기(Class A) 월 100만 · 읽기(Class B) 월 1,000만 · 저장 10GB.
올리기 전에 장부(누적)에 올릴 분량을 더해 한도의 70%를 넘으면 거부한다. 키 값은 이 파일에 없다.

사용:
  python r2guard.py status
  python r2guard.py upload <로컬 폴더> <저장소 안 경로> [--dry-run]
  python r2guard.py note <쓰기 건수> <바이트> <메모>     # 도구 밖에서 올린 분량을 장부에 기록
  python r2guard.py watch [초]                          # 장부를 주기(기본 30초)로 보다가 안전선 도달 시 정지
  python r2guard.py kill                                # R2 관련 프로세스 즉시 종료 + 정지 잠금
  python r2guard.py reset                               # 정지 잠금 해제(사용자가 직접, 새 주기·한도 확인 후)
안전선 도달 = 쓰기·읽기·저장 중 하나라도 한도의 70% 이상 → 정지 잠금 파일 생성 + rclone·wrangler·R2 업로드 스크립트 종료.
잠금이 있으면 upload는 항상 거부된다.
환경변수 R2_KEYS = 키 파일 경로(ACCESS_KEY_ID·SECRET_ACCESS_KEY·ENDPOINT 줄), R2_BUCKET = 저장소 이름
"""

import json
import math
import os
import subprocess
import sys
import time

BUCKET = os.environ.get("R2_BUCKET", "garmin-map-tiles")
KEYS = os.environ.get(
    "R2_KEYS", os.path.expanduser("~/.claude/jobs/05f2a17e/tmp/r2keys.txt.txt")
)
LEDGER = os.path.expanduser("~/Documents/garmin-map-national/r2_ledger.json")
STOP = os.path.join(os.path.dirname(LEDGER), "r2_STOP")
LIMIT_A, LIMIT_B, LIMIT_GB = 1_000_000, 10_000_000, 10
SAFE = 0.7
# 종료 대상 명령줄(자기 자신·클로드 세션은 제외)
KILL_PATTERN = r"rclone|wrangler|r2guard\.py upload|add_area\.py|r2_upload"


def period():
    """청구 주기 시작일(매월 31일 기준 → 달이 짧으면 말일). 같은 주기 키로 장부를 나눈다."""
    t = time.localtime()
    y, m = t.tm_year, t.tm_mon
    if t.tm_mday < 31:
        m -= 1
        if m == 0:
            y, m = y - 1, 12
    return f"{y}-{m:02d}"


def load():
    try:
        d = json.load(open(LEDGER, encoding="utf-8"))
    except FileNotFoundError:
        d = {}
    p = period()
    if d.get("period") != p:
        d = {"period": p, "a": 0, "b": 0, "bytes": d.get("bytes", 0), "log": []}
    return d


def save(d):
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    json.dump(d, open(LEDGER, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def show(d):
    print(
        f"주기 {d['period']}  쓰기 {d['a']:,}/{LIMIT_A:,} ({d['a'] / LIMIT_A:.0%})  읽기 {d['b']:,}/{LIMIT_B:,}  "
        f"저장 {d['bytes'] / 1e9:.2f}/{LIMIT_GB}GB ({d['bytes'] / 1e9 / LIMIT_GB:.0%})  안전선 {SAFE:.0%}"
    )


def tripped(d):
    """안전선 도달 항목 목록(쓰기·읽기·저장)."""
    hits = []
    if d["a"] >= LIMIT_A * SAFE:
        hits.append(f"쓰기 {d['a']:,}")
    if d["b"] >= LIMIT_B * SAFE:
        hits.append(f"읽기 {d['b']:,}")
    if d["bytes"] >= LIMIT_GB * 1e9 * SAFE:
        hits.append(f"저장 {d['bytes'] / 1e9:.2f}GB")
    return hits


def kill_all():
    """R2에 쓰는 프로세스를 출처(내부·외부)와 상관없이 종료. 자기 자신은 제외.
    실행 파일 이름(rclone·wrangler·workerd·aws·s3cmd)이거나, python·node의 명령줄에 R2 업로드 흔적이 있는 것."""
    ps = (
        "Get-CimInstance Win32_Process | Where-Object {"
        f" $_.ProcessId -ne {os.getpid()} -and ("
        " $_.Name -match '^(rclone|wrangler|workerd|aws|s3cmd)(\\.exe)?$' -or"
        " ($_.Name -match '^(python|pythonw|node)(\\.exe)?$' -and"
        f" $_.CommandLine -match '{KILL_PATTERN}' -and"
        " $_.CommandLine -notmatch 'r2guard\\.py (kill|watch|status|reset|note)') ) } |"
        " ForEach-Object { Stop-Process -Id $_.ProcessId -Force; $_.ProcessId }"
    )
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True,
        text=True,
        creationflags=0x08000000,  # 창 숨김(상주 pythonw에서 깜빡임 방지)
    )
    return r.stdout.split()


def trip(reason):
    """정지 잠금 생성 + 관련 프로세스 종료."""
    os.makedirs(os.path.dirname(STOP), exist_ok=True)
    with open(STOP, "w", encoding="utf-8") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M')} {reason}\n")
    pids = kill_all()
    print(f"정지: {reason} · 종료한 프로세스 {len(pids)}개 · 잠금 {STOP}")
    alert(
        f"[R2 안전선] {reason} · 프로세스 {len(pids)}개 종료 · 업로드 잠금(reset으로만 해제)"
    )


def alert(text):
    """카카오 클로대리로 호민에게 알림(실패해도 정지 동작은 유지). 키·비밀값은 넣지 않음."""
    try:
        sys.path.insert(0, os.path.expanduser("~/.claude/tools/kakao-bot"))
        import send_friend

        send_friend.send("Homin", text)
        print("클로대리 알림 전송")
    except Exception as e:
        print(f"클로대리 알림 실패: {e}")


def keys():
    kv = {}
    for line in open(KEYS, encoding="utf-8-sig"):
        if "=" in line:
            k, v = line.strip().split("=", 1)
            kv[k.strip()] = v.strip()
    return kv


def scan(folder):
    n = size = 0
    for r, _, files in os.walk(folder):
        for f in files:
            n += 1
            size += os.path.getsize(os.path.join(r, f))
    return n, size


def upload(folder, remote, dry):
    if os.path.exists(STOP):
        sys.exit(
            f"거부: 정지 잠금이 있음({open(STOP, encoding='utf-8').read().strip()}) — 사용자가 reset 해야 풀림"
        )
    d = load()
    n, size = scan(folder)
    lists = math.ceil(n / 1000) + 5  # 목록 조회는 1,000개당 쓰기 1건
    need_a = n + lists
    new_a, new_bytes = d["a"] + need_a, d["bytes"] + size
    print(f"올릴 파일 {n:,}개 · {size / 1e6:.1f}MB · 쓰기 약 {need_a:,}건")
    show(d)
    if new_a > LIMIT_A * SAFE:
        trip(f"쓰기가 {new_a:,}건이 되어 안전선 {int(LIMIT_A * SAFE):,}건 초과 예상")
        sys.exit(1)
    if new_bytes > LIMIT_GB * 1e9 * SAFE:
        trip(
            f"저장이 {new_bytes / 1e9:.2f}GB가 되어 안전선 {LIMIT_GB * SAFE:.0f}GB 초과 예상"
        )
        sys.exit(1)
    if dry:
        print("dry-run: 통과(올리지 않음)")
        return
    kv = keys()
    env = dict(
        os.environ,
        RCLONE_CONFIG_R2_TYPE="s3",
        RCLONE_CONFIG_R2_PROVIDER="Cloudflare",
        RCLONE_CONFIG_R2_ACCESS_KEY_ID=kv["ACCESS_KEY_ID"],
        RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=kv["SECRET_ACCESS_KEY"],
        RCLONE_CONFIG_R2_ENDPOINT=kv["ENDPOINT"],
        RCLONE_CONFIG_R2_NO_CHECK_BUCKET="true",
    )
    cmd = [
        "rclone",
        "copy",
        folder,
        f"r2:{BUCKET}/{remote}",
        "--transfers",
        "32",
        "--checkers",
        "32",
        "--retries",
        "1",
        "--low-level-retries",
        "3",
        "--stats",
        "120s",
        "--stats-one-line",
        "--log-level",
        "NOTICE",
    ]
    proc = subprocess.Popen(cmd, env=env)
    while proc.poll() is None:  # 업로드 중에도 잠금·장부 감시
        time.sleep(5)
        if os.path.exists(STOP) or tripped(load()):
            proc.kill()
            trip("업로드 중 안전선 도달")
            break
    rc = proc.wait()
    # 실패해도 시도한 만큼을 보수적으로 기록(상한 추정)
    d["a"] = new_a
    d["bytes"] = new_bytes
    d["log"].append(
        {
            "t": time.strftime("%Y-%m-%d %H:%M"),
            "upload": remote,
            "files": n,
            "mb": round(size / 1e6, 1),
            "rc": rc,
        }
    )
    save(d)
    show(d)
    if tripped(d):
        trip("업로드 후 안전선 도달")
    sys.exit(rc)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "status":
        show(load())
    elif a[0] == "upload" and len(a) >= 3:
        upload(a[1], a[2].strip("/"), "--dry-run" in a)
    elif a[0] == "note" and len(a) >= 4:
        d = load()
        d["a"] += int(a[1])
        d["bytes"] += int(a[2])
        d["log"].append(
            {
                "t": time.strftime("%Y-%m-%d %H:%M"),
                "note": " ".join(a[3:]),
                "a": int(a[1]),
                "bytes": int(a[2]),
            }
        )
        save(d)
        show(d)
        if tripped(d):
            trip("기록 후 안전선 도달")
    elif a[0] == "watch":
        sec = int(a[1]) if len(a) > 1 else 30
        while True:
            d = load()
            hits = tripped(d)
            if hits or os.path.exists(STOP):
                if not os.path.exists(STOP):
                    trip("감시 중 안전선 도달: " + ", ".join(hits))
                else:
                    kill_all()  # 잠금 중에는 어디서 새로 뜨든 계속 종료
            time.sleep(sec)
    elif a[0] == "kill":
        trip("수동 kill")
    elif a[0] == "reset":
        if os.path.exists(STOP):
            os.remove(STOP)
        print("정지 잠금 해제됨")
        show(load())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
