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
