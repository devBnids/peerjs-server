#!/bin/bash
# 현장 설치: peerjs 를 묶음 하나로 통일하고 systemd 로만 돌린다.
#   bash install.sh <peerjs-bundle-*.tgz> [--enable]
# bnids 로 실행(sudo -n 필요). 결과는 마지막 한 줄 "peerjs-install ..." 로 낸다.
#
# 하는 일
#  1. 설치 위치: 기존 것을 쓴다(encrypted/git → 옛 /usr/local/bnids/peerjs-server 순), 없으면 후자에 새로 깐다
#  2. 기존 bin·dist·node_modules·unit·nginx 설정을 백업(/usr/local/bnids/backup/peerjs-<시각>)
#  3. nginx 의 proxy_pass https://…:9000 → http:// (peerjs 는 이제 127.0.0.1 평문). nginx -t 를 먼저 통과해야 진행
#  4. 옛 프로세스(systemd·pm2 run·떠돌이)를 멈추고 파일 교체, 표준 unit 기록
#  5. 원래 돌고 있었거나 --enable 이면 켜고 확인. 실패하면 전부 되돌린다
#  6. 성공하면 pm2 run 을 지우고, pm2 에 남은 앱이 없으면 pm2 자체를 끈다(부팅 시 재기동 해제)
set -uo pipefail

BUNDLE=${1:?bundle}
ENABLE=0; [ "${2:-}" = "--enable" ] && ENABLE=1
TS=$(date +%Y%m%d-%H%M%S)
BK=/usr/local/bnids/backup/peerjs-$TS
UNIT=/etc/systemd/system/peerjs.service
S="sudo -n"
say() { echo "peerjs-install $*"; }
fail() { say "result=FAIL step=$1 ${2:-}"; exit 1; }

$S true 2>/dev/null || fail preflight "sudo"
[ -r "$BUNDLE" ] || fail preflight "bundle"
NODE=$(command -v node) || fail preflight "node"

D=""
for d in /usr/local/bnids/encrypted/git/peerjs-server /usr/local/bnids/peerjs-server; do
  [ -f "$d/bin/peerjs" ] && { D=$d; break; }
done
FRESH=0
[ -z "$D" ] && { D=/usr/local/bnids/peerjs-server; FRESH=1; }
OWNER=$(stat -c %U "$D" 2>/dev/null || echo bnids)

# 지금 상태
pids() { for p in $(pgrep -x node); do tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | grep -q 'bin/peerjs --port' && echo $p; done; }
PM2_RUN=0
command -v pm2 >/dev/null && pm2 jlist 2>/dev/null | grep -q '"name":"run"' && PM2_RUN=1
WAS_RUNNING=0; [ -n "$(pids)" ] && WAS_RUNNING=1
OLD_VER=$(cat "$D/VERSION" 2>/dev/null || md5sum "$D/bin/peerjs" 2>/dev/null | cut -c1-8)
START=$(( WAS_RUNNING || ENABLE ))

# 백업
$S mkdir -p "$BK" || fail backup
if [ $FRESH = 0 ]; then
  $S tar czf "$BK/tree.tgz" -C "$D" $(cd "$D" && ls -d bin dist node_modules package.json package-lock.json VERSION 2>/dev/null) || fail backup tree
