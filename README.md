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

1. **屏幕录制**（截图/录屏）
2. **辅助功能**（事件拦截）

> ad-hoc 签名每次重编译都会变，TCC 授权会反复失效。开发时建议先在「钥匙串访问 → 证书助理」建一张代码签名证书，然后：
> `SIGN_ID="Curtain Dev" ./Scripts/make_app.sh`

## 使用

```bash
curtainctl on                 # 升起幕帘（屏幕变黑，输入被吞）
curtainctl status
curtainctl capture --out ~/Desktop/shot.png
curtainctl record start --out ~/Desktop/rec.mp4
curtainctl record stop
curtainctl audit 20
```

解除：**长按 Esc 两秒**（或 `curtainctl off`）→ Touch ID。除指纹外没有别的出口，也没有倒计时；猫踩出认证框也过不了指纹。

退出：`curtainctl off` 验指纹，或直接结束 curtaind 进程（窗口随进程销毁，不会把自己锁在外面）。

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
