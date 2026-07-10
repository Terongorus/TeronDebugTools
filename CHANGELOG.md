# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-10

### Added

- Initial release: a modular debugging & diagnostics toolkit consolidating six previously
  separate addons into one control panel with load-on-demand modules.
- Core: shared namespace, module registry, minimap button (with an unread-error badge and a
  recent-errors tooltip preview), unified control panel with dynamically-added per-module tabs.
- Errors & Stack Traces module: Lua error/exception capture with stack traces, automatic popup
  on new errors (toggleable), sound alert, live refresh of an already-open window, colorized
  file/line and quoted-identifier references, a manual test-error trigger, and a BugSack-style
  layout (Prev/Next left, Okay centered, First/Last right). Right-click the minimap button to
  jump straight to the latest error. Error history is cleared on every login/reload rather than
  accumulating across sessions.
- Debug Log module: persistent per-label log store with a public logging API for other modules
  and addons to write through.
- Variable Watcher module: one-off expression inspection plus a persistent, optionally
  live-updating watch list.
- Resource Monitor module: lightweight memory/garbage-collection widget, clamped to the screen.
- Performance Profiler module: on-demand frame `OnEvent`/`OnUpdate` handler profiler with full
  unhook support.
- Save Reminder module (bonus, off by default): periodic/triggered chat-command automation for
  private servers with a custom save handler. The command is configurable (`.save` by default,
  editable, clearable to disable) rather than hardcoded, since it's server-specific and not every
  server implements the same one.
- Shared background-opacity slider (0.1-1.0, default 0.5) in the control panel, applying live to
  every window in the toolkit at once.
- All dialog-style windows use a flat, thin-bordered backdrop (matching Resource Monitor's
  existing style) instead of the ornate Blizzard dialog-box skin, so the opacity slider actually
  has a visible effect and the whole toolkit reads as one consistent design.
