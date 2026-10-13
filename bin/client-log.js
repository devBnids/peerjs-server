// tslint:disable
// 같은 통로의 접속·끊김이 반복될 때 로그를 묶는다.
// 송출 장치(순수 ID siteCode-gateId)가 끊겼다 붙었다 하거나, 뷰어(siteCode-gateId-<uuid>)가
// 캠서버를 못 찾아 재시도하면 한 줄씩 수만 줄이 쌓였다. 통로·역할별로 창(window) 안에서
// limit 번까지만 그대로 남기고, 넘친 횟수는 창이 끝날 때 요약 한 줄로 남긴다.

const UUID_SUFFIX = /-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function clientKey(id) {
  return UUID_SUFFIX.test(id) ? id.replace(UUID_SUFFIX, "-<viewer>") : id;
}

function createClientLog(log, { windowMs = 10 * 60 * 1000, limit = 3, now = Date.now } = {}) {
  const windows = new Map(); // key -> { since, counts: {kind: n}, dropped: {kind: n} }

  function event(kind, id) {
    const key = clientKey(id);
    let w = windows.get(key);
    if (!w) {
      w = { since: now(), counts: {}, dropped: {} };
      windows.set(key, w);
    }
    w.counts[kind] = (w.counts[kind] || 0) + 1;
    if (w.counts[kind] <= limit) {
      log(`Client ${kind}: ${id}`);
    } else {
      w.dropped[kind] = (w.dropped[kind] || 0) + 1;
    }
  }

  function flush(force = false) {
    const t = now();
    for (const [key, w] of windows) {
      if (!force && t - w.since < windowMs) continue;
      const dropped = Object.entries(w.dropped).map(([k, n]) => `${k} ${n}`);
      if (dropped.length) {
        const mins = Math.max(1, Math.round((t - w.since) / 60000));
        log(`Client ${key}: repeated, omitted ${dropped.join(", ")} in last ${mins}m`);
      }
      windows.delete(key);
    }
  }

  return { event, flush, size: () => windows.size };
}

module.exports = { createClientLog, clientKey };
