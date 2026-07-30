# Antigravity Saturn

A lightweight Windows desktop Saturn driven by Google Antigravity 2.0 hooks and a lifecycle-managed plugin sidecar.

## What it does

- Antigravity hooks write privacy-safe state events to `~/.gemini/antigravity-saturn/events/`.
- The resident sidecar renders Saturn as a 148 px topmost, non-activating window.
- Active states show one compact privacy-safe card: `Antigravity CLI · Working/Done/Needs attention`.
- Every hook tags its own Windows Terminal session with a Saturn-specific title derived from a short hash of `WT_SESSION`. A stationary left click searches every Terminal window for that exact marker, selects the remembered tab, then restores and focuses its owning window. A missing or ambiguous marker fails honestly instead of activating another agent's terminal. A native Antigravity desktop-process window remains the non-Terminal fallback.
- A deliberate drag moves Saturn and remembers its independent position.
- Double-click Saturn, double-click the card, click the card's `x`, or use **Show status card** in the right-click menu to collapse/restore cards. The choice is remembered.
- A failed focus attempt gives honest shake feedback instead of activating an unrelated window.
- The resident uses its own mutex, PID file, position file, data root, and event namespace, so it does not share Claude Moon state.

## Install

Requires Windows, Antigravity 2.0, Node.js, and built-in Windows PowerShell (`powershell.exe`). PowerShell 7 (`pwsh`) is not required.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
```

The installer copies only runtime files to `~/.gemini/config/plugins/antigravity-saturn/`, enables the `antigravity-saturn/saturn-resident` sidecar in `~/.gemini/config/config.json`, and backs up an existing config as `config.json.saturn-backup`. Restart Antigravity if it does not discover the plugin immediately.

Antigravity sidecars are disabled until explicitly enabled; the installer performs that opt-in. See the official [plugin](https://www.antigravity.google/docs/plugins), [hook](https://www.antigravity.google/docs/hooks), and [sidecar](https://www.antigravity.google/docs/sidecars) documentation.

Terminal targeting follows Microsoft's documentation for [shell-controlled tab titles](https://learn.microsoft.com/windows/terminal/tutorials/tab-title) and Windows Terminal's per-session [`WT_SESSION` marker](https://learn.microsoft.com/windows/terminal/tutorials/new-tab-same-directory).

## Event mapping

| Antigravity event | Saturn state | Notes |
| --- | --- | --- |
| `PreInvocation` | working | model invocation began |
| `PostInvocation` | working | the execution loop may continue |
| `PreToolUse` | working | adapter always returns `allow`; it never gates tools |
| `PostToolUse` | working | tool completed successfully |
| `PostToolUse` with `error` | attention | reliable error evidence; uses the working frame plus motion |
| `Stop` with `fullyIdle: false` | working | background work still exists |
| idle `Stop` | done | done expression lasts ten seconds, then returns to idle |
| errored `Stop` | attention | reliable execution-error evidence |

There is no documented universal “waiting for user” event. Saturn does not scrape the UI or guess. `attention` is reserved for explicit hook errors.

## Privacy and storage

The adapter deliberately does not persist prompts, tool arguments, transcript paths, artifact paths, workspace paths, raw conversation IDs, or observed tab titles. It stores only the hook name, normalized state/reason, selected numeric counters, workspace count, local process IDs used for terminal focusing, timestamps, a short SHA-256 conversation key, and a ten-character hash of Windows Terminal's per-tab `WT_SESSION` identifier. State writes are atomic unique-file renames. The event directory is capped opportunistically at 500 files and pruned back to 400.

## Uninstall

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1
```

Runtime data is retained by default. Add `-RemoveData` to remove `~/.gemini/antigravity-saturn/` too. Restart Antigravity if the lifecycle manager has not yet stopped the resident.

## Verify

```powershell
node tests\hook-adapter.test.js
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verify-package.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\install-roundtrip.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\measure-coexistence.ps1 -Seconds 30
```

`tests/verify-package.ps1` checks the native plugin schema, unique coexistence identifiers, 360×360 alpha assets, and a non-GUI resident smoke path.
