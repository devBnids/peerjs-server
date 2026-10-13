#!/bin/bash
# 맥에서 여러 현장에 peerjs 묶음을 병렬로 설치(또는 검사)한다.
#   bash deploy/fleet.sh <check|install> <묶음.tgz> <대상.tsv> <결과디렉터리> [병렬수=20]
# 대상.tsv: site_code<TAB>host<TAB>name  (host 가 12 면 사내 별칭으로 붙는다)
# 결과: <결과디렉터리>/results.tsv (site_code host name status 마지막줄), 현장별 로그 <code>.log
set -u
MODE=$1; BUNDLE=$2; TARGETS=$3; OUT=$4; PAR=${5:-20}
case $MODE in check) FLAG=--check ;; install) FLAG= ;; *) echo "mode: check|install"; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
: > "$OUT/results.tsv"

one() {
  local code=$1 host=$2 name=$3
  local T P R=/tmp/peerjs-deploy-$$
  if [ "$host" = 12 ]; then T=12; P=22; else T=bnids@$host; P=20022; fi
  local O=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=8)
  local line st
  if ! ssh -n -p $P "${O[@]}" $T "mkdir -p $R" >"$OUT/$code.log" 2>&1; then
    st=unreachable; line=$(tail -1 "$OUT/$code.log")
  elif ! scp -q -P $P "${O[@]}" "$BUNDLE" "$HERE/install.sh" $T:$R/ >>"$OUT/$code.log" 2>&1; then
    st=copy-fail; line=$(tail -1 "$OUT/$code.log")
  else
    ssh -n -p $P "${O[@]}" $T "bash $R/install.sh $R/$(basename "$BUNDLE") $FLAG; rc=\$?; rm -rf $R; exit \$rc" >>"$OUT/$code.log" 2>&1
    line=$(grep -a 'peerjs-install result=' "$OUT/$code.log" | tail -1)
    case "$line" in
      *result=OK*|*result=CHECK-OK*) st=ok ;;
      *result=FAIL*) st=fail ;;
      *) st=unknown; line=$(tail -1 "$OUT/$code.log") ;;
    esac
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$code" "$host" "$name" "$st" "$line" >> "$OUT/results.tsv"
  echo "$st $code $host"
}
export -f one
export OUT BUNDLE HERE FLAG

grep -v '^\s*$' "$TARGETS" | tr '\t' '\034' | xargs -P "$PAR" -I{} bash -c 'IFS=$'"'"'\034'"'"' read -r c h n <<< "{}"; one "$c" "$h" "$n"' \
  | awk '{n[$1]++} END{for (k in n) printf "%s %d\n", k, n[k]}'
