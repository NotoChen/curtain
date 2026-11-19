# Curtain 0.9.0

首个公开版本：一个对物理世界生效、但对 Agent 的 framebuffer 采集透明的 macOS 可见性开关。

## 下载

- `Curtain-0.9.0.dmg`：推荐安装包。
- `Curtain-0.9.0.zip`：应用压缩包。
- `*.sha256`：对应产物校验和。
- `Curtain-0.9.0.SHA256SUMS`：zip 与 DMG 的合并校验清单。

要求 macOS 14 或更高版本。

## 首次打开

本项目没有购买 Developer ID，也没有 Apple 公证，使用 ad-hoc 签名。首次打开请二选一：

1. 在 Finder 中右键 `Curtain.app`，选择「打开」。
2. 将应用放入 `/Applications` 后执行：

```bash
xattr -dr com.apple.quarantine /Applications/Curtain.app
```

首次启动需要在系统设置完成两项授权：

- 设备控制和数据访问
- 录屏与系统录音

重装或重新构建后，ad-hoc 代码身份会变化，macOS 可能要求重新确认权限。

## 这个版本包含

- 默认黑色输出层 gamma 幕帘，Agent 的普通截图和录屏仍可拿到真实桌面。
- 物理输入拦截、系统手势拦截、Touch ID 出口和故障撤幕。
- 空闲自动起幕、定时保护、倒计时和多屏角色。
- 离开 / 会议 / 访客 / 专注四个场景，完整背景、时钟和消息配置。
- 四个可配置场景全局快捷键。
- `curtainctl` 截图、录屏、状态、诊断、审计和 URL 控制。

## 已知限制

- 不是软件安全边界，不隔离同用户进程。
- 默认 gamma 幕帘不能显示文字或图片；需要展示内容时使用明确 opt-in 的展示模式。
- 展示模式对常规 ScreenCaptureKit 透明，但 HDMI、采集卡和私有采集路径不保证。
- 没有付费签名和公证，不能保证 Gatekeeper 在所有机器上直接放行。
- 真实合盖运行受 macOS 电源策略和外接屏配置影响。

完整说明和验证记录见仓库 [README](README.md)。
