# Curtain

macOS 上的「幕帘」：**对物理世界生效的可见性开关，对 framebuffer 采集透明**。

屏幕在物理上是统一纯色（默认黑色）、键盘鼠标被锁住，但持有权限的 AI agent 仍然可以截取完整桌面、录制屏幕、合成点击——画面里没有幕帘，也不会有锁屏界面。

> 它不是锁屏。系统锁屏会把整个会话切到 loginwindow，任何第三方都拿不到画面（实测 `screencapture -l` 直接报 `could not create image from window`）。幕帘是解锁状态下的遮挡层，所以 agent 才能继续工作。

## 下载

从 [GitHub Releases](https://github.com/NotoChen/curtain/releases) 下载 `Curtain-0.9.0.dmg` 或 `Curtain-0.9.0.zip`。当前版本需要 macOS 14+。

项目使用 ad-hoc 签名，没有 Apple Developer ID 公证。首次打开请右键 `Curtain.app` →「打开」，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/Curtain.app
```

## 三条需求与实现

| 需求 | 实现 |
|---|---|
| 防猫误触键盘 | 主 tap 挂在 `kCGHIDEventTap`：**物理事件（来源 PID 0）一律吞掉，合成事件一律放行**——不维护任何进程名单；另一个 session tap 专门吞掉 Mission Control、Space 切换、Dock control 等系统手势，避免滑动时露出桌面 |
| AI 截屏/录屏不被遮挡 | 主路径把显示器 gamma 写成统一纯色（默认黑），作用在输出层、位于 framebuffer 之后；任意读取 framebuffer 的截图/录屏仍拿到真实桌面。`SCContentFilter` 再排除 Curtain 自己的认证窗口 |
| 隐私（挡住人的视线） | gamma 纯色作用于显示输出，盖住菜单栏、Dock、通知和 HDMI/采集卡；认证时恢复 gamma，用普通层级黑窗继续遮挡桌面。**gamma 不可用时失败撤幕，不退回普通黑窗** |

## 验证记录

以下是不同版本的证据，不把旧版本结果冒充成新版本结果。测试机为 Apple M1、双屏（内置 Retina + DELL 1920×1080）、macOS 27.2。

- **0.5.1 gamma 表完整性**：本机两块屏实际各有 **1024** 个 gamma 采样点；用 1024 点全零写入后读回全黑，再写回原表，两块屏均恢复成功。旧实现只读写 256 点，撤幕后可能留下色偏；已修复。
- **0.5.1 重新授权后运行验收**：`doctor` 全部关键项可用；幕帘开启时两屏 gamma 1024 点全部为 0，撤幕后最大通道值恢复为 1.0；幕帘下双屏截图均值分别为 **56.2667 / 42.8961**，关闭后为 **56.2668 / 42.8853**，前后平均绝对差仅 **0.1036 / 0.0662**；2 秒录屏得到 21 帧，抽帧均值 **57.5464**，没有出现黑幕。`./Scripts/test.sh` 为 **21 tests / 8 suites** 全通过。
- **0.6.0 安装后运行验收**：重新授权后 `doctor` 全部关键项可用；幕帘下截图均值 **162.1239**，未出现黑幕；`CURTAIN_CLIENT=codex` 的截图被审计为 `client=codex`，`session_summary` 记录了 1 次截图、1 次 Touch ID 请求和 `panic` 撤幕。`./Scripts/test.sh` 为 **26 tests / 9 suites** 全通过。双击 Esc、快捷键 toggle、认证取消和 Touch ID 成功解锁仍需人工确认。
- **0.5.0 输出层透明性**：gamma 全黑时截图亮度均值 **58.8798**，未黑时 **58.8077**；两次结果几乎一致，说明截图读取的是 framebuffer，不是被 gamma 改写后的显示输出。
- **0.5.0 CUA 对照**：在 gamma 全黑前后抓取同一张 CUA UI 截图，文件都是 **190,494 bytes**，SHA-256 都是 `47a3ca86093be73ceb2a107e328d8381d89799348e32712f1783e2249dacf060`，说明采集链路没有被黑幕污染。
- **0.4.0 历史回归**：全屏截图平均亮度 58.81，关闭幕帘时 58.81；幕帘下录屏 58 帧，抽帧平均亮度 59.6。
- **0.4.0 合成输入**：幕帘开启期间，系统 UI 自动化仍能向「系统设置」搜索框键入文本，随后 `curtainctl panic` 正常撤幕。
- **2026-11-11 `sharingType = .none` 复核**：双屏全屏测试窗，`.readOnly` 屏的 ScreenCaptureKit 截图/录制里约 **99.999%** 是测试色；`.none` 屏的截图/录制里测试色像素为 **0**。这说明常规 ScreenCaptureKit 路径确实尊重窗口共享排除，但只证明这一条路径，不证明 HDMI/采集卡或私有采集 API。因此它适合可选的展示模式，不能替代默认的 gamma 输出层幕帘。
- 0.5.0 的 `.none` 对照曾观察到 18 个残留采样点；该旧结论只说明“普通窗口不能作为无条件的采集透明保证”，不能外推成“窗口排除在所有采集路径上都无效”。
- Touch ID：`biometryType=1`，可用。
- **2026-11-13 0.7.0 验收**：重新授权后 `doctor` 全部关键项可用；双屏起幕后 `curtainctl capture` 得到 **3360×2100** 截图，均值 **186.33**；15fps 录屏得到 **30 帧 / 2.07 秒**，抽帧均值 **185.67**，没有整屏黑幕。幕帘期间记录 **96 次**物理输入拦截；当时的 `curtainctl report 1` 能显示调用方分组、活动时间线和误触片段，该回看入口已在 0.8.2 移除。用户随后完成双击 Esc、快捷键/Touch ID 和展示模式的人工验收，确认无问题。
- **2026-11-13 0.8.0 UI/识别增量**：应用图标重绘；菜单栏改为与图标一致的自定义幕帘轮廓；权限页收敛为两项权限和一个拖拽入口，不再触发 TCC 请求弹窗或叠加大授权窗口；报告改为结构化摘要、调用方、时间线、物理输入和退出验证卡片；控制 socket 通过 `LOCAL_PEERPID`、进程祖先链和强 Agent 环境标识识别真实调用方。真实 `curtainctl` 经独立 socket 验证时，进程链只有 `curtainctl → zsh`，结果仍正确归因为 `Codex`，不会把 `curtainctl` 当调用方。展示模式用 `.none/.readOnly` 对照窗实测：`curtainctl` 的 ScreenCaptureKit 截图和录屏中 `.none` 窗完全不可见，`.readOnly` 窗正常可见。当时源码为 **44 tests / 11 suites**。
- **2026-11-13 0.8.0 收尾修复**：`doctor` 在录屏权限缺失时跳过 SCK 可见窗口探测，避免打开系统录屏授权弹窗；状态和审计把 `caller_process` 固定为直接连接的可执行文件，并新增 `caller_parent` / `caller_parent_pid` / `caller_parent_path`，环境提示仍只作归因兜底；`record_stop` 在清理状态前保存真实调用方，不再把审计写成 `unspecified`；展示模式补上光标隐藏/恢复。这些修复随后进入 0.8.1 安装包。
- **2026-11-13 0.8.0 本地安装**：`/Applications/Curtain.app` 已替换为 0.8.0（build 7，ad-hoc），两项权限已重新授予；`curtainctl doctor` 实测为“全部关键项可用”，`curtainctl status` 返回 `caller=Codex`、`caller_environment=Codex` 和 PID 链。该安装版尚未包含本轮额外的 `doctor`/审计收尾修复；`build/Curtain.app` 已单独打包校验，但未替换安装版。
- **2026-11-13 0.8.1 本地安装**：应用图标改为本地图像模型生成的深炭黑/暗铜幕布源图，保留 `Resources/AppIconSource.png` 和可复现的 `Scripts/make_app_icon.sh`；菜单栏图标去掉外框，改用更宽的双帘片、帘杆和负空间下摆，真实 18px 菜单栏已截图检查。启动时只有设备控制权限已授予才创建全局快捷键 tap，未授权启动不再额外触发系统 TCC 同意框。`/Applications/Curtain.app` 为 0.8.1（build 8，ad-hoc），两项权限已恢复，`doctor` 实测全部关键项可用；`curtainctl capture` 得到 **3360×2100** 截图，2 秒录屏得到 **21 帧**，调用方归因为 `Codex`。
- **0.8.2 报告行为收口**：撤销报告历史下拉、独立历史窗口、状态面板「报告」按钮和 `curtainctl report` 命令；撤幕时只在当次显示一次结构化报告，Touch ID 和应急 `panic` 撤幕都会显示，自动睡眠/权限失效/故障撤幕不叠加弹窗。`session_summary` 审计不再写入完整报告文本，只保留时长、调用方、动作计数、物理拦截和撤幕原因等结构化审计字段。`./Scripts/test.sh` 为 **43 tests / 11 suites** 全通过。
- **0.8.3 体验收口**：状态面板待命时不再展示空的会话明细；撤幕报告只在有调用方/Agent 动作/误触时展开对应卡片，零活动会话保持一张摘要和退出验证；权限页与浮窗改为一句话告诉用户“打开系统设置、拖入当前 app、旧项先移除”，去掉无动作的签名解释；Release 脚本同时生成 zip、DMG 和各自 SHA-256。`./Scripts/test.sh` 为 **43 tests / 11 suites** 全通过；zip、DMG 与 SHA-256 已在本地校验。
- **2026-11-17 0.8.4 安装验证**：重新授权后 `doctor` 报告两项权限、双屏 SCK、输出层黑幕、tap、快捷键和审计链全部可用；`curtainctl capture` 得到 **3360×2100** 截图，2 秒录屏得到 **31 帧**，调用方审计归因为 `Codex`。状态面板授权状态变化后动态收高；设置、报告和首次引导按鼠标所在屏幕居中。
- **2026-11-17 0.8.5 历史验证**：新增 opt-in 活动颜色反馈；截图成功显示暖色脉冲，开始录制显示青色脉冲，结束录制显示灰色脉冲，只改写输出层 gamma，不进入 framebuffer。后续 0.8.6 已移除这条活动反馈和撤幕报告。
- **2026-11-17 0.8.6 展示收口**：展示模式只显示当前时间和已保护时长，不再显示 Agent、截图/录制次数或物理输入误触；移除活动颜色反馈、撤幕报告、报告回看和对应统计代码。默认 gamma 幕帘仍为黑色输出层，展示模式仍是 opt-in。`./Scripts/test.sh` 为 **38 tests / 9 suites** 全通过。
- **2026-11-17 0.8.7 展示时钟**：展示模式补齐年、月、日、时、分、秒、星期和中文农历；新增数字、表盘、日历三种可切换样式，均为 AppKit 原生绘制，不引入网页时钟运行时。设置页使用与实际幕帘相同的 `PresentationCanvasView` 预览；已用系统 HEIC 壁纸分别渲染三种样式和纯黑背景，确认背景图可读取、等比铺满并裁切，卡片内容和完整日期没有截断。`./Scripts/test.sh` 为 **41 tests / 10 suites** 全通过。这里验证的是共享画布的真实图像渲染，不是再次起全屏幕帘做人工验收。
- **2026-11-17 0.8.8 设置排版**：设置窗口默认高度从 660 调到 750，展示页预览在默认尺寸下完整可见；移除“常规采集已实测不可见”技术警告卡，保留在 README 的边界说明；权限页授权操作改为“说明在上、按钮在下”，并把旧项移除与拖入步骤合并到同一段，避免横向拥挤。已生成 920×750 的展示页和权限页预览检查。
- **2026-11-17 0.8.9 预览与拆分**：展示页新增“全屏试看”，用当前未保存的颜色、背景图和时钟样式覆盖全部显示器，默认 8 秒后自动退出，不进入幕帘状态、不锁输入、不触发 Touch ID；背景图改为 ImageIO 按屏幕像素需求降采样并缓存，多屏共享同一份解码图；时钟样式改为三张可视化卡片。数字、表盘、日历三种样式均已在双屏真实窗口验证，背景铺满和裁切正常，试看结束后无残留窗口。源码拆出 `PresentationBackgroundImage`、`PresentationCanvasView`、`PresentationPreviewSession`、设置页组件和采集控制；`./Scripts/test.sh` 为 **45 tests / 12 suites** 全通过。
- **2026-11-17 0.8.9 安装与展示模式回归**：`/Applications/Curtain.app` 已替换为 0.8.9（build 16，ad-hoc），两项 TCC 权限恢复后 `doctor` 报告全部关键项可用。真实展示模式起幕后，两块屏各有一个 `CGShieldingWindowLevel` 全屏窗口，`sharingType=.none`；`curtainctl capture` 仍得到 **3360×2100** 的完整桌面截图，没有把背景图或时钟写进采集画面。一次真实 Touch ID 撤幕成功，`panic` 撤幕后两个覆盖窗口均消失，幕帘恢复关闭。
- **2026-11-17 0.9.0 自动化、多屏与倒计时**：空闲输入达到阈值后自动起幕已实测（约 63 秒）；`curtainctl on/protect --minutes` 和 `curtain://on|protect|off|status|settings` 已验证；主屏展示、副屏 gamma 黑幕及反向角色均实测，重排显示器后角色仍保持；保护时长到点只发起 Touch ID，不会直接露出桌面。合盖模式使用屏幕/系统空闲断言，并已在模拟显示器休眠下保持幕帘；**真实合上笔记本盖子尚未验证**，最终仍受 macOS 电源策略和外接屏配置影响。`./Scripts/test.sh` 为 **54 tests / 13 suites** 全通过。
- **2026-11-18 0.9.0 设置交互**：设置页新增 `⌘S` 保存、`⌘1`–`⌘5` 切换页面、`Esc` 关闭和未保存状态；关闭、关闭按钮与 `Esc` 共用保存/不保存/取消确认，全屏试看与授权引导返回后保留草稿。数字输入补齐范围校验、整数分钟格式和工具栏提示；定时保护关闭时保留空星期选择，空掩码不会误触发保护。已生成 820×620 最小窗口的五个页面与深色模式截图检查；`./Scripts/test.sh` 为 **56 tests / 13 suites** 全通过。当时 `/Applications/Curtain.app` 为 0.9.0（build 18，ad-hoc），重签后两项 TCC 已恢复，`doctor` 报告全部关键项可用；后续场景迭代已更新到 build 20。
- **2026-11-18 0.9.0 场景与回座提示**：状态面板待命时新增「离开 / 会议 / 访客 / 专注」四个场景和 `30 / 60 / 120 分钟 / 不限时` 快捷起幕；开启后改为 `+30 / +60 / +120 / 不限时` 延长或取消倒计时。场景时长在自动化页持久化，默认分别是 2 小时、1 小时、30 分钟和 90 分钟；「会议 / 专注」强制输出层 gamma 黑幕，「离开 / 访客」只在展示模式已开启时使用时钟，未开启仍是黑幕。新增 `curtainctl scene away|meeting|guest|focus [--minutes N]`。展示模式新增一次性回座提示：起幕满 60 秒后首次真实 HID 输入时，底部短暂显示 Esc/Touch ID 提示，不自动认证、不撤幕、不显示统计。已生成待命、已遮挡、缺权限、820×620 自动化页、深色模式和回座提示预览；`./Scripts/test.sh` 为 **58 tests / 13 suites** 全通过。安装版实测：`scene meeting` 为 `black_display_ids=1,2`、`presentation_displays=0`；`scene away` 为 `presentation_displays=2`、`black_display_ids` 为空；展示模式下 `curtainctl capture` 仍得到 **3360×2100** 完整截图，`panic` 后无残留。回座提示只做了画布预览，未用真实物理 HID 在无人值守时触发。
- **2026-11-18 0.9.0 首次引导与结构拆分**：首次引导改为三步：先说明“幕帘挡人眼、不挡 Agent”，再说明起幕/保护/撤幕路径，最后给出菜单栏、展示模式和 `curtainctl` 的起点；支持上一步/继续、以后不再显示和直接打开设置。`main.swift` 只保留启动入口，主进程按控制、会话、自动化、显示、面板、系统、诊断、设置和采集拆分；设置窗口按通用、自动化、展示、权限、状态和布局拆分。三步引导的浅色/深色、五个设置页、820×620 最小窗口和未保存状态都做了截图回归；`./Scripts/test.sh` 为 **58 tests / 13 suites** 全通过。
- **2026-11-18 0.9.0 场景配置包**：场景从单一保护时长升级为完整配置包，离开/会议/访客/专注分别保存保护时长、展示方式、独立背景图、时钟样式、提示文字、预计返回时间和主/副屏角色。设置窗口新增独立「场景」页，共六页；场景预览会按展示模式总开关显示真实纯黑回退。状态面板按场景实际配置显示时长和展示策略。场景页改为紧凑双列，默认窗口优先露出预览、时长、提示文字、返回时间和背景设置；源码测试为 **61 tests / 13 suites**，并已生成 940×820 与 820×620 的明暗、纯黑和背景图预览。
- **2026-11-19 0.9.0 场景真机验收**：在当前安装版上依次启动四个场景并用 `panic` 收尾。`away` 为 120 分钟、双屏展示；`meeting` 为 60 分钟、双屏 gamma 黑幕；`guest` 为 30 分钟、双屏展示；`focus` 为 90 分钟、双屏 gamma 黑幕。每次撤幕后状态都回到 `curtain=off`，没有残留幕帘状态；`doctor` 报告全部关键项可用。
- **2026-11-19 0.9.0 自定义场景验收**：临时给 `away` 写入独立 HEIC 背景、模拟时钟、提示文字「自定义场景验收」、1 分钟保护、主屏展示/副屏黑幕。实际起幕后状态为 `presentation_display_ids=1`、`black_display_ids=2`，审计记录同时包含该背景路径、提示文字和 1 分钟保护。撤幕后原配置已完整恢复，当前幕帘关闭。
- **2026-11-19 0.9.0 场景入口收口**：状态面板在已遮挡和认证中显示当前场景；场景页新增「恢复默认」，已自定义场景在说明后标记，未自定义时按钮禁用。补充 820×620 最小窗口回归，确认场景页滚动区与底部操作栏不重叠。源码测试为 **61 tests / 13 suites** 全通过，`/Applications/Curtain.app` 更新为 0.9.0（build 24，ad-hoc）。
- **2026-11-19 0.9.0 场景快捷键**：四个场景新增独立全局快捷键，默认 `⌃⌥⌘1` / `⌃⌥⌘2` / `⌃⌥⌘3` / `⌃⌥⌘4`；设置页可录制、恢复默认，并阻止与主快捷键或彼此重复。状态面板场景卡片显示对应快捷键，`curtainctl status` 和 `doctor` 会报告监听状态。源码测试为 **63 tests / 13 suites** 全通过。

> 0.5.1 的 gamma、截图和录屏已在重新授权后补跑；物理键盘/鼠标、三/四指系统手势和 Touch ID 成功解锁仍需要人工复验，不能把本轮的自动结果当成“0.5.1 全量真机通过”。

> **当前安装版**：`/Applications/Curtain.app` 是 0.9.0（build 25，ad-hoc）；两项 TCC 权限、事件 tap、手势 tap、全局快捷键和审计链均已恢复，`doctor` 报告全部关键项可用。

## 组成

```
curtaind            菜单栏常驻进程（唯一持权限的进程）
  Shield            gamma 输出层纯色；认证时临时恢复 gamma 并使用黑窗
  InputGuard        HID 事件拦截（物理/合成二分）+ 双击/长按 Esc 手势
  CaptureBroker     截图 SCScreenshotManager / 录屏 SCStream
  AuthGate          Touch ID（唯一出口）
  Sentinel          防显示器休眠 / 系统睡眠
  HealthWatchdog    后台 tap/权限检查 + 主线程卡死看门狗
  ScreenSnapshot    用 displayID 锁定屏幕身份，不用数组下标
  ControlServer     unix socket 控制面 + JSONL 审计
curtainctl          瘦客户端，不需要任何权限
```

设计要点：**权限只授予 curtaind 一处**，agent 通过 `curtainctl` 走 socket，自己不持有屏幕录制权限。谁能截、截给谁，集中在 broker 里。注意这仍是**同一用户边界**，不是恶意进程隔离：同用户进程可以调用 `panic`、`kill` 或自己申请 TCC。

## 与现有产品的关系

这个方向已经不是空白，但没有一个开源成品同时满足「人看不到、Agent 的 framebuffer 采集仍然透明、Touch ID 是唯一正常出口」：

- [Lockpaw](https://github.com/sorkila/lockpaw)：最接近的成熟产品。它的覆盖层、agent hook、Touch ID/password fallback、合盖模式和签名分发做得更完整；但它的锁屏是可被采集到的 overlay，agent 提示光效也会进入画面。我们学习它的热键、可靠性和分发设计；当前不接 agent hook，不复制可见覆盖层、密码 fallback 和 root helper。
- [acamarata/curtain](https://github.com/acamarata/curtain)：面向 macOS Screen Sharing 的物理/远程输入分流，重点是远程会话，不是本机 Agent 的截图透明性。我们保留它的输入源分流思路，不采用它的远程会话检测和强制解锁路径。
- [iwaller/curtain](https://github.com/iwaller/curtain)：同样使用 gamma 输出层和 Touch ID，验证记录很扎实；它有密码 fallback、系统锁屏恢复和更重的 watchdog 结构。我们采用它的显示重配置、失败保护和发布验证经验，但不把密码 fallback 作为出口。
- **没有可以直接拿来替换本项目的成品**。能复用的是策略和实现经验，不是把 Lockpaw 或其它 app 直接改个名字。

## 构建

只依赖 Command Line Tools（不需要 Xcode）：

```bash
./Scripts/make_app.sh          # 产物：build/Curtain.app
open build/Curtain.app
```

应用图标源图在 `Resources/AppIconSource.png`。修改后运行 `./Scripts/make_app_icon.sh` 重新生成 `Resources/AppIcon.icns`。

> 代码目标为 macOS 14+；上述真机证据来自 macOS 27.2。macOS 14/15 的 gamma 行为、权限面板名称和 ScreenCaptureKit 兼容性仍需单独实测。

首次启动后到「系统设置 → 隐私与安全性」授予：

1. **录屏与系统录音**（截图/录屏）
2. **设备控制和数据访问**（事件拦截；macOS 26 起取代了原来的「辅助功能」）

缺权限时 Curtain 只打开系统设置和跨桌面拖拽浮窗，不再额外弹一个重复的大授权窗口，也不会调用 `CGRequestScreenCaptureAccess` 触发「想要录制屏幕」确认框。浮窗会自动贴在系统设置窗口旁边并随其移动；按住里面的 Curtain 图标，可以直接拖进隐私列表。两项权限都变绿后浮窗自动收起。

> macOS 26/27 把这两类权限并进了「设备控制和数据访问」面板，Curtain.app 会被自动加进列表，勾选即可。

> 默认 **ad-hoc 签名**，不依赖付费证书。代价很具体：ad-hoc 的代码身份会随构建变化，重新安装后你需要在系统设置里把 Curtain.app **取消再勾一次**（两个面板各一次）。app 检测到权限失效会自己弹引导面板。
>
> 这是 GitHub 开源分发下的明确取舍，不把 Developer ID/公证作为项目依赖。若你本机已有自签证书，可以自行用 `SIGN_ID="证书 CN"` 构建；项目不要求也不分发证书。
>
> 勾选完成后如果状态仍显示未授权，退出并重新打开 `/Applications/Curtain.app`；已经运行的旧进程需要重启后才会读取新的 TCC 结果。
>
> 安装到 `/Applications`：`INSTALL=1 ./Scripts/make_app.sh`（推荐，路径固定）。

### GitHub Release

项目只走 GitHub 开源分发，不申请付费 Developer ID。打 release 包：

```bash
./Scripts/package_release.sh
gh release create v0.9.0 \
  dist/Curtain-0.9.0.zip dist/Curtain-0.9.0.zip.sha256 \
  dist/Curtain-0.9.0.dmg dist/Curtain-0.9.0.dmg.sha256 \
  dist/Curtain-0.9.0.SHA256SUMS \
  --title 'Curtain 0.9.0' --notes-file RELEASE_NOTES.md
```

下载方首次打开 ad-hoc 构建时，右键 `Curtain.app` → 打开，或执行一次：

```bash
xattr -dr com.apple.quarantine /Applications/Curtain.app
```

zip、DMG 和各自的 SHA-256 sidecar 足够做来源一致性校验；它不等于 Apple 公证，也不承诺 Gatekeeper 直接放行。

版本变化见 [CHANGELOG.md](CHANGELOG.md)，发布说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。`.github/workflows/ci.yml` 会在 GitHub macOS runner 上执行测试和 release 构建；发布产物仍由维护者生成，以避免混淆不同 CPU 架构。

## 使用

```bash
⌃⌥⌘C                        # 幕帘关闭时起幕；开启时请求 Touch ID 撤幕
curtainctl on                 # 升起幕帘（屏幕变纯色，输入被吞）
curtainctl protect --minutes 30  # 起幕并设置保护时长；到点只请求 Touch ID
curtainctl scene away --minutes 120  # 场景起幕：away / meeting / guest / focus
curtainctl status             # JSON 状态
curtainctl doctor             # 自检：权限 / 屏 / gamma 黑幕 / tap / 手势 tap / 快捷键 / Touch ID / 审计链 / 自启
curtainctl capture --out ~/Desktop/shot.png --client codex
curtainctl capture --all --out ~/Desktop/shots/s.png    # 每屏一张
curtainctl capture --display-id 1 --out ~/Desktop/shot.png
curtainctl capture --region 100,100,400,300 --cursor    # 区域截图（点），带光标
curtainctl record start --out ~/Desktop/rec.mp4 --fps 30 --bitrate 8000000
curtainctl record stop
curtainctl audit 20           # 最近 20 条
curtainctl audit --verify     # 校验哈希链
curtainctl install-agent      # 开机自启（LaunchAgent，KeepAlive 兼作崩溃看门狗）
curtainctl uninstall-agent
curtainctl panic              # 应急强制撤幕，不验指纹
```

也支持从 Shortcuts、终端或其它应用打开 URL：

```text
curtain://on?minutes=30
curtain://protect?minutes=30
curtain://off
curtain://status
curtain://settings
```

`on` / `protect` 的 `minutes` 会限制在 0–1440；`off` 仍走 Touch ID。URL 有意不支持 `panic`，避免网页或不可信应用绕过应急出口。

`capture` / `record start` 的返回 JSON 和审计记录会带上真实调用方。Curtain 从本地 socket 读取 peer PID，沿父进程链跳过 `curtainctl` 和常见 shell；如果父链被 launcher 截断，再用 peer 进程环境里的强标识（`CODEX_*`、`CLAUDE_CODE_*`、`CURSOR_*` 等）补齐。记录例如 `Codex`、`Claude`、`Terminal` 或 `python3`，同时保存完整 PID 链、可执行文件路径、直接进程、父进程和环境提示。`--client` / `CURTAIN_CLIENT` 仍可作为任务标签，但只作为补充，不冒充真实身份。

环境提示只在进程链不足以识别 Agent 时兜底，不是安全认证；同一用户下的进程可以伪造环境变量。需要严格追责时，以 PID 链、可执行路径和审计链为准。

解除方式：

- **双击 Esc**（默认间隔 0.7 秒）→ Touch ID。
- **再次按 `⌃⌥⌘C`** → 同一个 Touch ID 流程。
- 长按 Esc 2 秒仍保留为兜底 → Touch ID。
- `curtainctl off` 走同一路径；Touch ID 通过后才真正撤幕。
- 认证框显示期间再按一次 Esc 会取消认证，回到仍然锁住的幕帘。

正常交互只有指纹出口；猫踩出认证框也过不了指纹。`panic`、本地 `kill` 和进程级调试属于应急出口，不是认证路径。

### 卡住了怎么办

按优先级：

1. `curtainctl panic` —— 走本地 socket 强制撤幕，不验指纹。猫不会敲命令，这是安全的自救口。
2. `pkill -TERM curtaind` —— 进程一死，macOS 恢复 gamma，黑幕和输入限制一起消失。
3. 生物识别硬件不可用时，`curtainctl off` 会直接撤幕并记 `biometrics_unavailable` 审计，不会把人锁在黑屏里。

> 退出入口必须做在事件 tap 内部，不能做成菜单项：幕帘期间物理鼠标被吞掉，菜单根本点不到。

## 设置

菜单栏图标 → **状态面板** → **设置**。设置窗口分为六页：

- **幕帘行为**：双击 Esc 间隔（0.3–1.5 秒）、长按 Esc 兜底阈值（1–5 秒）、起幕/撤幕快捷键、输出层纯色背景、幕帘期间是否隐藏鼠标指针。
- **自动化**：空闲自动起幕、每日定时保护（支持跨午夜、按星期选择）、时段结束验证退出、默认保护时长，以及合盖继续运行的电源断言。所有自动结束只发起 Touch ID，不会直接撤幕。
- **场景**：为离开、会议、访客、专注分别配置快捷键、保护时长、纯黑或背景与时钟、独立背景图、时钟样式、提示文字、预计返回时间和主/副屏角色。场景只影响当前这次会话；展示模式总开关关闭时全部退回纯黑幕帘，配置仍保留。
- **展示模式（可选）**：默认关闭。开启后用窗口显示自定义背景图，以及年、月、日、时、分、秒、星期和农历；可选数字、表盘、日历三种原生时钟样式。背景图可设置焦点、1–2× 缩放和暗化，支持全屏试看；主屏和副屏可分别选择展示或 gamma 黑幕。普通 ScreenCaptureKit 已实测不可见，但 HDMI/采集卡会看到窗口，见「边界」。
- **权限**：两项权限的实时状态和单一「打开系统设置」入口；授权时显示带可拖拽 app 图标的跨桌面浮窗，不再叠加大授权窗口。
- **诊断**：复制诊断信息、打开审计日志、打开配置文件。

保存后立即生效，不需要重启 app。设置窗口支持 `⌘S` 保存、`⌘1`–`⌘6` 切换页面和 `Esc` 关闭；有未保存修改时底部会明确提示，关闭窗口会询问保存、不保存或取消。全屏试看或授权引导返回后，当前草稿不会丢失。截图目录/码率/帧率这些是命令行参数（`--out`、`--fps`、`--bitrate`、`--client`），不进设置窗口。

菜单栏左键直接打开状态面板：顶部显示幕帘状态、快捷键和已保护时长；不再展示 Agent、截图/录制或物理输入统计。待命时提供「离开 / 会议 / 访客 / 专注」场景和 `30 / 60 / 120 分钟 / 不限时` 快捷保护；场景卡片直接显示各自的全局快捷键。幕帘开启后，同一区域改为延长保护或取消倒计时。底部提供设置和退出入口；缺权限时，权限修复卡会优先出现在首屏。

## 配置文件

`~/Library/Application Support/Curtain/config.json`

```json
{
  "holdToAuthSeconds": 2,
  "doubleEscapeSeconds": 0.7,
  "safetyTimeoutSeconds": 0,
  "hideCursorDuringCurtain": true,
  "curtainColor": "#000000",
  "hotkeyKeyCode": 8,
  "hotkeyModifiers": 1835008,
  "sceneHotkeys": {},
  "hasShownOnboarding": false,
  "presentationModeEnabled": false,
  "presentationImagePath": "",
  "presentationClockStyle": "digital",
  "mainDisplayRole": "presentation",
  "secondaryDisplayRole": "presentation",
  "presentationFocusX": 0.5,
  "presentationFocusY": 0.5,
  "presentationZoom": 1,
  "presentationDim": 0,
  "idleAutoCurtainEnabled": false,
  "idleAutoCurtainSeconds": 600,
  "scheduleEnabled": false,
  "scheduleStartMinutes": 540,
  "scheduleEndMinutes": 1080,
  "scheduleWeekdays": 127,
  "scheduleAutoExit": false,
  "defaultProtectionMinutes": 0,
  "sceneProfiles": {
    "away": {
      "protectionMinutes": 120,
      "usesPresentation": true,
      "backgroundImagePath": "",
      "clockStyle": "",
      "message": "离开中",
      "showsReturnTime": true
    }
  },
  "clamshellModeEnabled": false
}
```

- 截图目录、帧率、码率是命令行参数（`--out` / `--fps` / `--bitrate`），不在配置里。
- `curtainColor` 是默认 gamma 模式的输出层纯色，格式 `#RRGGBB`；设置窗口提供颜色选择器。默认模式**不支持图片或文字**：gamma 没有空间信息，放进去就必须进入 framebuffer。若要显示图片/文字，只能另做明确标注取舍的展示模式。
- `hotkeyKeyCode` / `hotkeyModifiers` 是起幕和撤幕共用的快捷键绑定；设置窗口可以直接录制。必须包含 ⌃ / ⌥ / ⌘ 之一。
- `sceneHotkeys` 以场景 rawValue 为键保存独立快捷键；缺省时使用 `⌃⌥⌘1`–`⌃⌥⌘4`。设置窗口会阻止它与主快捷键或另一个场景重复，非法绑定会回退到该场景默认值。
- `presentationModeEnabled` / `presentationImagePath` / `presentationClockStyle` 是可选展示模式。开启后改用 `sharingType=.none` 窗口，背景图会等比铺满并裁切；时钟显示年、月、日、时、分、秒、星期和农历。`presentationClockStyle` 可选 `digital`、`analog`、`editorial`，非法值回退 `digital`。已实测 Curtain 的普通 ScreenCaptureKit 截图和录屏看不到该窗口；HDMI、采集卡及绕过 ScreenCaptureKit 的采集不在其控制范围内。
- `mainDisplayRole` / `secondaryDisplayRole` 是每块屏的角色：`black` 使用输出层 gamma 幕帘，`presentation` 使用展示窗口。展示模式关闭时两者都被强制为 `black`，避免把窗口当作默认保护层。
- `presentationFocusX` / `presentationFocusY`（0–1）、`presentationZoom`（1–2）、`presentationDim`（0–0.8）控制背景图焦点、缩放和额外暗化。
- `idleAutoCurtainSeconds` 是物理输入空闲阈值，范围 60–86400 秒；只触发一次，真实输入后重新武装。
- `scheduleStartMinutes` / `scheduleEndMinutes` 是从 00:00 起的分钟数；开始晚于结束表示跨午夜，相等表示选中日期的全天保护。`scheduleWeekdays` 是周一至周日 bit 0–6 的位掩码；定时保护关闭时允许为 `0`，启用时必须至少选择一天。
- `scheduleAutoExit` 开启后，定时窗口结束时只发起 Touch ID；`defaultProtectionMinutes` 是每次普通起幕的倒计时，到时同样只发起验证。
- `sceneProfiles` 是场景完整配置包，键为 `away`、`meeting`、`guest`、`focus`；未写入的键使用场景默认值。每个场景可独立覆盖 `protectionMinutes`、`usesPresentation`、`backgroundImagePath`、`clockStyle`、`message`、`showsReturnTime`、`mainDisplayRole` 和 `secondaryDisplayRole`。`0` 表示不限时；展示模式总开关关闭时所有场景仍强制 gamma 黑幕。
- `clamshellModeEnabled` 只请求系统防休眠断言；真实合盖是否保持运行仍由 macOS 电源策略和外接屏状态决定。
- `safetyTimeoutSeconds`：开发兜底，秒；`0` 表示关闭（默认）。不参与产品行为。

审计：`~/Library/Application Support/Curtain/audit.log`，每次入幕/撤幕/截图/录屏一行 JSON，截图带 sha256。审计链用于发现中途改写、删除和损坏；它不是密码学意义上的防篡改，不能防同用户重写整份文件或截断末尾。

## 边界

- 挡不住电源键、长按强关——物理动作不在事件流里。合盖模式只申请屏幕/系统空闲断言，不能覆盖所有电源策略；“外接屏在位 + 模拟显示器休眠保持幕帘”已验证，真实合盖仍需逐台复验。
- 挡不住 USB 设备接入这类系统级动作。
- 幕帘期间会话保持解锁：这是前提，不是副作用。系统一旦锁屏，采集立刻失效。
- 幕帘只解决「屏幕内容在物理上不可见」，不解决「有屏幕录制权限的进程能不能拿到画面」——那是授权与审计问题。
- **gamma 纯色的是显示输出，不是 framebuffer**：本机截图/录屏以及远程屏幕共享读取 framebuffer 时仍能看到真实桌面。这是让 agent 继续工作的必要条件，也意味着它不是远程隐私工具。
- **默认幕帘上不能显示文字/图片**：gamma 表只有整屏通道映射，没有空间信息。任何可见文字、图标、图片都会进入 framebuffer，破坏 Agent 采集透明性；需要时间等信息时只能启用明确标注取舍的展示模式。
- **背景图为什么不做成默认**：全屏图片只能做成 `sharingType=.none` 的窗口。2026-11-13 用 `.none/.readOnly` 对照窗重新实测，Curtain 的 ScreenCaptureKit 截图和录屏中 `.none` 窗完全不可见、`.readOnly` 窗正常可见；但 HDMI/采集卡、私有采集路径不在保证范围内。因此它被实现成明确标注取舍的 opt-in「展示模式」，默认关闭，不能替代默认的 gamma 输出层幕帘。
- **展示模式不是更强的幕帘**：它的窗口层级、输入拦截和 Touch ID 出口与默认模式相同，但显示和采集保证更弱。只用于愿意接受这个取舍的视觉展示场景。
- **回座提示只属于展示模式**：默认 gamma 幕帘没有空间信息，不能显示文字；展示模式下的提示只在起幕满 60 秒后首次检测到真实 HID 输入时出现一次，不参与退出或认证。
- **调用方记录只用于审计**：`curtainctl capture`、`record_start/stop` 会写入调用方和路径；这不是屏幕内容统计，也不在撤幕后生成报告。真实调用方优先由 socket peer PID 和父进程链识别；`--client`/`CURTAIN_CLIENT` 只是任务标签，不是身份认证。
- **自动化不是自动解锁**：空闲起幕、定时保护和倒计时只负责进入保护或发起 Touch ID；系统睡眠、权限失效、覆盖失败等故障路径会失败撤幕，不会留下“显示为开启但实际没有遮挡”的状态。
- **gamma 读回为黑不等于所有面板都物理变黑**：HDR、特殊色彩配置、外接矩阵/采集卡仍需逐台实测；`doctor` 只证明系统接受了 gamma 表，不能代替眼睛验收。
- **不限制本机进程的合成输入**：任何 agent、终端、自动化工具都能在幕帘期间照常操作。幕帘不是软件安全边界，是物理可见性开关。
- **合成事件必须带来源 PID**：来源 PID 为 0 的事件按物理输入处理；agent 应使用 `CGEventSource` 等带来源的方式投递点击和键盘。
- **手势流按物理输入处理**：合成触控板手势也会被拦截；需要 GUI 操作的 agent 使用点击、键盘和截图这条路径。
- 本地控制 socket 只拒绝其他用户，不区分同用户的进程；`panic` 和采集都沿用这个产品边界。

## 可靠性设计

- **单实例**：`flock` 守门，第二个实例若发现已有健康实例就静默退出（launchd 的 RunAtLoad 也走这条路，不会弹窗打扰）。
- **开机自启**：LaunchAgent + `KeepAlive`，进程被杀会被 launchd 拉起；`doctor` 里能看到加载状态。
- **录制抗崩溃**：`movieFragmentInterval = 2s`，即使进程被强杀，mp4 仍可播放。
- **审计完整性**：每条记录带 `prev` 与 `hash`，`curtainctl audit --verify` 能定位中途修改或删除；旧格式记录可出现在升级边界，但必须先结束旧段并从空 `prev` 开新链，尾部残留旧格式仍判为断裂。
- **稳定屏幕身份**：gamma 黑幕、认证窗口、截图和录屏都按 `CGDirectDisplayID` 定位，显示器热插拔/重排不会把第 0 块屏指向另一块屏。
- **混合多屏先遮后换**：显示器重配时先把新增的 black 屏纳入 gamma，再移除不再需要的展示窗口，最后收窄 gamma 目标，避免布局切换时露出一帧桌面；任一覆盖角色无法建立就失败撤幕。
- **采集透明**：gamma 黑幕位于 framebuffer 之后；截图/录屏读取 framebuffer，因此仍是真实桌面。启动、睡眠唤醒和显示器重配后会持续补涂 gamma；补涂失败不会偷偷换成普通黑窗，而是立即撤幕并提示。
- **gamma 表精度**：按显示器实际采样点数保存/恢复（本机为 1024 点，不按 256 点截断），避免撤幕后色偏。
- **崩溃自恢复**：gamma 属于当前进程，Curtain 退出/崩溃时 macOS 会自动恢复；正常撤幕还会用启动前保存的 gamma 表主动恢复。
- **手势覆盖**：除键盘、鼠标、滚轮和平板事件外，session 级 tap 还拦截 Dock control、Mission Control、Space 切换和触控板手势；不再依赖“黑窗刚好盖住”来赌系统动画。
- **输入失效保护**：后台 watchdog 每 500ms 检查主 tap、手势 tap 和两项权限；任一失效就自动撤幕，而不是留下“黑屏但仍可操作”的状态。
- **反复失效熔断**：事件 tap 在 10 秒内被系统禁用并重试 5 次仍不稳定时，不再无限重试，立即按失效处理并撤幕；稳定 30 秒后才清除熔断状态。
- **权限撤销保护**：幕帘期间撤销录屏或设备控制权限，同样自动撤幕。
- **空闲输入来源**：自动起幕读取 `IOHIDSystem.HIDIdleTime`，只把真实 HID 操作视为“有人在用”，agent 合成事件不会让空闲阈值永远达不到。
- **主线程故障保护**：主线程连续 8 秒没有心跳时，后台 watchdog 结束进程，让 macOS 恢复 gamma 并恢复物理输入；已安装 LaunchAgent 时会自动拉起。
- **分辨率**：截图/录屏按 `backingScaleFactor` 还原真实像素（Retina 上是 2x，不再只有一半）。

## 测试

```bash
./Scripts/test.sh
```

只依赖 Command Line Tools。脚本会处理 CLT 的 Swift Testing 宏插件路径；用 Xcode 工具链时直接 `swift test` 也可以。

调试真实 `curtainctl` 的调用方识别时，可以设置 `CURTAIN_CONTROL_SOCKET=/tmp/.../control.sock` 让它连接隔离的 `ControlServer`；不设置时仍使用固定路径 `~/Library/Application Support/Curtain/control.sock`。

## Roadmap

P0（已完成）：单实例、自启、doctor、区域/多屏/光标、fps/码率、录制分片、审计哈希链。

0.6.0（已安装，自动验收通过；双击 Esc、快捷键 toggle、认证取消和 Touch ID 成功解锁待人工交互验收）：双击 Esc/快捷键 toggle/认证取消、输出层纯色背景、物理输入统计、撤幕后幕帘报告。

0.7.0（已安装，自动验收和用户人工验收均通过）：报告升级为按 Agent 分组、最近活动时间线和误触片段；当时提供 `curtainctl report` 与「历史报告…」，该回看入口已在 0.8.2 移除；首次使用引导；可配置起幕/撤幕快捷键；可选展示模式（等比铺满背景图 + 实时 Agent/误触状态，认证期间保留全屏遮挡）；设置页改为可滚动内容 + 固定操作栏；撤幕时序改为先恢复屏幕再放行物理输入。当时的源码测试为 **35 tests / 10 suites**。

0.8.0（历史版本，已由 0.8.1 取代）：重绘应用图标并改用自定义幕帘菜单栏轮廓；权限页收敛为两项状态和一个系统设置入口，授权只保留拖拽浮窗；报告改为结构化卡片，0.8.2 之前保留最近 5 次；截图/录制记录真实调用进程、PID 链、可执行路径和环境提示；展示模式完成 `.none/.readOnly` 截图与录屏对照实测。当时源码为 **44 tests / 11 suites**。

0.8.1（历史版本，已由 0.8.2 取代）：使用本地图像模型生成深炭黑、暗铜幕布和暖金光缝的应用图标，保留 1024px 源图与可复现的 `Scripts/make_app_icon.sh`；菜单栏图标去掉外框，改为更宽的双帘片、帘杆和负空间下摆，认证锁与录制点保留。该版本同时包含 0.8.0 的 doctor/调用方审计/光标恢复收尾修复，并避免未授权启动时由全局快捷键探测触发系统 TCC 同意框。

0.8.2（历史版本，已由 0.8.3 取代）：报告只在本轮撤幕后显示一次，移除报告历史下拉、独立历史窗口、状态面板「报告」按钮与 `curtainctl report`；Touch ID 和 `panic` 撤幕都会汇报，自动睡眠、权限失效和故障撤幕不叠加弹窗；审计只保留结构化会话摘要，不再写入完整报告正文。当时源码为 **43 tests / 11 suites**。

0.8.3（历史版本，已由 0.8.4 取代）：待命状态面板隐藏空会话明细；报告按内容展开调用方、Agent 动作和误触卡片；权限引导收敛为三个动作；Release 脚本生成 zip + DMG + SHA-256。源码为 **43 tests / 11 suites**，zip、DMG 与 SHA-256 已本地校验。

0.8.4（历史版本，已由 0.8.5 取代）：状态面板在授权状态变化后动态调整高度；设置、报告和首次引导窗口按鼠标所在屏幕居中，双屏/多 Space 下不再固定跑到主屏；新增 DEBUG 预览截图入口用于检查界面边界。源码为 **43 tests / 11 suites**，安装版采集冒烟通过。

0.8.5（历史版本，已由 0.8.6 取代）：新增 opt-in 活动颜色反馈；后续因“人不在场时实时反馈没有价值”而移除。源码为 **46 tests / 11 suites**，release 构建通过。

0.8.6（历史版本，已由 0.8.7 取代）：展示模式收口为当前时间和已保护时长；移除 Agent/截图/录制/物理输入统计、活动颜色反馈、撤幕报告、报告回看和对应测试。源码为 **38 tests / 9 suites** 全通过。

0.8.7（历史版本，已由 0.8.8 取代）：展示模式补齐年月日、时分秒、星期和农历，新增数字、表盘、日历三种原生样式；自定义背景图接入同一展示画布，并完成三种样式、纯黑背景和 HEIC 背景图的实际渲染检查。源码为 **41 tests / 10 suites** 全通过。

0.8.8（历史版本，已由 0.8.9 取代）：设置窗口提高到默认 750pt，展示页预览默认完整可见；移除展示页的技术警告卡；权限页把授权说明与操作按钮改为上下布局，并合并重装与旧项处理说明。默认 gamma 幕帘和展示模式行为不变，当时源码为 **41 tests / 10 suites**。

0.8.9（历史版本，已由 0.9.0 取代）：新增全屏试看、背景图按目标像素降采样与缓存、可视化时钟样式选择器；完成双屏三种时钟样式和背景裁切的真实窗口验证；继续拆分展示画布、背景加载、试看会话、设置页组件和采集控制。源码为 **45 tests / 12 suites** 全通过。

0.9.0（当前源码）：新增空闲自动起幕、每日定时保护、跨午夜/按星期保护时段、默认保护时长；到时只发起 Touch ID。新增主/副屏 black/presentation 混合角色、显示配置变化下的先遮后换、`curtainctl protect`、`curtainctl scene` 和 `curtain://` URL 命令；展示模式补充背景焦点、1–2× 缩放、暗化和全屏试看。状态面板新增四个场景预设和快捷保护/延长倒计时；设置页新增独立「场景」页，场景保存快捷键、保护时长、展示方式、背景、时钟、提示文字、预计返回时间和屏幕角色。展示模式新增一次性回座提示，不改写认证路径。设置窗口会按可见屏幕自适应，展示模式高级项改为紧凑双列布局；侧栏导航增加辅助功能标签。设置页新增 `⌘S`、`⌘1`–`⌘6`、`Esc`，未保存状态、关闭确认和安全取消；试看或授权引导返回时保留草稿，关闭定时时不再把空星期选择强制改成周一，且空选择不会误触发定时保护。首次引导改为三步，主进程和设置窗口按职责拆分，`main.swift` 只保留入口。合盖模式使用屏幕/系统防休眠断言；真实合盖仍需逐台复验。源码为 **63 tests / 13 suites** 全通过。

P1（候选，按价值排序）：

1. **GitHub 分发收口**：Release zip/DMG、SHA-256、ad-hoc 首启说明、Homebrew tap；不依赖付费 Developer ID。（zip + DMG + SHA-256 已完成；Homebrew tap 仍可补）
2. **离座自动落幕**：空闲/定时起幕已完成，且**不自动解锁**；后续可补充更细的“离开检测”传感器策略，但撤幕仍只认 Touch ID。
3. **真机回归**：Mission Control、三/四指 Space、Dock、通知中心、全屏应用、显示器热插拔、权限撤销；展示模式的双屏与热插拔。
4. **音频与测试**：录屏带麦克风/系统声音；状态机单测 + 录制端到端回归。

## License

MIT。见 [LICENSE](LICENSE)。
