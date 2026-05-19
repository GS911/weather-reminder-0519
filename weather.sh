#!/bin/bash
# weather-reminder-0519
# 早晚天气预报推送脚本（OpenWeatherMap）
# 依赖：curl, jq

set -uo pipefail

# ===== 配置 =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.env"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

OWM_KEY="${OWM_KEY:?环境变量 OWM_KEY 未设置}"
SCT_KEY="${SCT_KEY:?环境变量 SCT_KEY 未设置}"
CITY="${CITY:-}"
TIME="${1:-morning}"

# ===== 城市名映射（中文 → 英文）=====
CITY_EN() {
  case "$1" in
    "北京") echo "Beijing" ;;
    "上海") echo "Shanghai" ;;
    "广州") echo "Guangzhou" ;;
    "深圳") echo "Shenzhen" ;;
    "南京") echo "Nanjing" ;;
    "杭州") echo "Hangzhou" ;;
    "成都") echo "Chengdu" ;;
    "武汉") echo "Wuhan" ;;
    "重庆") echo "Chongqing" ;;
    "西安") echo "XiAn" ;;
    "苏州") echo "Suzhou" ;;
    "天津") echo "Tianjin" ;;
    "长沙") echo "Changsha" ;;
    "郑州") echo "Zhengzhou" ;;
    "东莞") echo "Dongguan" ;;
    "青岛") echo "Qingdao" ;;
    "沈阳") echo "Shenyang" ;;
    "宁波") echo "Ningbo" ;;
    "昆明") echo "Kunming" ;;
    "大连") echo "Dalian" ;;
    *) echo "$1" ;;  # 不是中文则原样使用
  esac
}

# ===== 确定城市 =====
if [ -z "$CITY" ]; then
  echo "▶ 未配置城市，使用 IP 定位..."
  IP_INFO=$(curl -s https://ipinfo.io/json)
  CITY_NAME=$(echo "$IP_INFO" | jq -r '.city // "Beijing"')
  echo "   IP 定位到: $CITY_NAME"
else
  CITY_NAME="$CITY"
  echo "▶ 使用配置城市: $CITY_NAME"
fi

CITY_ENGLISH=$(CITY_EN "$CITY_NAME")
echo "   ️查询: $CITY_ENGLISH"

# ===== 获取天气 =====
echo "▶ 获取天气预报..."
WEATHER_RESP=$(curl -s --compressed \
  "https://api.openweathermap.org/data/2.5/weather?q=$CITY_ENGLISH&appid=$OWM_KEY&units=metric&lang=zh_cn")

# 校验响应
HTTP_CODE=$(echo "$WEATHER_RESP" | jq -r '.cod // empty' 2>/dev/null || echo "")
if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ 天气 API 返回异常:"
  echo "$WEATHER_RESP" | jq '.message // .' 2>/dev/null || echo "$WEATHER_RESP"
  echo ""
  echo "   💡 常见原因：API Key 无效、城市名不支持、免费额度用完"
  echo "   💡 可去 https://home.openweathermap.org/api_keys 检查 Key"
  exit 1
fi

# 解析当前天气
CURRENT_TEMP=$(echo "$WEATHER_RESP" | jq -r '.main.temp | round')
TEMP_MAX=$(echo "$WEATHER_RESP" | jq -r '.main.temp_max | round')
TEMP_MIN=$(echo "$WEATHER_RESP" | jq -r '.main.temp_min | round')
DESCRIPTION=$(echo "$WEATHER_RESP" | jq -r '.weather[0].description')
MAIN_WEATHER=$(echo "$WEATHER_RESP" | jq -r '.weather[0].main')
WIND_SPEED=$(echo "$WEATHER_RESP" | jq -r '.wind.speed | round')

# 获取明日预报
FORECAST_RESP=$(curl -s --compressed \
  "https://api.openweathermap.org/data/2.5/forecast?q=$CITY_ENGLISH&appid=$OWM_KEY&units=metric&lang=zh_cn&cnt=16")
TOMORROW=$(echo "$FORECAST_RESP" | jq '[.list[] | select(.dt_txt | startswith("'$(date -u -d "+1 day" +%Y-%m-%d)'"))]')
TOMORROW_TMAX=$(echo "$TOMORROW" | jq -r '[.[].main.temp_max] | max | round // empty' 2>/dev/null || echo "?")
TOMORROW_TMIN=$(echo "$TOMORROW" | jq -r '[.[].main.temp_min] | min | round // empty' 2>/dev/null || echo "?")
TOMORROW_DESC=$(echo "$TOMORROW" | jq -r '.[0].weather[0].description // "未知"')
TOMORROW_MAIN=$(echo "$TOMORROW" | jq -r '.[0].weather[0].main // ""')
TOMORROW_WIND=$(echo "$TOMORROW" | jq -r '[.[].wind.speed] | max | round // 0' 2>/dev/null || echo "0")

# 如果没有明天数据（预报不足1天），退而用今天数据
if [ -z "$TOMORROW_TMAX" ] || [ "$TOMORROW_TMAX" = "?" ]; then
  TOMORROW_TMAX=$TEMP_MAX
  TOMORROW_TMIN=$TEMP_MIN
  TOMORROW_DESC=$DESCRIPTION
  TOMORROW_MAIN=$MAIN_WEATHER
  TOMORROW_WIND=$WIND_SPEED
fi

# ===== 天气图标 =====
WEATHER_ICON() {
  case "$1" in
    *Clear*) echo "☀️" ;;
    *Clouds*) echo "⛅" ;;
    *Rain*|*Drizzle*) echo "🌧️" ;;
    *Thunderstorm*) echo "⛈️" ;;
    *Snow*) echo "❄️" ;;
    *Mist*|*Fog*|*Haze*) echo "🌫️" ;;
    *) echo "🌤️" ;;
  esac
}

