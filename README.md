# Curtain

macOS 上的「幕帘」：**对物理世界生效的可见性开关，对采集通道完全透明**。

屏幕在物理上是黑的、键盘鼠标被锁住，但持有权限的 AI agent 仍然可以截取完整桌面、录制屏幕、合成点击——画面里没有幕帘，也不会有锁屏界面。

> 它不是锁屏。系统锁屏会把整个会话切到 loginwindow，任何第三方都拿不到画面（实测 `screencapture -l` 直接报 `could not create image from window`）。幕帘是解锁状态下的遮挡层，所以 agent 才能继续工作。

## 三条需求与实现

| 需求 | 实现 |
|---|---|
| 防猫误触键盘 | `CGEventTap` 挂在 `kCGHIDEventTap`，把来源 PID 为 0 的**物理事件**全部吞掉；白名单进程的合成事件放行；系统超时禁用 tap 时自动重挂；指针冻结、光标隐藏 |
| AI 截屏/录屏不被遮挡 | 幕帘窗口 `sharingType = .none`（截图/录屏里直接消失），叠加 `SCContentFilter(display:excludingApplications:...)` 第二道保险；**按屏抓取整张桌面**，不是单窗口 |
| 隐私（挡住人的视线） | 黑幕放在 `CGShieldingWindowLevel()`，盖住菜单栏、Dock、通知；HDMI/采集卡取的是同一帧缓冲，对外也只会是黑的 |

## 已实测（真机）

- 幕帘开启时截图：平均亮度 **173.8**，与关闭时 170.0 基本一致 → 拿到的是真实桌面，不是黑屏
- 幕帘开启时录屏：H.264 / 1680×1050 / 60 帧 / 3.18 s，抽帧平均亮度 **173.5** → 视频里也没有幕帘
- `sharingType = .none` 对照组：同一红色测试窗，`.readOnly` 时截图里有 135,034 个红色采样点，`.none` 时 18 个
- 事件分流：物理鼠标事件 `sourcePID=0`；合成事件的来源 PID 与 `kCGEventSourceUserData` 均按要求保留
- Touch ID：`biometryType=1`，可用

## 组成

```
curtaind            菜单栏常驻进程（唯一持权限的进程）
  Shield            每块屏幕一个黑窗，shielding 层级，sharingType .none
  InputGuard        HID 事件拦截 + 白名单 + 长按 Esc 手势
  CaptureBroker     截图 SCScreenshotManager / 录屏 SCStream
  AuthGate          Touch ID（唯一出口）
  Sentinel          防显示器休眠 / 系统睡眠
  ControlServer     unix socket 控制面 + JSONL 审计
curtainctl          瘦客户端，不需要任何权限
```

设计要点：**权限只授予 curtaind 一处**，agent 通过 `curtainctl` 走 socket，自己不持有屏幕录制权限。谁能截、截给谁，集中在 broker 里。

## 构建

只依赖 Command Line Tools（不需要 Xcode）：

```bash
./Scripts/make_app.sh          # 产物：build/Curtain.app
open build/Curtain.app
```

首次启动后到「系统设置 → 隐私与安全性」授予：

1. **录屏与系统录音**（截图/录屏）
2. **设备控制和数据访问**（事件拦截；macOS 26 起取代了原来的「辅助功能」）

缺权限时 Curtain 会自己弹出引导面板：每项一行、带状态灯和「打开设置」按钮，点一下直达对应系统面板，授权后状态灯会自动变绿，不用手动重开面板。

> macOS 26/27 把这两类权限并进了「设备控制和数据访问」面板，Curtain.app 会被自动加进列表，勾选即可。

> 默认 **ad-hoc 签名**，不依赖证书。代价很具体：ad-hoc 的代码身份就是 cdhash，我每次改代码重新编译后，你需要在系统设置里把 Curtain.app **取消再勾一次**（两个面板各一次）。app 检测到权限失效会自己弹引导面板。
>
> 不想反复授权时，可以给脚本指定一个固定签名身份（可选，不是必需）：
> `SIGN_ID="证书 CN" INSTALL=1 ./Scripts/make_app.sh`
>
> 安装到 `/Applications`：`INSTALL=1 ./Scripts/make_app.sh`（推荐，路径固定）。

## 使用

