
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
