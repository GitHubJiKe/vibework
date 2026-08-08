# vibework 使用指南

> 局域网「AI 编程遥控器」：Mac 抓取目标应用（Cursor / Codex / VS Code / 终端等）窗口，
> 实时推流到手机浏览器，手机端像遥控器一样查看和控制 Mac 上的 AI 编程。
>
> 当前推荐使用**命令行方式**（稳定）；桌面 App（VibePilot）为实验性功能。

## 一、快速开始（命令行）

### 1. 构建

前置：macOS 13+，Xcode 命令行工具（`xcode-select --install`）。

```bash
cd ~/Codes/vibework
make build
```

> 沙箱/受限环境构建报错时，`make build` 已内置 `--disable-sandbox` 与临时模块缓存参数。

### 2. 查看可捕获的窗口

```bash
./mac-stream/.build/release/vibework --list
```

输出形如：

```
[0] ChatGPT（com.openai.codex）— ChatGPT（714x900pt）
[1] Cursor（com.todesktop.230313mzl4w4u92）— Cursor Agents（714x900pt）
[2] 终端（com.apple.Terminal）— （800x600pt）
```

### 3. 启动推流

```bash
./mac-stream/.build/release/vibework --window 1 --port 8090 --fps 15
```

启动后终端会显示访问地址和二维码：

```
本机预览：    http://localhost:8090
iPhone 预览： http://192.168.1.54:8090   （同一 Wi-Fi 下）
用手机相机扫码访问：
   ▄▄▄▄▄▄▄ ▄▄▄ ▄▄  ▄ ▄▄▄▄▄▄▄
   █ ▄▄▄ █ █▀ ▄▄█▄▄▄ █ ▄▄▄ █
   ...（二维码）
按 Ctrl+C 退出
```

**手机直接扫码**即可打开控制页面（手机与 Mac 需在同一 Wi-Fi）。

### 4. 推荐参数（含口令与 AI 润色）

```bash
./mac-stream/.build/release/vibework --window 1 --port 8090 --fps 15 \
  --token 你的口令 \
  --deepseek-key sk-你的DeepSeekKey
```

## 二、命令行参数

| 参数 | 说明 |
|------|------|
| `--list` | 列出可捕获窗口及序号 |
| `--window <序号>` | 捕获指定窗口（单应用） |
| `--apps <序号,序号,...>` | 同时加载多个窗口，网页端顶部可切换（如 `--apps 1,2`） |
| `--port <端口>` | 监听端口，默认 8080 |
| `--fps <1-30>` | 帧率，默认 15 |
| `--quality <0-1>` | JPEG 质量，默认 0.65 |
| `--max-width <宽>` | 输出最大宽度（像素），默认 1440 |
| `--token <口令>` | 访问口令：手机打开页面需输入口令 |
| `--deepseek-key <key>` | DeepSeek API Key：AI 润色（也保存到 `~/.vibework/deepseek.key`） |
| `--screen` | 捕获整个主屏幕（窗口捕获异常时的诊断/兜底） |
| `--demo` | 演示模式：不捕获屏幕，推模拟画面 |
| `--no-capture` | 只启动 HTTP/WS 服务，不捕获屏幕 |
| `--snapshot [路径]` | 一次性整屏截图诊断 |
| `--probe <序号>` | 事件注入诊断（坐标/鼠标/滚轮/点击是否到达目标窗口） |

完整帮助：`./mac-stream/.build/release/vibework --help`

## 三、手机端使用（浏览器打开）

手机与 Mac 连同一 Wi-Fi，用相机扫终端二维码（或手动输入 `http://<Mac 局域网 IP>:<端口>`）。

### 连接与口令

- 设置了 `--token` 时，首次打开页面需输入口令，通过后自动记住；
- 口令错误会被拒绝连接（401）。

### 画面与控制区

页面从上到下：**应用切换栏**（多应用时显示）→ **视频画面** → **快捷键行** → **输入行**。

### 鼠标控制（视频画面上）

- **单指拖动**：移动鼠标光标（手指在哪，鼠标就在窗口对应位置）
- **单击**：鼠标单击；**快速连点**：双击
- **双指点击**：鼠标右键