```bash
curtainctl on                 # 升起幕帘（屏幕变黑，输入被吞）
curtainctl status             # JSON 状态
curtainctl doctor             # 自检：权限 / 屏 / tap / Touch ID / 审计链 / 自启
curtainctl capture --out ~/Desktop/shot.png
curtainctl capture --all --out ~/Desktop/shots/s.png    # 每屏一张
curtainctl capture --region 100,100,400,300 --cursor    # 区域截图（点），带光标
curtainctl record start --out ~/Desktop/rec.mp4 --fps 30 --bitrate 8000000
curtainctl record stop
curtainctl audit 20           # 最近 20 条
curtainctl audit --verify     # 校验哈希链
curtainctl install-agent      # 开机自启（LaunchAgent，KeepAlive 兼作崩溃看门狗）
curtainctl uninstall-agent
curtainctl panic              # 应急强制撤幕，不验指纹
```

解除：**长按 Esc 两秒**（或 `curtainctl off`）→ Touch ID。除指纹外没有别的出口，也没有倒计时；猫踩出认证框也过不了指纹。

### 卡住了怎么办

按优先级：

1. `curtainctl panic` —— 走本地 socket 强制撤幕，不验指纹。猫不会敲命令，这是安全的自救口。
2. `pkill -TERM curtaind` —— 进程一死，黑窗随之销毁，输入立刻恢复。
3. 生物识别硬件不可用时，`curtainctl off` 会直接撤幕并记 `biometrics_unavailable` 审计，不会把人锁在黑屏里。

> 退出入口必须做在事件 tap 内部，不能做成菜单项：幕帘期间物理鼠标被吞掉，菜单根本点不到。

## 配置文件

`~/Library/Application Support/Curtain/config.json`

```json
{
  "allowlist": [
    "/Applications/Cua Driver.app",
    "com.nousresearch.cua-driver",
    "com.apple.Terminal",
    "/usr/bin/osascript"
  ],
  "holdToAuthSeconds": 2,
  "safetyTimeoutSeconds": 0
}
```

- `allowlist`：`/` 开头按可执行文件路径前缀匹配，否则按 bundle id 精确匹配。只有名单里的进程能在幕帘期间注入输入。
- `safetyTimeoutSeconds`：开发兜底，秒；`0` 表示关闭（默认）。不参与产品行为。

审计：`~/Library/Application Support/Curtain/audit.log`，每次入幕/撤幕/截图/录屏一行 JSON，截图带 sha256。

## 边界

- 挡不住电源键、合盖、长按强关——物理动作不在事件流里。
- 挡不住 USB 设备接入这类系统级动作。
- 幕帘期间会话保持解锁：这是前提，不是副作用。系统一旦锁屏，采集立刻失效。
- 幕帘只解决「屏幕内容在物理上不可见」，不解决「有屏幕录制权限的进程能不能拿到画面」——那是授权与审计问题。

## 可靠性设计

- **单实例**：`flock` 守门，第二个实例若发现已有健康实例就静默退出（launchd 的 RunAtLoad 也走这条路，不会弹窗打扰）。
- **开机自启**：LaunchAgent + `KeepAlive`，进程被杀会被 launchd 拉起；`doctor` 里能看到加载状态。
- **录制抗崩溃**：`movieFragmentInterval = 2s`，即使进程被强杀，mp4 仍可播放。
- **审计防篡改**：每条记录带 `prev` 与 `hash`，`curtainctl audit --verify` 能定位到具体哪一行被改过；旧格式记录自动跳过并单独计数。
- **分辨率**：截图/录屏按 `backingScaleFactor` 还原真实像素（Retina 上是 2x，不再只有一半）。

## Roadmap

P0（已完成）：单实例、自启、doctor、区域/多屏/光标、fps/码率、录制分片、审计哈希链。

P1（候选，按价值排序）：

1. **在场感应解锁**：iPhone/Watch 靠近自动撤幕，离开自动落幕（BLE RSSI）。
2. **对外 API**：本地 HTTP + MCP server，让 Claude Code / Codex 等其它 agent 通过 token 走同一个采集通道（权限与审计仍集中在 curator）。
3. **设置界面**：allowlist 编辑器、长按阈值、录制参数，替代手改 JSON。
4. **音频**：录屏带麦克风/系统声音。
5. **分发**：签名 DMG + Homebrew cask（需要 Developer ID），或 GitHub Actions 出通用构建。
6. **测试**：状态机单测 + 录制的端到端回归。
