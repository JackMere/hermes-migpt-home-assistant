// start-migpt.mjs — 开机/一键启动后自动驱动 MiGPT 运行
// （mi-gpt 跑在 GUI 的子进程里，容器/Docker 重启后不会自动恢复，必须重新触发）
const BASE = "http://localhost:36592";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchWithRetry(url, opts = {}, tries = 10, gapMs = 3000) {
  let lastErr;
  for (let i = 1; i <= tries; i++) {
    try {
      const c = new AbortController();
      const id = setTimeout(() => c.abort(), 8000);
      const res = await fetch(url, { ...opts, signal: c.signal });
      clearTimeout(id);
      return res;
    } catch (e) {
      lastErr = e;
      if (i < tries) await sleep(gapMs);
    }
  }
  throw lastErr;
}

async function main() {
  // 1. 读取已保存的配置
  const cfgRes = await fetchWithRetry(`${BASE}/api/default`);
  const cfgJson = await cfgRes.json();
  const body = cfgJson.config;
  if (!body || !body.config || !body.config.speaker) {
    console.error("没有找到已保存的 MiGPT 配置（migptgui.json），请先在 GUI 里配置一次。");
    process.exit(1);
  }
  console.log("已读取配置：bot =", body.config.bot?.name, "| model =", body.env?.OPENAI_MODEL);

  // 2. 触发启动
  const startRes = await fetchWithRetry(`${BASE}/api/default/start`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const startJson = await startRes.json();
  console.log("启动结果:", JSON.stringify(startJson));

  // 3. 查询状态
  await sleep(3000);
  const st = await fetchWithRetry(`${BASE}/api/status`).then((r) => r.json());
  console.log("MiGPT 运行状态:", JSON.stringify(st));
  if (!st.running) process.exit(2);
}

main().catch((e) => {
  console.error("出错:", e.message);
  process.exit(1);
});
