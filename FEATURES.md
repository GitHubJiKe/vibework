# vibework · 功能清单

> 局域网「AI 编程遥控器」：Mac 端抓取目标应用（Cursor / Codex 等）窗口实时推流到手机，
> 手机网页远程查看与控制。本文档汇总当前全部功能点与使用方式。

## 一、视频推流（Mac → 手机）

- **窗口捕获**：基于 ScreenCaptureKit 捕获单个应用窗口（`--window <序号>`，配合 `--list` 查看序号）
- **整屏捕获**：`--screen` 捕获整个主显示器（窗口捕获不出帧时的诊断/兜底方案）
- **JPEG 硬件编码推流**：VideoToolbox 优先，CoreImage 兜底；`--quality` 调节质量（默认 0.65）
- **WebSocket 低延迟传输**：始终发送最新帧，繁忙时丢弃中间帧
- **静止画面兜底**：屏幕无变化时每秒重发最后一帧 + 微调配置强制出新帧，手机端始终能看到当前画面
- **熄屏检测**：启动时检测显示器睡眠状态并提示
- **断线自动重连**：手机端连接断开后 1 秒自动重连
- **演示模式**：`--demo` 不捕获屏幕，推模拟画面（测试网页/控制链路用）
- **纯服务模式**：`--no-capture` 只启动 HTTP/WS 服务

## 二、手机控制（触控板 / 鼠标）

- **单指拖动** = 移动光标（绝对映射，手在屏幕哪里鼠标就在目标窗口哪里）
- **单击 / 快速连点** = 单击 / 双击
- **双指点击** = 右键
- **窗口自动激活**：注入点击/按键/文字前自动把目标应用激活到最前，避免误操作到其他 App

## 三、手机控制（滚动）

- **单指快速甩动** = 带惯性的滚动（像刷手机 App）
- **双指拖动** = 精细滚动（iOS 原生方向）
- **方向键 ▲▼◀▶**：点按滚一档（≈80px），按住连续滚；**双击 ▲▼ = 滚到顶部 / 底部**
- **滚动锚点**：固定锚定到目标窗口中央的聊天/主内容区，不受此前点过位置影响
- 兼容桌面浏览器：鼠标移动 / 点击 + 滚轮滚动

## 四、文字输入与发送

- **文字注入**：输入框内容以键盘事件逐字注入目标应用（支持中文）
- **发送自动回车**：点一次「发送」= 输入内容 + 自动回车触发对话，无需二次操作
- **Codex 输入框自动聚焦**：对 Codex 发送前自动点击底部输入框拿到焦点（Cursor 激活后焦点天然在输入框，无需点击）
- **全屏编辑 📝**：输入/语音转写内容较长时，一键弹到全屏查看、修改，确认后发送
- **一键清空 ⌫**：先全选再删除，一次清空输入框
- **快捷键 ⇥ / ⎋**：Tab（补全/缩进）、Esc（取消/退出）

## 五、AI 增强

- **DeepSeek 文本润色 ✨**：纠正错别字、理顺口语化表达，使用 `deepseek-v4-flash` 模型
- **优化结果弹窗**：润色结果全屏展示，可编辑后「确认并发送」（自动回车）
- **Loading 状态**：优化进行中按钮变为 ⏳ 并禁用，35 秒超时提示
- **API Key 持久化**：Key 保存到 `~/.vibework/deepseek.key`（权限 600），重启不丢失；启动参数 `--deepseek-key` 或页面 ⚙ 均可配置
- **Key 有效性校验脚本**：`bash scripts/check-deepseek.sh sk-xxx` 一键验证

## 六、安全与访问

- **访问口令**：`--token <口令>` 启用，手机打开页面需输入口令，错误拒绝连接（401）
- **口令记忆**：手机端记住已通过的口令（localStorage）
- **局域网隔离**：仅监听本机端口，同一 Wi-Fi 下手机访问 Mac 局域网 IP

## 七、诊断与调试

- **`--list`**：列出可捕获窗口及序号
- **`--snapshot [路径]`**：一次性整屏截图，判断权限/捕获管线是否正常
- **`--probe <序号>`**：事件注入诊断——对比 SCK/AX 坐标、验证鼠标移动、滚轮、点击是否到达目标窗口
- **启动 8 秒自检**：自动报告推流帧数，区分「捕获失败 / 画面静止 / 编码失败」
- **日志输出**：控制指令接收日志（收到控制指令：text/scroll 等）

## 八、语音能力（暂缓）

- 网页连续语音识别（说「回车发送」自动发送等）代码已保留，但入口按钮已移除
- 原因：网页麦克风需要 HTTPS 环境；当前 http 下建议使用 iPhone 键盘自带听写 + 全屏编辑

## 九、已知限制 / 待办

- **多应用切换（`--apps`）**：已在 `feature/multi-app` 分支实现并验证可用（按需切换 + 切流完成后回执），待合并回 `main`；合并前 `main` 为单窗口模式
- **H.264 硬件编码 + fMP4/WebRTC**：待做（当前 JPEG，延迟与带宽仍有优化空间）
- **音频回传**：需虚拟声卡（BlackHole），SCStream 只能捕获被录窗口所属 App 的音频
- **iOS 原生 App**（SwiftUI + 播放与触控层）：待做
- **HTTPS 自签证书**：待做（解锁连续语音、消除浏览器限制）

## 十、快速上手

**桌面 App（推荐）**：

```bash
make app            # 生成 build/VibePilot.app
open build/VibePilot.app
```

在 App 主窗口勾选应用 → 设置端口/口令/DeepSeek Key → 点「开始推流」；菜单栏图标常驻，可查看状态、切换应用、停止服务。

**命令行方式**：

```bash
# 查看可捕获窗口
./mac-stream/.build/release/vibework --list

# 启动（推荐）
./mac-stream/.build/release/vibework --window <序号> --port 8090 --fps 15 \
  --token 你的口令 --deepseek-key sk-你的DeepSeekKey

# 编译
make build
```

手机打开 `http://<Mac 局域网 IP>:8090`（同一 Wi-Fi），查 IP：`ipconfig getifaddr en0`。

## 十一、技术栈

- macOS：Swift + ScreenCaptureKit + CoreGraphics（CGEvent 注入）+ Network（NWListener WebSocket）+ VideoToolbox/CoreImage（JPEG）
- 桌面 App：SwiftUI + AppKit（主窗口、菜单栏、开机自启 SMAppService），打包脚本 `scripts/build-app.sh`
- 网页端：原生 HTML/JS（无框架），内嵌于 VibeCore `Viewer.swift`（开发副本 `web/viewer.html`）
- AI：DeepSeek API（`deepseek-v4-flash`）
