#!/usr/bin/env bash
# 把 README + docs/*.md 合并成单文件全本 tutorial-full.md
#
# 用途：方便把整份教程一次性喂给 AI，或离线/打印阅读。
#
# ⚠️ 本文件由本脚本自动生成，请勿手工编辑 tutorial-full.md；
#    要改内容请改 README.md 或 docs/*.md，然后重新执行本脚本。
#
# 用法：bash scripts/build-full.sh
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="tutorial-full.md"

{
    echo "# 小爱同学 × Hermes Agent × Home Assistant —— 完整教程（单文件版）"
    echo
    echo "> 本文件由 \`scripts/build-full.sh\` **自动生成，请勿手工编辑**。"
    echo "> 要改内容请改 \`README.md\` 或 \`docs/*.md\`，再重新执行该脚本。"
    echo ">"
    echo "> 分篇版本（链接可互相跳转）见仓库 [README.md](README.md) 与 [docs/](docs/) 目录。"
    echo "> 本单文件版里的 \`相对链接\` 不会跳转，请按标题查找对应章节。"
    echo
    echo "## 目录"
    echo
    echo "1. 项目总览与当前状态（README）"
    for f in $(ls docs/*.md | sort); do
        title=$(head -n 1 "$f" | sed 's/^# *//')
        echo "1. $title（\`$f\`）"
    done
    echo "1. 脚本说明（\`scripts/README.md\`）"
    echo
    echo "---"
    echo
    echo "# 项目总览与当前状态"
    echo
    cat README.md
    echo
    for f in $(ls docs/*.md | sort); do
        echo
        echo "---"
        echo
        cat "$f"
        echo
    done
    # 附录：脚本说明（不在 docs/ 下，单独追加）
    echo
    echo "---"
    echo
    cat scripts/README.md
    echo
} > "$OUT"

lines=$(wc -l < "$OUT")
bytes=$(wc -c < "$OUT")
echo "✅ 已生成 $OUT（$lines 行 / $bytes 字节）"
