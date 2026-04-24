#!/bin/bash

# 日時をフォーマットする関数（macOS/Linux両対応）
# Unixタイムスタンプ（ミリ秒）とISO 8601の両方に対応
format_reset_time() {
  local dt="$1"
  if [ -z "$dt" ]; then return 1; fi

  # Unixタイムスタンプ（ミリ秒）の場合
  if echo "$dt" | grep -qE '^[0-9]+$'; then
    local epoch_sec=$((dt / 1000))
    # macOS (BSD date)
    if date -j -r "$epoch_sec" +"%m/%d %H:%M" 2>/dev/null; then return 0; fi
    # Linux (GNU date)
    if date -d "@$epoch_sec" +"%m/%d %H:%M" 2>/dev/null; then return 0; fi
  fi

  # ISO 8601形式の場合
  local normalized
  normalized=$(echo "$dt" | sed -E 's/\.[0-9]+//; s/Z$/+0000/; s/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
  # macOS (BSD date)
  if date -j -f "%Y-%m-%dT%H:%M:%S%z" "$normalized" +"%m/%d %H:%M" 2>/dev/null; then return 0; fi
  # Linux (GNU date)
  if date -d "$dt" +"%m/%d %H:%M" 2>/dev/null; then return 0; fi

  echo "$dt"
}

# 標準入力からJSON形式のデータを読み込む
input=$(cat)

# モデル名
MODEL=$(echo "$input" | jq -r '.model.display_name')

# 現在のディレクトリ名
CWD=$(echo "$input" | jq -r '.workspace.current_dir')
DIR=$(basename "$CWD")

# gitブランチ名
BRANCH=$(git -C "$CWD" --no-optional-locks branch --show-current 2>/dev/null)

# ディレクトリ表示（ブランチがあれば括弧付き）
if [ -n "$BRANCH" ]; then
  DIR_DISPLAY="${DIR}(${BRANCH})"
else
  DIR_DISPLAY="${DIR}"
fi

# コンテキスト使用率
CTX_USED=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$CTX_USED" ]; then
  CTX_DISPLAY="Context: $(printf '%.0f' "$CTX_USED")%"
else
  CTX_DISPLAY="Context: --"
fi

# リミット使用率(5時間/7日間)
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
USAGE_DISPLAY=""
if [ -n "$FIVE_H" ] && [ -n "$SEVEN_D" ]; then
  USAGE_DISPLAY="5H: $(printf '%.0f' "$FIVE_H")% / 7D: $(printf '%.0f' "$SEVEN_D")%"
elif [ -n "$FIVE_H" ]; then
  USAGE_DISPLAY="5H: $(printf '%.0f' "$FIVE_H")% / 7D: --"
elif [ -n "$SEVEN_D" ]; then
  USAGE_DISPLAY="5H: -- / 7D: $(printf '%.0f' "$SEVEN_D")%"
else
  USAGE_DISPLAY="5H: -- / 7D: --"
fi

# リミットのリセット時間(5時間/7日間)
# FIVE_H_RESET_AT=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
# SEVEN_D_RESET_AT=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
# RESET_DISPLAY=""
# if [ -n "$FIVE_H_RESET_AT" ] && [ -n "$SEVEN_D_RESET_AT" ]; then
#   RESET_DISPLAY="5H: $(format_reset_time "$FIVE_H_RESET_AT") / 7D: $(format_reset_time "$SEVEN_D_RESET_AT")"
# elif [ -n "$FIVE_H_RESET_AT" ]; then
#   RESET_DISPLAY="5H: $(format_reset_time "$FIVE_H_RESET_AT") / 7D: --"
# elif [ -n "$SEVEN_D_RESET_AT" ]; then
#   RESET_DISPLAY="5H: -- / 7D: $(format_reset_time "$SEVEN_D_RESET_AT")"
# else
#   RESET_DISPLAY="5H: -- / 7D: --"
# fi

# コスト算出
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# ステータスライン組み立て
STATUS="🤖${MODEL} | 📁${DIR_DISPLAY} | ${CTX_DISPLAY} | Usage ${USAGE_DISPLAY} | 💰Cost: \$$(printf '%.2f' "$COST")"

printf "%s\n" "$STATUS"