TEMP_LABEL() {
  if [ "$1" -ge 35 ]; then echo "🥵 酷热"
  elif [ "$1" -ge 30 ]; then echo "🌡️ 炎热"
  elif [ "$1" -ge 25 ]; then echo "😊 舒适"
  elif [ "$1" -ge 20 ]; then echo "🌿 凉爽"
  elif [ "$1" -ge 10 ]; then echo "🍂 微凉"
  elif [ "$1" -ge 5 ]; then echo "🧥 较冷"
  else echo "🥶 寒冷"
  fi
}

if [ "$TIME" = "morning" ]; then
  # === 早上提醒 ===
  TITLE="🌤 早上好！今日天气预报"
  ICON=$(WEATHER_ICON "$MAIN_WEATHER")

  SUGGEST=""
  if echo "$MAIN_WEATHER" | grep -qE "Rain|Drizzle|Thunderstorm"; then
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

  FEEL=$(TEMP_LABEL "$TEMP_MAX")

  BODY="📌 **$CITY_NAME** $ICON
━━━━━━━━━━━━━━━━━━━
🌡️ 当前温度：${CURRENT_TEMP}°C
📊 今日范围：${TEMP_MIN}°C ~ ${TEMP_MAX}°C（$FEEL）
🌤️ 天气：$DESCRIPTION
💨 风速：${WIND_SPEED}m/s
━━━━━━━━━━━━━━━━━━━
💡 **$SUGGEST**"

else
  # === 晚上提醒 ===
  TITLE="🌙 晚上好！明日天气预报"
  ICON=$(WEATHER_ICON "$TOMORROW_MAIN")

  # 与今天对比
  DIFF=$(( TOMORROW_TMAX - TEMP_MAX ))
  DIFF_TEXT=""
  if [ "$DIFF" -gt 0 ]; then
    DIFF_TEXT="（比今天升 ${DIFF}°C）"
  elif [ "$DIFF" -lt 0 ]; then
    DIFF_TEXT="（比今天降 $(( -DIFF ))°C）"
  else
    DIFF_TEXT="（与今天持平）"
  fi

  FEEL=$(TEMP_LABEL "$TOMORROW_TMAX")

  SUGGEST=""
  if echo "$TOMORROW_MAIN" | grep -qE "Rain|Drizzle|Thunderstorm"; then
    SUGGEST="${SUGGEST}🌂 明日有雨，记得带伞！"
  fi
  if [ "$DIFF" -le -5 ]; then
    SUGGEST="${SUGGEST}🧥 明日明显降温，注意添衣。"
  elif [ "$DIFF" -ge 5 ]; then
    SUGGEST="${SUGGEST}🌡️ 明日升温，可适当减少衣物。"
  fi
  if [ "$TOMORROW_TMAX" -ge 35 ]; then
    SUGGEST="${SUGGEST}🥵 高温预警，注意防暑！"
  fi
  if [ -z "$SUGGEST" ]; then
    SUGGEST="😊 明天天气稳定，安心休息吧！"
  fi

  BODY="📌 **$CITY_NAME** $ICON
━━━━━━━━━━━━━━━━━━━
🌡️ 明日温度：${TOMORROW_TMIN}°C ~ ${TOMORROW_TMAX}°C $FEEL $DIFF_TEXT
🌤️ 天气：$TOMORROW_DESC
💨 风速：${TOMORROW_WIND}m/s
━━━━━━━━━━━━━━━━━━━
💡 **$SUGGEST**"
fi

# ===== 推送微信 =====
echo "▶ 推送微信..."
SCT_URL="https://sctapi.ftqq.com/${SCT_KEY}.send"
curl -s -X POST "$SCT_URL" \
  -d "title=$TITLE" \
  -d "desp=$BODY" \
  -o /dev/null -w "   HTTP %{http_code}\n"

echo "✅ 推送完成！"
