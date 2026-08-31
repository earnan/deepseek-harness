# Agent Note: Hide Windows ordinary-subprocess consoles

Status: implemented

English | [中文](2026-08-24-hide-windows-ordinary-subprocess-consoles.zh.md)

## Problem

The Web and other GUI or background launchers can run without an attached Windows console. When the local subprocess provider starts a console-subsystem executable from such a host without requesting a hidden window, Windows may allocate a visible console. Short Bash and PowerShell tool calls then appear as transient windows even though their stdio is piped and the caller does not request an interactive terminal.

This behavior belongs to ordinary process creation in `@deepseek-ai/dsh-subprocess-local`. Proxy traffic, browser requests, and individual shell consumers can trigger a command, but none owns the Windows process window.

## Decision

`spawnSubprocess()` sets Node's `windowsHide` spawn option exactly when its effective platform is `win32`. The provider continues to use the caller's explicit stdin, stdout, and stderr dispositions and keeps Windows process-tree termination through `taskkill /T /F`. POSIX children keep their existing detached process groups and do not request window hiding.

Terminal sessions remain separate. `spawnTerminal()` continues to use `node-pty` and ConPTY because an interactive terminal requires a pseudoconsole rather than an ordinary hidden child process.

## Verification

The ordinary-spawn unit suite injects a recording spawner and pins `windowsHide: true` for the Windows platform path and `false` for the POSIX path while executing a real child. Windows field verification starts the Web host without a console, executes short Bash and PowerShell tool calls, and observes no visible shell window while output and exit status still reach the tool result.

## Alternatives considered

**Hide windows in each launcher or shell consumer.** Rejected because the Web launcher controls only the host window, while Bash, PowerShell, LSP, MCP, and future consumers all reach the same ordinary-process creation point. Per-consumer flags would leave alternate callers exposed and duplicate platform policy.

**Treat proxy headers, HTML rewriting, or tunnels as the fix site.** Rejected because those paths can cause a session to execute work but never create the local shell process. The visible window also reproduces without proxy or tunnel listeners.

**Use a persistent terminal for every command.** Rejected because ordinary batch execution has different ownership, output, timeout, and teardown semantics. Replacing it with a PTY would expand behavior instead of correcting window presentation.

## Consequences

All ordinary local subprocess consumers inherit the Windows no-flash behavior without changing their APIs or output handling. A deliberately interactive terminal still owns its ConPTY presentation, and a caller that genuinely needs a visible console must use a different process provider rather than relying on an accidental Windows default.
