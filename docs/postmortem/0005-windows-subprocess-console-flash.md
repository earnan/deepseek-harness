# Post-mortem 0005: Windows subprocess consoles flashed from the no-console Web host

English | [中文](0005-windows-subprocess-console-flash.zh.md)

Status: field verification pending

## Executive summary

Short Bash and PowerShell tool calls opened transient console windows on a user's Windows desktop even though the Web host itself ran without a console. Proxy and tunnel activity triggered work but did not create the window. The shared ordinary-subprocess provider now requests `windowsHide` on Windows, but a later flash during active DSH work means source inspection alone cannot establish that every real execution path uses that provider. DSH presets now pin `custom-bash` to the system Git Bash instead of resolving WorkBuddy's bundled PortableGit from inherited `PATH`; this isolates executable provenance but does not itself prove that no console can be created. Field acceptance remains pending.

## Summary

The Web launcher correctly starts its Node.js host with no visible console. That property does not propagate to later console-subsystem children. The shared `@deepseek-ai/dsh-subprocess-local` ordinary spawn path explicitly sets Node's `windowsHide` option on Windows, but a visible flash can still come from an alternate or nested process-creation path. A short-lived window whose title names Bash identifies the executable, not the precise call site that created its console.

Proxy requests, browser activity, and tunnels can cause a session to run a tool, but they do not create the local process window. The flash persisted with proxy and tunnel listeners stopped. High-frequency sampling connected the Web host to Bash and `conhost.exe`, while a captured title identified WorkBuddy's PortableGit Bash executable. That path was selected by DSH's `custom-bash` resolution from inherited `PATH`, so preset configuration could couple DSH execution to WorkBuddy's bundled Git without proving that WorkBuddy itself created the window.

## Impact

Users could see intermittent console windows while the Web application executed ordinary local tools. The commands still completed and their output remained correct, but the flashes disrupted desktop use and made the GUI appear unstable. No data loss, privilege change, or command-execution expansion occurred.

The initial correlation with proxy and tunnel activity prolonged diagnosis and could have led to a fix in a layer that did not own Windows process creation. Diagnostic sessions that launched their own Bash and PowerShell children also produced similar process noise.

## Timeline

- The Web manager launched the application with hidden-window process options, while the shared ordinary-subprocess provider needed an explicit Windows child-window policy.
- Users observed recurring flashes and first investigated LAN proxy rewriting, browser requests, and SSH tunnel activity.
- The issue reproduced after all proxy and tunnel listeners were stopped, disproving them as necessary conditions.
- A captured title identified WorkBuddy's PortableGit `bash.exe`; high-frequency sampling then observed `Web node.exe -> bash.exe -> conhost.exe` and equivalent PowerShell chains.
- Source inspection established that `spawnSubprocess()` now sets `windowsHide: true` for its Windows path; the Liangshen preset disables PTY use on Windows and calls the ordinary subprocess service for `custom-bash`.
- The user later observed another flash while using DSH, so the static ordinary-spawn policy did not establish coverage of the observed runtime path.
- All discovered preset files with `custom-bash` use `C:\Program Files\Git\bin\bash.exe`, preventing inherited `PATH` order from selecting WorkBuddy PortableGit.
- The repair launcher initially passed the DSH JavaScript entrypoint without preserving its spaces, causing Node to report `Cannot find module 'D:\\Program'`; the launcher now quotes that entrypoint before starting DSH.

## Root cause

The original defect was treating a hidden host window as sufficient for a no-flash application. On Windows, window allocation is also a child-process creation decision. Piped stdio, a detached-process setting, and a hidden parent do not independently require an ordinary console-subsystem child to remain invisible.

The ownership model was blurred during diagnosis. Network and browser components owned when work was requested, while `@deepseek-ai/dsh-subprocess-local` owned how the executable was created. Temporal correlation directed attention toward the trigger layer instead of the process-creation layer.

The ordinary-spawn unit suite now asserts the Windows window option, but it can only establish the options handed to that provider. It cannot prove that a nested shell, a dependency, or another process provider did not create the observed window. Operational observation needs a positive trigger: an interval with no flash and no spawned shell cannot prove the defect fixed.

## Guardrails added

- [`spawnSubprocess()`](../../packages/subprocess/subprocess-local/src/spawn.ts) sets `windowsHide: true` when its effective platform is `win32`; POSIX behavior and caller-selected stdio remain unchanged.
- [`spawn.spec.ts`](../../packages/subprocess/subprocess-local/tests/spawn.spec.ts) injects a recording spawner and pins `true` for the Windows platform path and `false` for the POSIX path while a real child executes.
- The [`subprocess-local` README](../../packages/subprocess/subprocess-local/README.md) states that ordinary Windows children hide their console without changing stdio dispositions.
- The [implemented Agent Note](../../.agents/notes/implemented/bug-fix/2026-08-24-hide-windows-ordinary-subprocess-consoles.md) owns the process-creation decision, the rejected proxy- and consumer-level alternatives, and the distinction between ordinary subprocesses and ConPTY terminals.
- The repair launcher applies an explicit system Git Bash path to every discovered `custom-bash` preset, backs up every target, verifies the replacement, and starts DSH with a quoted JavaScript entrypoint. Its backup directory retains the launch logs.
- Windows field acceptance starts the actual Web host without a console, invokes a real Bash tool call, verifies its output and exit, samples the complete DSH descendant chain, and requires that the invoked Bash path is the configured system Git path and that no target child has a visible main window.

## Lessons

- A hidden GUI host does not imply hidden console-subsystem children; every ordinary Windows process-creation boundary needs an explicit window policy.
- The component that triggers work is not necessarily the component that creates the visible operating-system resource. Window titles, parent-child process evidence, and source ownership must agree before assigning cause.
- Short-lived process defects require high-frequency observation. Diagnostic tools must be separated by process ancestry because they can manufacture the same Bash, PowerShell, and `conhost.exe` noise.
- An explicit executable path isolates provenance but does not suppress windows. The real entry path must create the target child while functional output, descendant ancestry, executable path, and window state are observed together.
