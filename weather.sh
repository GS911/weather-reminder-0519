#!/bin/bash
# weather-reminder-0519
# 早晚天气预报推送脚本
# 依赖：curl, jq

set -uo pipefail

# ===== 配置 =====
# 从环境变量读取，或从 ../config.env 加载
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.env"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

HEFENG_KEY="${HEFENG_KEY:?环境变量 HEFENG_KEY 未设置}"
SCT_KEY="${SCT_KEY:?环境变量 SCT_KEY 未设置}"
CITY="${CITY:-}"
TIME="${1:-morning}"  # morning 或 evening

# ===== 获取城市 Location ID =====
if [ -z "$CITY" ]; then
  # 没有配置城市 → IP 定位（适合本地 Mac 运行）
  echo "▶ 未配置城市，使用 IP 定位..."
  IP_INFO=$(curl -s https://ipinfo.io/json)
  CITY_NAME=$(echo "$IP_INFO" | jq -r '.city // "北京"')
  echo "   IP 定位到: $CITY_NAME"
else
  CITY_NAME="$CITY"
  echo "▶ 使用配置城市: $CITY_NAME"
fi

echo "   ↳ 请求城市: $CITY_NAME"
LOCATION_RESP=$(curl -s --connect-timeout 10 "https://geoapi.qweather.com/v2/city/lookup?location=$CITY_NAME&key=$HEFENG_KEY" 2>&1 || true)
LOCATION_ID=$(echo "$LOCATION_RESP" | jq -r '.location[0].id // empty' 2>/dev/null || echo "")

if [ -z "$LOCATION_ID" ]; then
  echo "❌ 无法获取城市 ID，API 返回:"
  echo "$LOCATION_RESP" | head -c 500
  echo ""
  echo "   💡 可能原因：和风天气 Key 未激活、免费订阅未生效、城市名不支持"
  echo "   💡 可去 https://dev.qweather.com 检查你的订阅状态"
  exit 1
fi
echo "   ️城市 ID: $LOCATION_ID"

# ===== 获取天气预报 =====
echo "▶ 获取天气预报..."
WEATHER_RESP=$(curl -s "https://devapi.qweather.com/v7/weather/3d?location=$LOCATION_ID&key=$HEFENG_KEY")
if [ "$(echo "$WEATHER_RESP" | jq -r '.code')" != "200" ]; then
  echo "❌ 天气 API 返回异常: $(echo "$WEATHER_RESP" | jq '.')"
  exit 1
fi

TODAY=$(echo "$WEATHER_RESP" | jq '.daily[0]')
TOMORROW=$(echo "$WEATHER_RESP" | jq '.daily[1]')

# ===== 构建消息 =====
WEATHER_ICON() {
  case "$1" in
    *晴*) echo "☀️" ;;
    *云*) echo "⛅" ;;
    *阴*) echo "☁️" ;;
    *雨*) echo "🌧️" ;;
    *雪*) echo "❄️" ;;
    *雾*) echo "🌫️" ;;
    *风*) echo "💨" ;;
    *) echo "🌤️" ;;
  esac
}

TEMP_ICON() {
  if [ "$1" -ge 35 ]; then echo "🥵"
  elif [ "$1" -ge 30 ]; then echo "🌡️"
  elif [ "$1" -ge 20 ]; then echo "😊"
  elif [ "$1" -ge 10 ]; then echo "🍂"
  else echo "🥶"
  fi
}

