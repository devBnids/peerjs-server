#!/bin/bash
# 현장 설치: peerjs 를 묶음 하나로 통일하고 systemd 로만 돌린다.
#   bash install.sh <peerjs-bundle-*.tgz> [--enable]
# bnids 로 실행(sudo -n 필요). 결과는 마지막 한 줄 "peerjs-install ..." 로 낸다.
# ssh 가 끊겨도 끝까지 돈다(nohup) — 전체 기록은 /usr/local/bnids/backup/peerjs-<시각>/install.log
#
# 하는 일
#  1. 설치 위치: 기존 것을 쓴다(encrypted/git → 옛 /usr/local/bnids/peerjs-server 순), 없으면 후자에 새로 깐다
#  2. 기존 bin·dist·node_modules·unit(enable 상태 포함)·nginx 설정을 백업
#  3. nginx 의 proxy_pass https://…:9000 → http:// (peerjs 는 이제 127.0.0.1 평문). nginx -t 를 먼저 통과해야 진행
#  4. 옛 프로세스(systemd·pm2 run·떠돌이)를 멈추고 파일 교체, 표준 unit 기록
#  5. 원래 돌고 있었거나 --enable 이면 켜고 확인(직접·nginx 경유). 실패·중단되면 전부 되돌린다
#  6. 성공하면 pm2 run 을 지우고, pm2 에 남은 앱이 없으면 pm2 자체를 끈다(부팅 시 재기동 해제)
# pipefail 은 쓰지 않는다 — `| grep -q` 가 앞 명령을 일찍 끊으면(SIGPIPE) 정상도 실패로 읽힌다
set -u

TS=${PEERJS_INSTALL_TS:-$(date +%Y%m%d-%H%M%S)}
BK=/usr/local/bnids/backup/peerjs-$TS
S="sudo -n"

# ssh 가 끊겨도 중간에 죽지 않게 자기 자신을 nohup 으로 다시 띄우고 끝날 때까지 기다린다
if [ -z "${PEERJS_INSTALL_INNER:-}" ]; then
  $S true 2>/dev/null || { echo "peerjs-install result=FAIL step=preflight sudo"; exit 1; }
  $S mkdir -p "$BK" && $S chown "$(id -un)" "$BK" || { echo "peerjs-install result=FAIL step=preflight backup-dir"; exit 1; }
  PEERJS_INSTALL_INNER=1 PEERJS_INSTALL_TS=$TS nohup bash "$0" "$@" >"$BK/install.log" 2>&1 </dev/null
  rc=$?
  tail -1 "$BK/install.log"
  exit $rc
fi

BUNDLE=${1:?bundle}
ENABLE=0; [ "${2:-}" = "--enable" ] && ENABLE=1
UNIT=/etc/systemd/system/peerjs.service
say() { echo "peerjs-install $*"; }
fail() { say "result=FAIL step=$1 ${2:-} backup=$BK"; exit 1; }

[ -r "$BUNDLE" ] || fail preflight "bundle"
NODE=$(command -v node) || fail preflight "node"

D=""
for d in /usr/local/bnids/encrypted/git/peerjs-server /usr/local/bnids/peerjs-server; do
  [ -f "$d/bin/peerjs" ] && { D=$d; break; }
done
FRESH=0
[ -z "$D" ] && { D=/usr/local/bnids/peerjs-server; FRESH=1; }
OWNER=$(stat -c %U "$D" 2>/dev/null || id -un)