### 滚动

- **单指快速甩动**：带惯性的滚动（像刷手机 App）
- **双指拖动**：精细滚动
- **方向键 ▲▼◀▶**：点按滚一档，按住连续滚；**双击 ▲▼ = 滚到顶部 / 底部**
- 滚动固定作用于窗口中央的聊天/主内容区

### 快捷键行

| 键 | 作用 |
|----|------|
| ▲ ◀ ▶ ▼ | 方向滚动（▲▼ 双击 = 顶/底） |
| ⇥ Tab | 补全 / 缩进 |
| ⎋ Esc | 取消 / 退出 |
| ⌫ 清空 | 一键清空输入框 |

### 文字输入与发送

1. 在输入框输入内容（或语音转写）；
2. 点 **📝** 可全屏查看/编辑长内容，确认后发送；
3. 点 **✨** 交给 DeepSeek 润色（纠错/理顺表达），结果在弹窗确认后发送；
4. 点 **发送**：内容注入目标应用输入框并**自动回车**，直接发起对话（Codex 会自动聚焦输入框）。

### AI 润色（DeepSeek）

- 需要配置 Key：启动加 `--deepseek-key`，或在页面点 **⚙** 输入（保存到本机，重启不丢失）；
- 模型使用 `deepseek-v4-flash`；
- 校验 Key：`bash scripts/check-deepseek.sh sk-xxx`

### 多应用切换

用 `--apps 1,2` 启动后，网页顶部出现应用切换栏，点一下即可切换画面与控制目标（约 1 秒）。

## 四、权限说明（重要）

首次使用需要授予运行终端两个权限：

1. **屏幕录制**：系统设置 → 隐私与安全性 → 屏幕录制 → 勾选运行命令的终端；
2. **辅助功能**：系统设置 → 隐私与安全性 → 辅助功能 → 勾选运行命令的终端（用于鼠标/键盘/滚动注入）。

授权后**重新打开终端再运行**。画面预览只需要屏幕录制；控制功能（点击/输入/滚动）需要辅助功能。

## 五、常见问题

**Q：启动后一直「等待画面帧」？**

显示器熄屏或屏幕完全静止。先执行 `caffeinate -d` 保持屏幕常亮；静止画面有每秒兜底重发，耐心等待首帧。

**Q：滚动没反应？**

确认辅助功能权限已授予且终端已重启；滚动固定锚定在窗口中央聊天区，若目标窗口中心不是内容区，可先单指点击内容位置再滚。

**Q：发送的文字进不了输入框？**

辅助功能权限未授予，或目标应用未激活。Cursor/Codex 会自动激活并聚焦输入框；其他应用请先在手机上点击其输入框。

**Q：AI 润色报 Key 无效？**

用 `bash scripts/check-deepseek.sh sk-xxx` 验证 Key；确认模型名（`deepseek-v4-flash`）与官方文档一致。

**Q：端口被占用？**

换端口：`--port 8091`；或查占用：`lsof -nP -iTCP:8090 -sTCP:LISTEN`。

**Q：手机打不开页面？**

确认同一 Wi-Fi；Mac 防火墙可能拦截，允许本程序入站；查 IP：`ipconfig getifaddr en0`。

## 六、桌面 App（实验性）

`make app` 可生成 `build/VibePilot.app`（SwiftUI 主窗口 + 菜单栏）。当前以命令行为主，App 版仍在打磨（权限记录稳定性等问题），功能与命令行一致但建议暂以命令行为主。

## 七、诊断工具速查

```bash
# 一次性截图，判断捕获管线是否正常
./mac-stream/.build/release/vibework --snapshot

# 事件注入诊断（对比坐标、验证鼠标/滚轮/点击是否到达窗口）
./mac-stream/.build/release/vibework --probe 1
```

## 八、项目结构速览

```
mac-stream/
  Sources/VibeCore/      共享引擎（捕获/注入/推流/AI/二维码）
  Sources/vibework/      CLI 入口
  Sources/vibeapp/       桌面 App（实验性）
web/viewer.html          手机端页面副本
scripts/                 打包与工具脚本
```
