# Agent Note: 隐藏 Windows 普通子进程控制台

Status: implemented

[English](2026-08-24-hide-windows-ordinary-subprocess-consoles.md) | 中文

## Problem

Web 及其他 GUI 或后台 launcher 可以在没有附加 Windows 控制台的情况下运行。本地 subprocess provider 从这种宿主启动控制台子系统可执行文件时，如果没有请求隐藏窗口，Windows 可能会分配一个可见控制台。于是，即使 stdio 已通过管道传输且调用方没有请求交互式 terminal，短时 Bash 和 PowerShell 工具调用仍会表现为一闪而过的窗口。

该行为归 `@deepseek-ai/dsh-subprocess-local` 的普通进程创建所有。Proxy 流量、浏览器请求和各个 shell 消费方可以触发命令，但都不拥有 Windows 进程窗口。

## Decision

`spawnSubprocess()` 仅在有效平台为 `win32` 时设置 Node 的 `windowsHide` spawn 选项。Provider 继续使用调用方显式指定的 stdin、stdout 和 stderr 处置方式，并继续通过 `taskkill /T /F` 终止 Windows 进程树。POSIX 子进程保留现有 detached 进程组，不请求隐藏窗口。

Terminal session 仍是独立路径。`spawnTerminal()` 继续使用 `node-pty` 和 ConPTY，因为交互式 terminal 需要伪控制台，而不是普通隐藏子进程。

## Verification

普通 spawn 单元测试注入一个记录型 spawner，在执行真实子进程的同时固定 Windows 平台路径使用 `windowsHide: true`，POSIX 路径使用 `false`。Windows 现场验证在无控制台状态下启动 Web 宿主，执行短时 Bash 和 PowerShell 工具调用，并观察 shell 窗口不再可见，同时工具结果仍能收到输出和退出状态。

## Alternatives considered

**在每个 launcher 或 shell 消费方中隐藏窗口。** 拒绝，因为 Web launcher 只控制宿主窗口，而 Bash、PowerShell、LSP、MCP 和未来消费方都会到达同一个普通进程创建点。逐消费方设置会遗漏其他调用方并重复平台策略。

**把 proxy header、HTML 改写或隧道作为修复位置。** 拒绝，因为这些路径可以促使会话执行工作，却不会创建本地 shell 进程；即使没有 proxy 或 tunnel listener，可见窗口也能复现。

**让每条命令都使用持久 terminal。** 拒绝，因为普通批处理执行拥有不同的所有权、输出、超时和拆卸语义。改用 PTY 会扩大行为，而不是修正窗口展示。

## Consequences

所有普通本地 subprocess 消费方都会继承 Windows 不闪窗行为，API 和输出处理保持不变。真正的交互式 terminal 仍由自身 ConPTY 展示负责；确实需要可见控制台的调用方必须使用不同的进程 provider，而不能依赖 Windows 的偶然默认行为。
