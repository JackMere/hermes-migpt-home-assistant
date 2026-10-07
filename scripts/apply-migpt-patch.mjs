// apply-migpt-patch.mjs — MiGPT 本地补丁（幂等，可重复执行）
//
// 补丁 1：修复流式解析崩溃
//   Hermes 触发工具调用时会发 `event: hermes.tool.progress` 事件帧（无 choices 字段），
//   MiGPT 直接读 chunk.choices[0] 会抛 TypeError。
//   修复：chunk.choices[0]  →  chunk.choices?.[0]
//
// 补丁 2：会话记忆（带自动轮转，避免历史无限累积变慢）
//   给 OpenAI 客户端加 defaultHeaders 里的 X-Hermes-Session-Id，
//   Hermes 服务端据此维护该会话的历史与记忆。
//   会话 ID 优先用环境变量 XIAOAI_SESSION_ID；否则用「按天轮转」的
//   `xiaoai-YYYYMMDD`（当天保留记忆，跨天自动开新会话，避免越聊越慢）。
import fs from "fs";

const TARGET = "/usr/local/lib/node_modules/migpt-server/node_modules/mi-gpt/dist/index.js";

if (!fs.existsSync(TARGET)) {
  console.log("找不到目标文件:", TARGET);
  process.exit(1);
}

let code = fs.readFileSync(TARGET, "utf8");
let changed = false;

// 备份（仅首次）
if (!fs.existsSync(TARGET + ".bak")) {
  fs.copyFileSync(TARGET, TARGET + ".bak");
  console.log("已备份原文件 -> index.js.bak");
}

// ---- 补丁 1：流式解析容错 ----
const FROM1 = "chunk.choices[0]";
const TO1 = "chunk.choices?.[0]";
const n1 = code.split(FROM1).length - 1;
if (n1 > 0) {
  code = code.split(FROM1).join(TO1);
  changed = true;
  console.log(`补丁1（流式容错）：替换 ${n1} 处`);
} else {
  console.log("补丁1：已应用或无需应用");
}

// ---- 补丁 2：会话记忆（按天轮转）----
const FROM2 = "new OpenAI({ httpAgent: kProxyAgent })";
// 按东八区日期生成 xiaoai-YYYYMMDD；可用 XIAOAI_SESSION_ID 覆盖
const SID_EXPR =
  'process.env.XIAOAI_SESSION_ID || ("xiaoai-" + new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, ""))';
const TO2 =
  'new OpenAI({ httpAgent: kProxyAgent, defaultHeaders: { "X-Hermes-Session-Id": ' + SID_EXPR + " } })";

if (code.includes(FROM2)) {
  code = code.split(FROM2).join(TO2);
  changed = true;
  console.log("补丁2（会话记忆，按天轮转）：已应用");
} else if (code.includes("X-Hermes-Session-Id")) {
  console.log("补丁2：已应用（检测到已存在 X-Hermes-Session-Id）");
} else {
  console.log("补丁2：未找到目标代码，跳过");
}

if (changed) {
  fs.writeFileSync(TARGET, code);
  console.log("✅ 补丁写入完成");
} else {
  console.log("✅ 无需改动");
}
