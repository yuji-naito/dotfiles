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

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# 標準入力からJSON形式のデータを読み込む
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"') # モデル名
DIR=$(echo "$input" | jq -r '.workspace.current_dir') # 現在のパス
BRANCH=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null) # gitブランチ名
# used_percentageは小数で来ることがあるため、整数比較(-ge)できるよう丸める
CTX_USED=$(printf '%.0f' "$(echo "$input" | jq -r '.context_window.used_percentage // 0')")
FIVE_H=$(printf '%.0f' "$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0')") # リミット使用率(5時間)
SEVEN_D=$(printf '%.0f' "$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0')") # リミット使用率(7日間)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0') # コスト

if [ "$CTX_USED" -ge 90 ]; then CTX_COLOR="$RED"
elif [ "$CTX_USED" -ge 70 ]; then CTX_COLOR="$YELLOW"
else CTX_COLOR="$GREEN"; fi

if [ "$FIVE_H" -ge 90 ]; then FIVE_COLOR="$RED"
elif [ "$FIVE_H" -ge 70 ]; then FIVE_COLOR="$YELLOW"
else FIVE_COLOR="$GREEN"; fi

if [ "$SEVEN_D" -ge 90 ]; then SEVEN_COLOR="$RED"
elif [ "$SEVEN_D" -ge 70 ]; then SEVEN_COLOR="$YELLOW"
else SEVEN_COLOR="$GREEN"; fi

# ステータスライン組み立て
STATUS="${CYAN}[${MODEL}]${RESET} | 📁 ${DIR##*/} | 🌿 ${BRANCH} | Context: ${CTX_COLOR}${CTX_USED}%${RESET} | Usage: 5H ${FIVE_COLOR}${FIVE_H}%${RESET} / 7D ${SEVEN_COLOR}${SEVEN_D}%${RESET} | 💰 ${YELLOW}\$$(printf '%.2f' "$COST")${RESET}"

printf "%b\n" "$STATUS"
