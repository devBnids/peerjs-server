#!/bin/bash
# 리포 → 현장 설치 묶음 peerjs-bundle-<커밋>.tgz
# 운영 의존성만 넣는다(네이티브 모듈 없음 — 맥에서 만들어도 리눅스에서 돈다).
# 사용: bash deploy/build.sh [출력 디렉터리]   → 마지막 줄에 묶음 경로
set -euo pipefail
cd "$(dirname "$0")/.."

npx tsc
REV=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- bin dist src package.json package-lock.json || REV="$REV-dirty"

OUT=${1:-$PWD}
ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT
chmod 755 "$ST"

cp -R bin dist package.json package-lock.json "$ST"/
(cd "$ST" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null)
echo "$REV" > "$ST/VERSION"

TGZ="$OUT/peerjs-bundle-$REV.tgz"
COPYFILE_DISABLE=1 tar czf "$TGZ" --no-xattrs --no-mac-metadata --uid 0 --gid 0 -C "$ST" .
echo "$TGZ"
