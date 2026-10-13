
# 실시간 PeerJS PM2 설치 및 사용 법 

pm2 설치 
``` bash 
sudo npm i -g pm2 
```

run.sh 파일 생성 
``` bash 
vi /usr/local/bnids/peerjs-server/bin/run.sh 
```

run.sh 파일 
``` bash
#!bin/bash
/usr/local/bnids/peerjs-server/bin/peerjs --port 9000 --key peerjs --path /myapp
```

pm2 시작
``` bash 
pm2 start /usr/local/bnids/peerjs-server/bin/run.sh 
```

pm2 상태 확인 
``` bash 
pm2 status 
```

pm2 log 확인 
``` bash 
pm2 logs 
```

pm2 중지
``` bash 
pm2 kill 
```


---

## 2026-10-13 통일판 — 이 아래가 현행이다 (위의 pm2 안내는 폐기)

### 무엇이 바뀌었나

| | 이전 | 지금 |
|---|---|---|
| 실행 | pm2 `run`(65곳) 또는 systemd, 둘 다 뜬 곳도 3곳 | **systemd `peerjs.service` 하나** (`Restart=on-failure`, `TimeoutStopSec=10`) |
| 치명 오류 | `uncaughtException` 을 삼켜 포트도 못 잡은 채 살아 있음 | 기록하고 `exit(1)` → systemd 가 5초 뒤 재기동 |
| 듣는 곳 | `*:9000` TLS (인증서 직접 읽음, 2027-02-12 만료) | **`127.0.0.1:9000` 평문**. TLS 는 nginx 가 끝낸다 |
| nginx | `proxy_pass https://gate.local…:9000` | `proxy_pass http://gate.local…:9000` |
| 정지 | 열린 웹소켓을 기다려 90초 | 3초 |
| 끊김 검사 | 300ms 마다 | 5초마다 (`--check_interval`) |
| 로그 | 콘솔이 pm2 로그·저널로 무한 복제 | 파일만(30일), 반복 재접속은 통로별 요약 |
| 의존성 | 147MB (socket.io·peer·개발용 포함) | 운영 13MB |

### 배포

```bash
bash deploy/build.sh /tmp              # → /tmp/peerjs-bundle-<커밋>.tgz (2.7MB)
scp /tmp/peerjs-bundle-*.tgz deploy/install.sh <현장>:/tmp/
ssh <현장> 'bash /tmp/install.sh /tmp/peerjs-bundle-<커밋>.tgz'   # --enable 은 꺼져 있던 현장도 켤 때
```

`install.sh` 는 원래 돌고 있던 현장만 켠다(꺼진 현장은 파일·unit 만 맞추고 꺼 둔다). 시작 확인에 실패하면
트리·unit·nginx·pm2 를 전부 되돌린다. 백업은 `/usr/local/bnids/backup/peerjs-<시각>/`.

### 배포 순서 — gitea `devBnids/nginx` 와 같이 움직인다

공통 nginx 설정(lab `/home/lab/git/gitea_nginx/default.conf`, sonamu 서비스 `nginx`)도 `https→http` 로 바꿔야 한다.

- **현장 설치 전에** gitea 를 바꿔 nginx 가 배포되면: http nginx ↔ 옛 TLS peerjs → 실시간 끊김
- **현장 설치 후에** gitea 를 안 바꾸면: 다음 nginx 배포가 https 로 되돌림 → 실시간 끊김

그래서 현장 설치를 시작하는 날 gitea 를 바꿔 push 하고, 그날 안에 전 현장 설치를 끝낸다(그 사이 nginx 배포 금지).
`install.sh` 는 현장 nginx 를 스스로 고치므로 gitea 변경이 현장에 먼저 닿을 필요는 없다.

```
sed -i -E 's#(proxy_pass[[:space:]]+)https://(gate\.local\.happyparking\.co\.kr):9000#\1http://\2:9000#g' default.conf
```

### 12 리허설 (2026-10-13)

| 시나리오 | 결과 |
|---|---|
| systemd 로 돌던 현장 | OK, nginx(https)→peerjs(http) 응답·실제 송출 장치 재접속, 저널 0줄 |
| 재설치(멱등) | OK, 4초 |
| 꺼져 있던 현장 / `--enable` | 꺼진 채 유지 / 켜짐 |
| 고장 난 묶음 | `FAIL step=start rolled-back` → 이전 판 복원·정상 응답 |
| 수락리버시티형(옛 TLS 판을 pm2 가 돌리고 systemd 는 포트 못 잡은 채 중복, nginx https) | OK 8초 — 프로세스 1개·pm2 부팅 해제·nginx http |

---

## 로그 (2026-10-13)

- 정본은 파일 로그 `/usr/local/bnids/logs/peerjs-server-YYYYMMDD.log` (30일 보관). 저널·pm2 로그에는 더 이상 접속 기록이 나가지 않는다(터미널에서 직접 띄우거나 `PEERJS_CONSOLE=1` 일 때만 콘솔 출력).
- 같은 통로의 접속·끊김이 반복되면(송출 장치가 끊겼다 붙었다, 또는 뷰어가 캠서버를 못 찾아 재시도) 통로·역할별로 10분에 3번까지만 그대로 남기고 나머지는 `Client <현장>-<통로>-<viewer>: repeated, omitted …` 요약 한 줄로 남긴다 (`bin/client-log.js`, 시험 `node test/client-log.test.js`).
- pm2 는 peerjs 가 자주 죽던 시절의 장치다. 지금은 systemd `peerjs.service`(Restart=on-failure) 로 충분하다.
