#!/usr/bin/env bash
# 验证 DeepSeek API Key 是否有效（只打印响应，不会显示 Key 本身）
# 用法: bash scripts/check-deepseek.sh sk-你的key
set -u

key="${1:-}"
if [[ -z "$key" ]]; then
  echo "用法: bash scripts/check-deepseek.sh sk-你的key"
  exit 1
fi

resp=$(curl -sS --max-time 20 https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $key" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"你好"}]}')

echo "$resp"
echo "---"
if echo "$resp" | grep -q '"choices"'; then
  echo "✅ Key 有效，可以正常调用 DeepSeek"
  exit 0
else
  echo "❌ Key 无效或不可用，请根据上面的错误信息处理"
  exit 1
fi
