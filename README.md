# vibework — Mac 窗口远程预览（Phase 1）

把 Mac 上指定 App 的窗口（比如 Cursor / VS Code / Terminal）实时推流到同一局域网内的浏览器或 iPhone。

这是「AI 编程远程桌面」的第一阶段最小闭环：**ScreenCaptureKit 窗口捕获 → JPEG 编码 → WebSocket 推流 → 手机网页查看**。零第三方依赖，不需要 Xcode，`swift build` 即可。

## 为什么先做这个，而不是直接上 WebRTC

- WebRTC 在 Mac 服务端需要集成 GoogleWebRTC 框架 + 信令服务器，开发成本高。先用 WebSocket + JPEG 把「手机实时看到 Mac 画面」的核心体验验证掉，再升级不迟。
- iPhone 的 Safari 原生支持 WebSocket + Blob，网页就能当客户端，不需要先写 iOS App。
- 局域网下 1440p / 15fps JPEG 约 10-25 Mbps，体验足够；延迟通常在 200ms 左右。

## 快速开始

前置：macOS 13+，Xcode 命令行工具（`xcode-select --install`）。

```bash
cd mac-stream
swift build -c release
swift run -c release -- --list
```

> 如果在受限/沙箱环境里构建报 `sandbox-exec` 或缓存目录权限错误，用 `make build`（Makefile 已带上 `--disable-sandbox` 和临时模块缓存路径）。

首次运行会提示没有屏幕录制权限：

1. 打开 系统设置 → 隐私与安全性 → 屏幕录制
2. 勾选运行它的终端（用 `swift run` 跑就授权给 Terminal）
3. 重新运行

选定窗口并启动推流：

```bash
swift run -c release -- --window 2 --port 8080 --fps 15
```

输出会给出预览地址：

- 本机：http://localhost:8080
- iPhone（同一 Wi-Fi）：http://`<Mac 的局域网 IP>`:8080，查 IP 用 `ipconfig getifaddr en0`

第一次启动如果弹出 macOS 防火墙「允许传入连接」提示，点允许。

## 先不用屏幕也能验证（演示模式）

```bash
swift run -c release -- --demo --port 8090
```

浏览器打开 `http://localhost:8090` 会看到一张模拟测试画面在动。也可以用联调脚本直接验证 WebSocket 帧：

```bash
swift run -c release -- --demo --port 8090 &
node scripts/ws-test.js 8090
```

`--list` 因为屏幕录制权限没有授权会提示错误或超时，这是预期行为；授权后重试即可。

## 常见问题排查

| 现象 | 处理 |
|------|------|
| 提示 Address already in use | 端口被占用。换一个端口：`--port 8090`；或查占用者：`lsof -nP -iTCP:8080 -sTCP:LISTEN` |
| iPhone 打不开页面 | 先在 Mac 上确认 `http://localhost:8080` 能开；确认 IP 没写错；两个设备在同一 Wi-Fi；防火墙弹窗点了允许 |
| 页面白屏 / Safari「无法解析响应」 | 旧版本的 HTTP 响应头损坏 bug，已修复。重新 `make build` 并重启服务，浏览器强刷（Cmd+Shift+R） |
| 有页面但画面不动/黑屏 | 屏幕录制授权没生效——完全退出 Terminal 重开再启动；确认目标窗口没最小化 |
| 画面模糊或卡顿 | 降低参数：`--fps 10 --max-width 960 --quality 0.5` |
| 崩溃 CGS_REQUIRE_INIT | 旧版本的 bug，已修复（启动时初始化 AppKit）。重新 `make build` 即可 |
| 一直「等待画面帧」 | 先跑 `vibework --snapshot`：黑图=显示器熄屏/锁屏（用 `caffeinate -d`）；正常图=权限/管线没问题。录屏权限要授予**运行 vibework 的终端**，不是被录制的 App |

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--list` | - | 列出所有可捕获窗口及序号 |
| `--window <序号>` | 自动匹配 | 捕获指定窗口 |
| `--port <端口>` | 8080 | 监听端口 |
| `--fps <1-30>` | 15 | 推流帧率 |
| `--quality <0-1>` | 0.65 | JPEG 压缩质量 |
| `--max-width <像素>` | 1440 | 输出最大宽度，按比例缩放 |
| `--demo` | 关 | 不捕获屏幕，推一张模拟测试画面（用于联调） |
| `--no-capture` | 关 | 只启动 HTTP/WS 服务，不捕获 |
| `--screen` | 关 | 捕获整个主屏幕（窗口捕获不出帧时用于诊断/兜底） |
| `--snapshot <路径>` | 关 | 一次性整屏截图诊断，默认保存到 /tmp/vibework-snapshot.jpg |

## 目录结构

```
mac-stream/
  Package.swift
  Sources/vibework/
    CLI.swift           命令行入口、窗口选择
    CaptureEngine.swift ScreenCaptureKit 窗口捕获
    JPEGEncoder.swift   CVPixelBuffer → JPEG
    WebSocketServer.swift 极简 WebSocket 服务器（Network 框架）
    Viewer.swift        内嵌的手机端查看页
    Demo.swift          演示画面生成器