fi
[ -f $UNIT ] && $S cp -p $UNIT "$BK/peerjs.service"
NGX=$($S grep -lE 'proxy_pass[[:space:]]+https://[^;[:space:]]+:9000' /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/* 2>/dev/null)
for f in $NGX; do $S cp -p "$f" "$BK/nginx.$(echo "$f" | tr / _)"; done

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

# 새 트리 준비
NEW=$(mktemp -d)
tar xzf "$BUNDLE" -C "$NEW" --no-same-owner 2>/dev/null || { restore_nginx; fail extract; }
NEW_VER=$(cat "$NEW/VERSION")

# 옛 프로세스 멈춤
# 옛 판은 SIGTERM 뒤 열린 웹소켓을 끝까지 기다린다(systemd 90초). 2초만 주고 끊는다
[ $PM2_RUN = 1 ] && pm2 stop run >/dev/null 2>&1
$S systemctl stop --no-block peerjs 2>/dev/null
for p in $(pids); do $S kill $p 2>/dev/null; done
sleep 2
$S systemctl kill -s KILL peerjs 2>/dev/null
for p in $(pids); do $S kill -9 $p 2>/dev/null; done
$S systemctl stop peerjs 2>/dev/null

# 교체
$S mkdir -p "$D"
$S rm -rf "$D/bin" "$D/dist" "$D/node_modules" "$D/package-lock.json"
$S cp -R "$NEW/bin" "$NEW/dist" "$NEW/node_modules" "$NEW/package.json" "$NEW/package-lock.json" "$NEW/VERSION" "$D/"
$S chown -R "$OWNER": "$D/bin" "$D/dist" "$D/node_modules" "$D/package.json" "$D/package-lock.json" "$D/VERSION" 2>/dev/null
rm -rf "$NEW"

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

rollback() {
  $S systemctl stop peerjs 2>/dev/null
  if [ $FRESH = 0 ]; then
    $S rm -rf "$D/bin" "$D/dist" "$D/node_modules" "$D/VERSION"
    $S tar xzf "$BK/tree.tgz" -C "$D"
  fi
  if [ -f "$BK/peerjs.service" ]; then $S cp -p "$BK/peerjs.service" $UNIT; else $S rm -f $UNIT; fi
  $S systemctl daemon-reload
  restore_nginx; [ -n "$NGX" ] && $S systemctl reload nginx
  if [ $PM2_RUN = 1 ]; then pm2 start run >/dev/null 2>&1
  elif [ $WAS_RUNNING = 1 ]; then $S systemctl start peerjs; fi
  for i in $(seq 1 20); do [ -n "$(pids)" ] && curl -sk -m 2 http://127.0.0.1:9000/myapp/ https://127.0.0.1:9000/myapp/ 2>/dev/null | grep -q PeerJS && return; sleep 0.5; done
}

if [ $START = 1 ]; then
  $S systemctl enable peerjs >/dev/null 2>&1
  $S systemctl start peerjs
  ok=0
  for i in $(seq 1 20); do
    curl -s -m 2 http://127.0.0.1:9000/myapp/ 2>/dev/null | grep -q 'PeerJS' && { ok=1; break; }
    sleep 0.5
  done
  if [ $ok = 0 ]; then rollback; fail start "rolled-back"; fi
else
  # 원래 꺼져 있던 현장은 파일·unit 만 맞추고 꺼 둔다
  $S systemctl disable peerjs >/dev/null 2>&1
fi
[ -n "$NGX" ] && { $S systemctl reload nginx || { rollback; fail nginx-reload "rolled-back"; }; }

# pm2 정리(성공한 뒤에만)
PM2_STATE=none
if [ $PM2_RUN = 1 ]; then
  pm2 delete run >/dev/null 2>&1
  pm2 save --force >/dev/null 2>&1
  if [ -z "$(pm2 jlist 2>/dev/null | grep -o '"name":"[^"]*"' | grep -v pm2-logrotate)" ]; then
    $S systemctl disable "pm2-$(whoami)" >/dev/null 2>&1
    pm2 kill >/dev/null 2>&1
    PM2_STATE=removed
  else
    PM2_STATE=kept-other-apps
  fi
fi

LISTEN=$(awk '$2 ~ /:2328$/ && $4=="0A"{print $2}' /proc/net/tcp /proc/net/tcp6 2>/dev/null | head -1)
say "result=OK dir=$D old=$OLD_VER new=$NEW_VER started=$START active=$(systemctl is-active peerjs) enabled=$(systemctl is-enabled peerjs 2>/dev/null) procs=$(pids | wc -l) listen=$LISTEN nginx_files=$(echo $NGX | wc -w) pm2=$PM2_STATE backup=$BK"
