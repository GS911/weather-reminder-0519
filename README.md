# weather-reminder-0519

实时跟踪指定地区天气预报，每天早晚智能推送微信提醒。

- **早上 7:00** — 今日天气概况 + 穿衣/带伞建议
- **晚上 21:00** — 明日预报 + 温度对比 + 重点提醒

## 你需要准备的

1. **和风天气 API Key** — 免费注册 https://dev.qweather.com
2. **ServerChan SendKey** — 免费注册 https://sct.ftqq.com
3. **GitHub 账号** — 用来托管代码和运行定时任务

## 快速开始

### 1. 注册并拿到密钥

- 和风天气：注册 → 创建应用 → 免费订阅 → 复制 Key
- ServerChan：微信扫码登录 → 复制 SendKey

### 2. Fork / 推送代码到你的 GitHub

```bash
# 在 GitHub 新建一个仓库，然后：
git clone https://github.com/你的用户名/weather-reminder-0519.git
cd weather-reminder-0519
# 把本项目的文件复制进去
git add .
git commit -m "init"
git push
```

### 3. 在仓库设置中添加密钥

GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret：

| 名称 | 值 |
|------|-----|
| `HEFENG_KEY` | 你的和风天气 API Key |
| `SCT_KEY` | 你的 ServerChan SendKey |
| `CITY` | 城市名，如 `北京`（可选，不填则用 IP 定位） |

### 4. 启用 Actions

GitHub 仓库 → Actions → 确认 workflow 已启用。

默认每天早上 7:00 和晚上 21:00（北京时间）自动运行。

你也可以点 **"Run workflow"** 手动测试立即推送一条。

## 本地调试（Mac）

```bash
cd weather-reminder-0519
cp config.env.example config.env
# 编辑 config.env 填入你的密钥

# 测试早上推送
bash weather.sh morning

# 测试晚上推送
bash weather.sh evening
```

## 技术栈

- Shell 脚本（curl + jq）
- 和风天气 API v7
- ServerChan 推送
- GitHub Actions 定时任务

## 项目结构

```
weather-reminder-0519/
├── weather.sh                    # 主脚本
├── config.env.example            # 配置模板
├── .github/workflows/
│   └── weather-reminder.yml      # GitHub Actions 定时任务
└── README.md
```
