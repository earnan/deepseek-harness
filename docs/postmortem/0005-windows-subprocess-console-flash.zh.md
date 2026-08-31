# 事故复盘（postmortem） 0005：无控制台 Web 宿主启动的 Windows 子进程发生闪窗

[English](0005-windows-subprocess-console-flash.md) | 中文

Status: 等待现场验收

## 摘要

尽管 Web 宿主本身以无控制台方式运行，短时 Bash 和 PowerShell 工具调用仍会在用户的 Windows 桌面打开一闪而过的控制台窗口。Proxy 和隧道活动会触发工作，但不创建窗口。共享普通 subprocess provider 现在会在 Windows 请求 `windowsHide`，但用户在 DSH 工作期间后来再次观察到闪窗，因此源码检查不能证明每条真实执行路径都经过该 provider。DSH preset 已将 `custom-bash` 固定为系统 Git Bash，不再从继承的 `PATH` 解析 WorkBuddy 自带的 PortableGit；这会隔离可执行文件来源，但本身不能证明不会创建控制台。现场验收仍待完成。

## 概述

Web launcher 能以无可见控制台方式启动 Node.js 宿主，但该属性不会传播给后来创建的控制台子系统子进程。共享的 `@deepseek-ai/dsh-subprocess-local` 普通 spawn 路径会在 Windows 显式设置 Node 的 `windowsHide` 选项，但可见闪窗仍可能来自替代或嵌套的进程创建路径。标题指向 Bash 的短时窗口只能识别可执行文件，不能精确定位创建该控制台的调用点。

Proxy 请求、浏览器活动和隧道可以促使会话运行工具，却不会创建本地进程窗口。Proxy 和隧道 listener 停止后，闪窗仍然发生。高频采样把 Web 宿主与 Bash、`conhost.exe` 连接起来，捕获到的标题识别出 WorkBuddy 的 PortableGit Bash。DSH 的 `custom-bash` 会从继承的 `PATH` 解析该路径，因此 preset 配置可能让 DSH 使用 WorkBuddy 自带 Git，但这不能证明由 WorkBuddy 本身创建了窗口。

## 影响

Web 应用执行普通本地工具时，用户可能看到间歇性控制台窗口。命令仍能完成且输出正确，但闪窗会干扰桌面使用，并让 GUI 显得不稳定。事故没有造成数据丢失、权限变化或命令执行范围扩大。

最初与 Proxy 和隧道活动的相关性延长了诊断过程，也可能导致修复落入一个并不拥有 Windows 进程创建的层。诊断会话自身启动的 Bash 和 PowerShell 子进程还会产生相似的进程噪声。

## 时间线

- Web manager 使用隐藏窗口进程选项启动应用，而共享的普通 subprocess provider 需要显式 Windows 子进程窗口策略。
- 用户观察到反复闪窗，最初检查 LAN Proxy 改写、浏览器请求和 SSH 隧道活动。
- 所有 Proxy 和隧道 listener 停止后问题仍能复现，证明它们不是必要条件。
- 捕获到的标题识别出 WorkBuddy 的 PortableGit `bash.exe`；高频采样随后观察到 `Web node.exe -> bash.exe -> conhost.exe` 及等价的 PowerShell 进程链。
- 源码检查确认 `spawnSubprocess()` 在 Windows 路径设置 `windowsHide: true`；Liangshen preset 在 Windows 禁用 PTY，并通过普通 subprocess service 执行 `custom-bash`。
- 用户在 DSH 工作期间后来再次观察到闪窗，因此静态的普通 spawn 策略不能证明覆盖了被观察到的运行时路径。
- 所有已发现包含 `custom-bash` 的 preset 均使用 `C:\Program Files\Git\bin\bash.exe`，避免继承 `PATH` 的顺序选择 WorkBuddy PortableGit。
- 修复启动器最初没有保留 DSH JavaScript 入口路径中的空格，Node 因而报告 `Cannot find module 'D:\\Program'`；启动器现会在启动 DSH 前引用该入口路径。

## 根因

原始缺陷是把宿主窗口隐藏误当成无闪窗应用的充分条件。然而在 Windows 上，是否分配窗口也是一项子进程创建决策。管道 stdio、detached 进程设置和隐藏父进程都不能单独要求普通控制台子系统子进程保持不可见。

诊断期间的所有权模型不清晰。网络和浏览器组件拥有“何时请求工作”，`@deepseek-ai/dsh-subprocess-local` 则拥有“如何创建可执行文件”。时间相关性把注意力引向触发层，而不是进程创建层。

普通 spawn 单元测试现在会断言 Windows 窗口选项，但它只能证明交给该 provider 的选项，不能证明嵌套 shell、依赖项或其他进程 provider 没有创建被观察到的窗口。运行观察还必须包含一次正向触发：如果观察期间没有闪窗也没有启动 shell，就不能证明缺陷已经修复。

## 已添加的防护措施

- [`spawnSubprocess()`](../../packages/subprocess/subprocess-local/src/spawn.ts) 在有效平台为 `win32` 时设置 `windowsHide: true`；POSIX 行为和调用方选择的 stdio 保持不变。
- [`spawn.spec.ts`](../../packages/subprocess/subprocess-local/tests/spawn.spec.ts) 注入记录型 spawner，在执行真实子进程的同时固定 Windows 平台路径使用 `true`，POSIX 路径使用 `false`。
- [`subprocess-local` README](../../packages/subprocess/subprocess-local/README.zh.md)说明普通 Windows 子进程会隐藏控制台，同时不改变 stdio 处置方式。
- [已实现的 Agent Note](../../.agents/notes/implemented/bug-fix/2026-08-24-hide-windows-ordinary-subprocess-consoles.zh.md)记录进程创建决策、被否决的 Proxy 层与消费方层替代方案，以及普通 subprocess 与 ConPTY terminal 的区别。
- 修复启动器会为每个已发现的 `custom-bash` preset 写入显式系统 Git Bash 路径、备份每个目标、验证替换结果，并以引用后的 JavaScript 入口路径启动 DSH。备份目录保留启动日志。
- Windows 现场验收以无控制台方式启动真实 Web 宿主，调用一次真实 Bash 工具，验证其输出与退出，采集完整 DSH 后代进程链，并要求被调用 Bash 的路径为配置的系统 Git 路径、目标子进程没有可见主窗口。

## 教训

- 隐藏 GUI 宿主不等于隐藏控制台子系统子进程；每个 Windows 普通进程创建边界都需要显式窗口策略。
- 触发工作的组件不一定是创建可见操作系统资源的组件。窗口标题、进程父子证据和源码所有权必须一致，才能归因。
- 短命进程缺陷需要高频观察。诊断工具也会制造 Bash、PowerShell 和 `conhost.exe` 噪声，必须通过进程祖先关系将其与被测对象分开。
- 显式可执行文件路径只能隔离来源，不能抑制窗口。必须让真实入口创建目标子进程，同时观察功能输出、后代关系、可执行文件路径和窗口状态。