# 지금 상태
pids() { for p in $(pgrep -x node); do tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | grep -q 'bin/peerjs --port' && echo $p; done; }
probe_direct() {
  local o; o=$(curl -s -m 2 http://127.0.0.1:9000/myapp/ 2>/dev/null); [[ $o == *PeerJS* ]] && return 0
  o=$(curl -sk -m 2 https://127.0.0.1:9000/myapp/ 2>/dev/null); [[ $o == *PeerJS* ]]   # 옛 판(TLS) 되돌림 확인용
}
probe_nginx() { local o; o=$(curl -sk -m 3 https://127.0.0.1/webrtc/ 2>/dev/null); [[ $o == *PeerJS* ]]; }
PM2_RUN=0
command -v pm2 >/dev/null && [ "$(pm2 pid run 2>/dev/null | tr -cd 0-9)" -gt 0 ] 2>/dev/null && PM2_RUN=1
PM2_HAS_RUN=0
command -v pm2 >/dev/null && pm2 jlist 2>/dev/null | grep -q '"name":"run"' && PM2_HAS_RUN=1
WAS_RUNNING=0; { [ -n "$(pids)" ] || [ $PM2_RUN = 1 ]; } && WAS_RUNNING=1
UNIT_ENABLED=$(systemctl is-enabled peerjs 2>/dev/null || true)
NGINX_BEFORE=0; probe_nginx && NGINX_BEFORE=1
OLD_VER=$(cat "$D/VERSION" 2>/dev/null || md5sum "$D/bin/peerjs" 2>/dev/null | cut -c1-8)
START=$(( WAS_RUNNING || ENABLE ))
say "state dir=$D fresh=$FRESH running=$WAS_RUNNING pm2_run=$PM2_RUN unit=$UNIT_ENABLED nginx_ok=$NGINX_BEFORE old=$OLD_VER"

# 백업
if [ $FRESH = 0 ]; then
  $S tar czf "$BK/tree.tgz" -C "$D" $(cd "$D" && ls -d bin dist node_modules package.json package-lock.json VERSION 2>/dev/null) || fail backup tree
fi
[ -f $UNIT ] && $S cp -p $UNIT "$BK/peerjs.service"
NGX=$($S grep -lE 'proxy_pass[[:space:]]+https://[^;[:space:]]+:9000' /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/* 2>/dev/null)
for f in $NGX; do $S cp -p "$f" "$BK/nginx.$(echo "$f" | tr / _)" || fail backup nginx; done

restore_nginx() {
  for f in $NGX; do $S cp -p "$BK/nginx.$(echo "$f" | tr / _)" "$f"; done
}

# nginx: 먼저 고치고 검사만(아직 reload 안 함)
for f in $NGX; do
  $S sed -i -E 's#(proxy_pass[[:space:]]+)https://([^/;[:space:]]+):9000#\1http://\2:9000#g' "$f"
done
if [ -n "$NGX" ] && ! $S nginx -t >/dev/null 2>&1; then
  restore_nginx; fail nginx-test
fi

# 새 트리 준비·검사(교체 전에)
NEW=$(mktemp -d)
tar xzf "$BUNDLE" -C "$NEW" --no-same-owner 2>/dev/null || { restore_nginx; fail extract; }
NEW_VER=$(cat "$NEW/VERSION" 2>/dev/null)
[ -n "$NEW_VER" ] || { restore_nginx; fail extract "no VERSION"; }
"$NODE" -e 'new (require("vm").Script)(require("fs").readFileSync(process.argv[1], "utf8").replace(/^#!.*/, ""))' "$NEW/bin/peerjs" >/dev/null 2>&1 && (cd "$NEW" && "$NODE" -e 'require("./dist/src"); require("./bin/client-log"); require("winston"); require("winston-daily-rotate-file"); require("yargs")') >/dev/null 2>&1 \
  || { restore_nginx; fail bundle-check "node $($NODE -v)"; }

rollback() {
  trap '' HUP INT TERM
  $S systemctl stop peerjs 2>/dev/null
  if [ $FRESH = 0 ]; then
    $S rm -rf "$D/bin" "$D/dist" "$D/node_modules" "$D/VERSION"
    $S tar xzf "$BK/tree.tgz" -C "$D"
  fi
  if [ -f "$BK/peerjs.service" ]; then $S cp -p "$BK/peerjs.service" $UNIT; else $S rm -f $UNIT; fi
  $S systemctl daemon-reload
  case "$UNIT_ENABLED" in
    enabled) $S systemctl enable peerjs >/dev/null 2>&1 ;;
    *) $S systemctl disable peerjs >/dev/null 2>&1 ;;
  esac
  restore_nginx; [ -n "$NGX" ] && $S systemctl reload nginx
  if [ $PM2_RUN = 1 ]; then pm2 start run >/dev/null 2>&1
  elif [ $WAS_RUNNING = 1 ]; then $S systemctl start peerjs; fi
  RB=down
  [ $WAS_RUNNING = 0 ] && RB=off
  if [ $WAS_RUNNING = 1 ]; then
    for i in $(seq 1 20); do probe_direct && { RB=up; break; }; sleep 0.5; done
  fi
}
# 여기서부터 중단되면 되돌린다
trap 'rollback; fail interrupted "rolled-back=$RB"' HUP INT TERM

# 옛 프로세스 멈춤 — 옛 판은 SIGTERM 뒤 열린 웹소켓을 끝까지 기다린다(systemd 90초). 2초만 주고 끊는다
[ $PM2_RUN = 1 ] && pm2 stop run >/dev/null 2>&1
$S systemctl stop --no-block peerjs 2>/dev/null
for p in $(pids); do $S kill $p 2>/dev/null; done
sleep 2
$S systemctl kill -s KILL peerjs 2>/dev/null
for p in $(pids); do $S kill -9 $p 2>/dev/null; done
$S systemctl stop peerjs 2>/dev/null
sleep 2
# 다른 계정의 pm2 같은 모르는 관리자가 되살리면 둘이 9000 을 두고 싸운다 — 중단
if [ -n "$(pids)" ]; then
  rollback; fail respawn "unknown manager $(for p in $(pids); do ps -o user=,ppid= -p $p; done | tr -s ' ' | tr '\n' ' ') rolled-back=$RB"
fi

# 교체(실패하면 되돌림)
copy_ok=1
$S mkdir -p "$D" || copy_ok=0
$S rm -rf "$D/bin" "$D/dist" "$D/node_modules" "$D/package-lock.json" || copy_ok=0
$S cp -R "$NEW/bin" "$NEW/dist" "$NEW/node_modules" "$NEW/package.json" "$NEW/package-lock.json" "$NEW/VERSION" "$D/" || copy_ok=0
$S chown -R "$OWNER": "$D/bin" "$D/dist" "$D/node_modules" "$D/package.json" "$D/package-lock.json" "$D/VERSION" || copy_ok=0
[ "$(cat "$D/VERSION" 2>/dev/null)" = "$NEW_VER" ] || copy_ok=0
(cd "$D" && "$NODE" -e 'require("./dist/src"); require("./bin/client-log"); require("winston")') >/dev/null 2>&1 || copy_ok=0
rm -rf "$NEW"
[ $copy_ok = 1 ] || { rollback; fail copy "rolled-back=$RB"; }

$S tee $UNIT >/dev/null <<EOF
[Unit]
Description=peerjs (realtime camera signaling)
After=network.target

[Service]
Type=simple
ExecStart=$NODE $D/bin/peerjs --port 9000 --key peerjs --path /myapp
Restart=on-failure
RestartSec=5s
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
$S systemctl daemon-reload

NGX_AFTER=skip
if [ $START = 1 ]; then
  $S systemctl enable peerjs >/dev/null 2>&1
  $S systemctl start peerjs
  ok=0
  for i in $(seq 1 20); do probe_direct && { ok=1; break; }; sleep 0.5; done
  [ $ok = 1 ] || { rollback; fail start "rolled-back=$RB"; }
else
  # 원래 꺼져 있던 현장은 파일·unit 만 맞추고 꺼 둔다
  $S systemctl disable peerjs >/dev/null 2>&1
fi
if [ -n "$NGX" ]; then
  $S systemctl reload nginx || { rollback; fail nginx-reload "rolled-back=$RB"; }
fi
if [ $START = 1 ]; then
  # 설치 전에 nginx 로 닿던 현장이면 설치 후에도 닿아야 한다(gate.local 이 루프백이 아닌 현장 등)
  NGX_AFTER=fail
  for i in $(seq 1 10); do probe_nginx && { NGX_AFTER=ok; break; }; sleep 0.5; done
  if [ $NGINX_BEFORE = 1 ] && [ $NGX_AFTER = fail ]; then rollback; fail nginx-probe "rolled-back=$RB"; fi
fi
trap - HUP INT TERM

# pm2 정리(성공한 뒤에만)
PM2_STATE=none
if [ $PM2_HAS_RUN = 1 ]; then
  pm2 delete run >/dev/null 2>&1
  pm2 save --force >/dev/null 2>&1
  if [ -z "$(pm2 jlist 2>/dev/null | grep -o '"name":"[^"]*"' | grep -v pm2-logrotate)" ]; then
    $S systemctl disable "pm2-$(id -un)" >/dev/null 2>&1
    pm2 kill >/dev/null 2>&1
    PM2_STATE=removed
  else
    PM2_STATE=kept-other-apps
  fi
fi

LISTEN=$(awk '$2 ~ /:2328$/ && $4=="0A"{print $2}' /proc/net/tcp /proc/net/tcp6 2>/dev/null | head -1)
say "result=OK dir=$D old=$OLD_VER new=$NEW_VER started=$START active=$(systemctl is-active peerjs) enabled=$(systemctl is-enabled peerjs 2>/dev/null) procs=$(pids | wc -l) listen=$LISTEN nginx_files=$(echo $NGX | wc -w) via_nginx=$NGX_AFTER pm2=$PM2_STATE backup=$BK"