web/
  viewer.html           查看页独立副本（方便改样式）
scripts/
  ws-test.js            联调脚本：验证 WebSocket 握手与二进制帧
```

## 权限说明（重要）

- **屏幕录制**：必需，一次性授权。授权是常驻的，不会「定期提醒」；只有在系统升级、更换终端或重新安装 App 时才可能重新弹窗。
- **辅助功能（Accessibility）**：手机控制 Mac（触控板/按键/文字注入）必需。到 系统设置 → 隐私与安全性 → 辅助功能 勾选运行 vibework 的终端，然后重启 vibework。未授权时画面预览不受影响，但控制不生效。
- 屏幕录制无法捕获 DRM 保护内容（会黑屏），这是系统限制。

## 手机控制（Phase 2）

手机/浏览器打开预览页后，画面下方会出现控制栏：

- **拖动**：移动光标；**点击**：单击；**快速连点**：双击
- **滚动**：单指快速甩动 = 带惯性的滚动（像刷 App）；双指拖动 = 精细滚动；**双指点击** = 右键
- **快捷按键**：⇥（Tab）/ ⎋（Esc）/ ⌫（清空），另附 ▲▼◀▶ 方向滚动键（双击 ▲▼ = 滚到顶/底）
- **文字输入**：输入后点「发送」会自动回车触发对话；📝 可全屏查看/编辑长内容后确认发送
- **AI 润色**：点 ✨ 把输入内容交给 DeepSeek 纠正错别字/理顺表达，结果在弹窗中确认后发送（Key 保存到本机，重启不丢失）
- **连续语音指令**：网页语音识别需要 HTTPS，当前 http 下用 iPhone 键盘自带听写输入即可

桌面浏览器同样支持：鼠标移动/点击 + 滚轮滚动。

### 访问口令与 DeepSeek Key

```bash
./mac-stream/.build/release/vibework --window 0 --port 8090 --fps 15 \
  --token 你的口令 \
  --deepseek-key sk-你的DeepSeekKey
```

- `--token`：手机打开页面会先要求输入口令，口令错误拒绝连接（401）
- `--deepseek-key`：启动时配置；也可以在手机上点 ⚙ 输入。Key 会保存到 `~/.vibework/deepseek.key`（权限 600），重启不丢失
- 窗口自动激活：注入点击/按键/文字前，会自动把被控窗口（如 Cursor）激活到最前，避免误操作到其他 App

### 多应用切换（暂缓）

多应用切换（`--apps` + 网页端切换栏）原型已开发，但在真实环境验证中发现切换后滚动与文字聚焦不稳定，已回退到单窗口模式保证可用。当前请用 `--window` 指定单个应用；多应用功能等定位修复后再开放。

## 路线图

1. ✅ 窗口枚举、窗口捕获、JPEG 编码、WebSocket 推流、手机网页查看、断线自动重连
2. ✅ 手机控制最小闭环：虚拟触控板、快捷按键、文字输入（CGEvent 注入 + 窗口自动激活）
3. ✅ 访问口令（--token）、DeepSeek AI 文本润色（✨）、连续语音指令（🎙）
4. ⏳ H.264 硬件编码（VideoToolbox）+ fMP4/WebRTC，降延迟降带宽
5. ⏳ 音频回传：需要虚拟声卡（BlackHole），SCStream 只能捕获被录窗口所属 App 的音频，不是「系统音频」
6. ⏳ iOS 原生 App（SwiftUI + 播放与触控层）、多窗口切换（原型已做，稳定后恢复）

## 路线图

1. ✅ 当前：窗口枚举、窗口捕获、JPEG 编码、WebSocket 推流、手机网页查看、断线自动重连
2. ⏳ H.264 硬件编码（VideoToolbox）+ fMP4/WebRTC，降延迟降带宽
3. ⏳ 输入注入：虚拟触控板 / 键盘 / 快捷按钮（CGEvent + 辅助功能权限）
4. ⏳ 语音输入：iPhone 语音 → 文字 → 发送到 Mac（先做成粘贴 + Command+V）
5. ⏳ 音频回传：需要虚拟声卡（BlackHole），SCStream 只能捕获被录窗口所属 App 的音频，不是「系统音频」
6. ⏳ iOS 原生 App（SwiftUI + 播放与触控层）、多窗口切换

## 诚实的技术修正（相对最初方案）

- 输入注入还需要**辅助功能权限**，CGEvent 依赖它，不是只有录屏权限。
- ScreenCaptureKit 的音频捕获范围 = 被捕获窗口所属 App 的音频；iPhone 麦克风进 Mac 需要虚拟声卡。
- Moonlight 在 Mac 上没有官方服务端，要用 Sunshine 或 Steam Link；只想快速体验「手机看 Mac 并控制」，macOS 自带屏幕共享 + VNC 客户端最快。
