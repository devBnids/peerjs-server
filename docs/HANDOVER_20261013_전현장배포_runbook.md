# peerjs 통일판 + nginx https→http 전 현장 배포 (2026-10-13 23:00)

사용자 승인: 2026-10-13 23시 실행(sonamu nginx 포함, gitea 와 다른 4곳도 gitea 판으로).

## 준비물
- 묶음: `bash deploy/build.sh /tmp` → `peerjs-bundle-7c13f85.tgz` (12 리허설 OK)
- 대상: 클라우드 `/cloud/api/site`(506) ∪ lab sonamu 목록(475) = 507곳 (`code<TAB>host<TAB>name`, 12 는 host=`12`)
- 사전 `--check`(16:41): 통과 464 · 미도달 42 · 실패 1(bn200408 — node·peerjs 없음)
- 외부 기준값: 실행 중 339곳 `https://<host>:9443/webrtc/` 모두 PeerJS 응답

## 순서
1. 카나리: bn210608(v12+pm2) bn210104(v12+systemd) bn211103(pm2+systemd 중복) bn201107(nvm) bn211005(꺼진 현장) bn210804(v16+pm2)
   `bash deploy/fleet.sh install <묶음> canary.tsv run_canary 6`
2. 나머지: `bash deploy/fleet.sh install <묶음> rest.tsv run_all 20` → `results.tsv` 의 ok/fail/unreachable
3. gitea nginx(lab `/home/lab/git/gitea_nginx`, 브랜치 main):
   `sed -i -E 's#(proxy_pass[[:space:]]+)https://(gate\.local\.happyparking\.co\.kr):9000#\1http://\2:9000#g' default.conf`
   → md5 `d80794a2…` 확인 → commit·push
4. sonamu nginx 배포 — **2 에서 OK 인 현장만**(lab 목록에 있는 코드):
   `$PY $S deploy --service nginx --sites-file ok_codes.txt --yes`
   gitea 와 달랐던 4곳(190902·230102·260801·200604)은 gitea 판 `nginx -t` 사전 검사 통과(16:5x) → 포함
5. 점검: 외부 :9443/webrtc/ 전후 비교, peerjs active·127.0.0.1:9000·pm2 정리, 현장 default.conf md5 = d80794a2

## 지켜야 할 것
- 설치 안 된 현장(미도달 등)에는 nginx 를 보내지 않는다 — http nginx ↔ 옛 TLS peerjs 로 실시간이 끊긴다.
  이후 그 현장에 nginx 를 배포하려면 peerjs 설치(`install.sh`)가 먼저다.
- 되돌리기: 현장 `/usr/local/bnids/backup/peerjs-<시각>/`(tree.tgz·peerjs.service·nginx 사본), nginx 는 sonamu 백업 `default.conf.YYYYMMDD`.

## 실행 결과 (2026-10-13 21:59~22:20, 사용자 지시로 23시에서 앞당김)

| 단계 | 결과 |
|---|---|
| peerjs 설치 | OK 463(실행 339·꺼짐 유지 124) · 실패 1(bn200408 node 없음) · 미도달 43 |
| gitea nginx | 8b2fb4f push (md5 d80794a2) |
| sonamu nginx | 459곳 성공 459 / 실패 0 (리포트 lab ~/.sonamu-deploy/reports/20261013-220658_nginx_459sites.txt) |
| bn260801(lab 목록 밖) | gitea 판 직접 적용, 백업 default.conf.20261013 |
| 점검 | 462곳 default.conf=d80794a2·nginx active, peerjs active 338(+12)·127.0.0.1:9000, 동시 접속 1,962(전 1,994), 외부 :9443/webrtc 338/339 — 실패 1은 설치 전부터 오프라인인 bn230607 |

### 미도달 43곳 — 옛 상태(옛 TLS peerjs + https nginx). **nginx 배포 전에 install.sh 먼저**

