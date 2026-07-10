# Teron's Debug Tools

A modular debugging & diagnostics toolkit for WoW Vanilla / Classic 1.12.1. One control panel,
one minimap button, six independently load-on-demand modules - enable only what you need, and a
disabled module never even gets loaded into memory.

## Modules

| Module | What it does | Default | Slash command |
|---|---|---|---|
| **Errors & Stack Traces** | Catches Lua errors and stack traces. Pops up automatically on a new error by default (toggleable), plays a sound, colorizes file/line references, and keeps refreshing live if you already have it open. Cleared fresh every login/reload - never shows stale errors from a previous session. | On | `/tdterrors` |
| **Debug Log** | A persistent, per-label log that other tools - and your own addons - can write to via `TeronDebugTools:Log(label, msg)`. | On | `/tdtlog [label]` |
| **Variable Watcher** | Inspect any Lua expression on demand, or keep a persistent watch list that refreshes manually or live (throttled, not per-frame). | On | `/tdtwatch [expr]` |
| **Resource Monitor** | A small always-on widget showing current/max/rate Lua memory and time since the last garbage-collection cleanup. Clamped to the screen. | On | - |
| **Performance Profiler** | On-demand profiler: hooks frame `OnEvent`/`OnUpdate` handlers and ranks them by count/time/memory. Heavier - fully unhooks itself when you click Stop Profiling. | Off | `/tdtprofiler` |
| **Save Reminder** *(bonus)* | Not a debugging tool. Sends a configurable chat command (`.save` by default, editable - clear it to disable entirely if your server has no equivalent, e.g. Kronos) periodically or on trigger events. | Off | - |

Open the control panel with the minimap button (left-click) or `/tdt` to enable/disable modules
and configure each one - including a shared background-opacity slider (0.1-1.0) that applies to
every window at once. Right-click the minimap button to jump straight to the latest error, and
hover it for a preview of recent errors with occurrence counts. Enabling a module loads it
immediately if possible; disabling one takes effect after your next `/reload`, same as any other
addon.

## Installation

Copy every `TeronDebugTools*` folder from this repository into your `Interface/AddOns/` directory
(they're siblings, not nested inside each other - that's how WoW's load-on-demand addon detection
works).

## Credits

This toolkit consolidates ideas from six standalone addons the WoW Vanilla community has relied on
for years. Every module here is a clean-room reimplementation - the functional concepts and public
API contracts are drawn from these projects, but no source code was copied, which is what let this
toolkit adopt a single unified license (GPL-3.0) instead of trying to reconcile the sources'
several different licenses (GPL-3.0, CC-BY-NC-SA-2.5, MIT, and two with no license at all). Thanks
to the original authors:

- **!AutoSave** by Platine - inspired Save Reminder
- **BugGrabber** by Fritti, Rabbit (credits: Rowne, Ramble, kergoth, ckknight) - inspired the Errors & Stack Traces capture backend
- **BugSack** by Fritti, Rabbit (credits: Rowne, Ramble, Gamefaq, thomasmo, damjau, kergoth) - inspired the Errors & Stack Traces display
- **Tracer** by Steve Kehlet - inspired Debug Log
- **TurtleDebug** by Francis Egan - inspired Variable Watcher
- **pfDebug** by Shagu - inspired Resource Monitor and Performance Profiler

## License

GPL-3.0. See [LICENSE](LICENSE).
