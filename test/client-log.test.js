// node test/client-log.test.js
const assert = require("assert");
const { createClientLog, clientKey } = require("../bin/client-log");

let t = 0; const out = [];
const cl = createClientLog(m => out.push(m), { windowMs: 600000, limit: 3, now: () => t });

assert.strictEqual(clientKey("17336-220702-1-0f8c2a1e-1b2c-4d3e-8f90-a1b2c3d4e5f6"), "17336-220702-1-<viewer>");
assert.strictEqual(clientKey("17336-220702-1"), "17336-220702-1");

// 정상 송출 장치: 접속 1, 끊김 1 — 그대로 남는다
cl.event("connected", "17336-220702-2"); cl.event("disconnected", "17336-220702-2");
// 뷰어 폭주: uuid 가 매번 달라도 통로 단위로 묶인다
for (let i = 0; i < 100; i++) {
  const id = `17336-220702-1-${String(i).padStart(8, "0")}-1b2c-4d3e-8f90-a1b2c3d4e5f6`;
  cl.event("connected", id); cl.event("disconnected", id);
}
assert.strictEqual(out.length, 2 + 6);
cl.flush(); assert.strictEqual(out.length, 8);           // 창이 안 끝났으면 요약 없음
t = 600000; cl.flush();
assert.strictEqual(out.length, 9);
assert.match(out[8], /^Client 17336-220702-1-<viewer>: repeated, omitted connected 97, disconnected 97 in last 10m; last disconnected 17336-220702-1-00000099-1b2c-4d3e-8f90-a1b2c3d4e5f6 at \d\d:\d\d:\d\d$/);
assert.strictEqual(cl.size(), 0);                        // 창이 끝나면 비워진다
cl.event("connected", "17336-220702-1"); assert.strictEqual(out.length, 10); // 새 창은 다시 그대로
cl.flush(true); assert.strictEqual(out.length, 10);      // 넘친 게 없으면 요약 없음
console.log("ok", out.length, "lines");