```
00000-000000	localserver.hparking.co.kr	BNIDS-Master (IP:11)
01775-201102	bn201102.hparking.co.kr	Y20N100.[V3](V1) 서울 노원 하계 학여울청
02007-210109	bn210109.hparking.co.kr	중랑 묵동아이파크
04419-201205	bn201205.hparking.co.kr	한남리첸시아
04709-261001	bn261001.hparking.co.kr	성동삼성쉐르빌
04718-211001	bn211001.hparking.co.kr	성동 금호삼성레미안
04734-221204	bn221204.hparking.co.kr	성동구 옥수삼성아파트
05267-210105	bn210105.hparking.co.kr	AS-셋팅서버-Ultra5
07258-191207	bn191207.hparking.co.kr	Y19N025.[V2] 서울 영등포 당산동부센트레빌_2
07270-200302	bn200302.hparking.co.kr	비엔인더스트리
07270-210105	bn210105.hparking.co.kr	rkd동 명일삼익그린2차_AS
07270-210111	bn210111.hparking.co.kr	현장팀용 통합서버
07270-210700	bn210700.hparking.co.kr	KC인증용통합서버
08734-191210	bn191210.hparking.co.kr	Y19N028.[V2.x] 서울 관악 관악푸르지오_**
08777-200712	lab.hparking.co.kr	BN연구소172_12_ext
08777-210711	localserver21.hparking.co.kr	BNIDS-BNI연구소21 - 개발서버
10068-201207	bn201207.hparking.co.kr	김포 은여울 경남아너스빌
10234-221005	bn221005.hparking.co.kr	일산 아이파크5단지
10448-210705	bn210705.hparking.co.kr	흰돌마을 3단지
10551-210806	bn210806.hparking.co.kr	Y21N175.[V2.x](V1) 경기 고양 원흥도래울
10551-211203	bn211203.hparking.co.kr	Y21N208.[V3.5] 경기 고양 도래울파크뷰6단지
11914-210302	bn210302.hparking.co.kr	일신건영1차 아파트
11914-250305	bn250305.hparking.co.kr	아름마을일신건영1차 아파트
11919-220903	bn220903.hparking.co.kr	구리인창아름마을원일(종료)
12069-220102	bn220102.hparking.co.kr	진접부영사랑으로
12774-200907	bn200907.hparking.co.kr	Y20N090.[V2](V1) 경기 광주 오포 우림 퓨
13165-200906	bn200906.hparking.co.kr	성남 래미안 금광아파트
13436-210502	bn210502.hparking.co.kr	Y21N150.[V2](V1) 경기 성남 센트럴타운3단
13973-260901	bn260901.hparking.co.kr	석수아이파크
14068-211204	bn211204.hparking.co.kr	안양 초원세경
14293-210404	bn210404.hparking.co.kr	Y21N148.[V2](V1) 경기 광명 현진에버빌_2
15381-191008	bn191008.hparking.co.kr	원곡 벽산블루밍
15539-210903	bn210903.hparking.co.kr	안산 본오동태영
16513-210103	bn210103.hparking.co.kr	광교레이크파크한양수자인
16836-230802	bn230802.hparking.co.kr	용인신정마을주공1단지
16963-201005	bn201005.hparking.co.kr	용인 기흥 가현마을 신안아파트
17091-230607	bn230607.hparking.co.kr	Y23N308.[V3.5Gx] 경기 용인 삼현마을진우_
17931-230203	bn230203.hparking.co.kr	Y23N286.[V3.5x](V1) 경기 평택 이화마을
18109-200506	bn200506.hparking.co.kr	세교데시앙포레
18151-200402	bn200402.hparking.co.kr	오산자이 아파트
21973-200901	bn200901.hparking.co.kr	인천 연수 한양2차
21997-191004	bn191004.hparking.co.kr	송도더샵 퍼스트월드
22631-260604	bn260604.hparking.co.kr	Y26N488.[V3.5Cx] 삼보해피하임2단지_29.
```


## 사고 — 2026-10-17 nginx 전 현장 배포가 미설치 현장의 중계를 끊음 (복구 완료 23:3x)

석수 VPN 대역 geo 면제(gitea nginx `0fa3b92`)를 sonamu `nginx` 로 전 현장(470곳)에 배포하면서 위 "설치 안 된 현장에는 nginx 를 보내지 않는다" 를 확인하지 않았다. 8b2fb4f 의 `proxy_pass http` 가 같이 실려 **옛 TLS peerjs 가 남은 현장은 http nginx ↔ TLS peerjs 로 /webrtc 가 502** 가 됐다.

| 43곳 중 | 결과 |
|---|---|
| 오늘 nginx 가 실제 들어간 곳 | **4곳**뿐(나머지 38곳은 lab 목록 밖이라 배포 안 감, 석수 260901 은 연결 안됨) |
| 17091-230607 삼현마을진우 | 23:20 통일판 peerjs 기동됨(다른 lab 세션이 복구한 것으로 보임) → 200 |
| 08734-191210 관악푸르지오 | peerjs 가 원래 꺼진 현장(배포 전에도 502) → 통일판 c679201 설치, 꺼진 채 유지(회귀 아님) |
| 08777-210711 사내 21(CentOS 7) | 끊김 확인 → **nginx :9000 프록시를 https 로 되돌려 복구**(백업 `default.conf.bak-20261017-peerjs-https`). 통일판 설치는 nvm node v18 이 `GLIBC_2.27` 을 요구해 bundle-check 실패·자동 되돌림 — 시스템 node 로 install.sh 보강 필요 |
| 04709-261001 성동삼성쉐르빌 | 맥·lab 모두 SSH 키 없음 → sonamu_site `/exec`(사무실 IP 만, lab 에서 호출)로 진단(옛 TLS peerjs active, node 없음, `encrypted/git/peerjs-server`) 후 같은 경로로 **https 되돌림 → 외부 :9443/webrtc 200** |

- 되돌린 2곳(21·261001)은 다시 "옛 TLS peerjs + https nginx" 다. **다음 nginx 배포가 또 http 로 덮는다** — 그 전에 통일판을 깔거나(21: node 경로, 261001: SSH 키 먼저), 배포 대상에서 뺀다.
- `/exec` 로 보내는 JSON 에 역슬래시(sed `\.`·`\1`)를 넣으면 Flask 가 400 으로 거부해 아무것도 안 돈다 — 점 그대로 쓰는 패턴으로, 보내기 전 `python3 -c json.load` 로 검사한다(1차 시도에서 겪음).
- 절차 보강: **sonamu `nginx` 전 현장 배포 전에 이 표의 미설치 현장(§미도달 43곳) 가운데 lab 목록에 있는 코드를 `--sites` 로 빼거나 install.sh 를 먼저 돌린다.** 스크립트는 sonamu_site `doc/tools_20261017/` 옆이 아니라 맥 `$CLAUDE_JOB_DIR/tmp/peerjs_fix_20261017.sh`·`peerjs_fix2_261001.sh`(세션 임시) 였다 — 내용은 위 표대로 `sudo cp 백업 → sed https → nginx -t → reload`.
