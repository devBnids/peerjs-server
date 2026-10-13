
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

## 로그 (2026-10-13)

- 정본은 파일 로그 `/usr/local/bnids/logs/peerjs-server-YYYYMMDD.log` (30일 보관). 저널·pm2 로그에는 더 이상 접속 기록이 나가지 않는다(터미널에서 직접 띄우거나 `PEERJS_CONSOLE=1` 일 때만 콘솔 출력).
- 같은 통로의 접속·끊김이 반복되면(송출 장치가 끊겼다 붙었다, 또는 뷰어가 캠서버를 못 찾아 재시도) 통로·역할별로 10분에 3번까지만 그대로 남기고 나머지는 `Client <현장>-<통로>-<viewer>: repeated, omitted …` 요약 한 줄로 남긴다 (`bin/client-log.js`, 시험 `node test/client-log.test.js`).
- pm2 는 peerjs 가 자주 죽던 시절의 장치다. 지금은 systemd `peerjs.service`(Restart=on-failure) 로 충분하다.