if [ "$TIME" = "morning" ]; then
  # === 早上提醒 ===
  TITLE="🌤 早上好！今日天气预报"
  TEXT_DAY=$(echo "$TODAY" | jq -r '.textDay')
  TEMP_MAX=$(echo "$TODAY" | jq -r '.tempMax')
  TEMP_MIN=$(echo "$TODAY" | jq -r '.tempMin')
  WIND=$(echo "$TODAY" | jq -r '.windDir')
  WIND_SPEED=$(echo "$TODAY" | jq -r '.windSpeed')

  ICON=$(WEATHER_ICON "$TEXT_DAY")
  TEMP_ICN=$(TEMP_ICON "$TEMP_MAX")

  # 智能建议
  SUGGEST=""
  if echo "$TEXT_DAY" | grep -q "雨"; then
    SUGGEST="${SUGGEST}🌂 今天有雨，记得带伞！"
  fi
  if [ "$TEMP_MAX" -ge 35 ]; then
    SUGGEST="${SUGGEST}🥵 高温预警，注意防暑！"
  elif [ "$TEMP_MAX" -ge 30 ]; then
    SUGGEST="${SUGGEST}🧴 天气炎热，注意防晒补水。"
  fi
  if [ "$TEMP_MIN" -le 5 ]; then
    SUGGEST="${SUGGEST}🧥 早晚寒冷，记得加衣。"
  fi
  if [ -z "$SUGGEST" ]; then
    SUGGEST="☀️ 天气不错，祝你有愉快的一天！"
  fi

  BODY="📌 **$CITY_NAME** $ICON
━━━━━━━━━━━━━━━━━━━
🌡️ 温度：${TEMP_MIN}°C ~ ${TEMP_MAX}°C $TEMP_ICN
🌤️ 天气：$TEXT_DAY
💨 风力：${WIND} ${WIND_SPEED}级
━━━━━━━━━━━━━━━━━━━
💡 **$SUGGEST**"
else
  # === 晚上提醒 ===
  TITLE="🌙 晚上好！明日天气预报"
  TEXT_DAY=$(echo "$TOMORROW" | jq -r '.textDay')
  TEMP_MAX=$(echo "$TOMORROW" | jq -r '.tempMax')
  TEMP_MIN=$(echo "$TOMORROW" | jq -r '.tempMin')
  WIND=$(echo "$TOMORROW" | jq -r '.windDir')
  WIND_SPEED=$(echo "$TOMORROW" | jq -r '.windSpeed')

  # 与今天对比
  TODAY_TMAX=$(echo "$TODAY" | jq -r '.tempMax')
  DIFF=$(( TEMP_MAX - TODAY_TMAX ))
  DIFF_TEXT=""
  if [ "$DIFF" -gt 0 ]; then
    DIFF_TEXT="（比今天升 ${DIFF}°C）"
  elif [ "$DIFF" -lt 0 ]; then
    DIFF_TEXT="（比今天降 $(( -DIFF ))°C）"
  else
    DIFF_TEXT="（与今天持平）"
  fi

  ICON=$(WEATHER_ICON "$TEXT_DAY")
  TEMP_ICN=$(TEMP_ICON "$TEMP_MAX")

  SUGGEST=""
  if echo "$TEXT_DAY" | grep -q "雨"; then
    SUGGEST="${SUGGEST}🌂 明日有雨，记得带伞！"
  fi
  if [ "$DIFF" -le -5 ]; then
    SUGGEST="${SUGGEST}🧥 明日明显降温，注意添衣。"
  elif [ "$DIFF" -ge 5 ]; then
    SUGGEST="${SUGGEST}🌡️ 明日升温，可适当减少衣物。"
  fi
  if [ -z "$SUGGEST" ]; then
    SUGGEST="😊 明天天气稳定，安心休息吧！"
  fi

  BODY="📌 **$CITY_NAME** $ICON
━━━━━━━━━━━━━━━━━━━
🌡️ 温度：${TEMP_MIN}°C ~ ${TEMP_MAX}°C $TEMP_ICN $DIFF_TEXT
🌤️ 天气：$TEXT_DAY
💨 风力：${WIND} ${WIND_SPEED}级
━━━━━━━━━━━━━━━━━━━
💡 **$SUGGEST**"
fi

# ===== 推送 =====
echo "▶ 推送微信..."
SCT_URL="https://sctapi.ftqq.com/${SCT_KEY}.send"
curl -s -X POST "$SCT_URL" \
  -d "title=$TITLE" \
  -d "desp=$BODY" \
  -o /dev/null -w "   HTTP %{http_code}\n"

echo "✅ 推送完成！"
