# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] - 2026-07-13

### Fixed

- Errors & Stack Traces: the 1.0.4 fix for own-frame noise in captured traces used a text-based
  strip that kept removing lines for as long as they matched (mentioned `ErrorCatcher.lua`, or
  were the literal `[C]: ?` dispatch stub). That's too broad: a genuine bug spanning several of
  this module's own internal calls in a row could have real diagnostic frames swallowed right
  along with the constant noise. Replaced it with `debugstack()`'s own `start` parameter, which
  skips an exact frame count by position instead of by matching text - it only ever removes the
  one guaranteed-noise frame (this module's own handler), so a real bug anywhere else - including
  deeper inside this module's own code - now always shows in full.

## [1.0.4] - 2026-07-13

### Fixed

- Errors & Stack Traces: `debugstack()` was being called from *inside* the error-handler and
  SetText hook functions themselves, so every captured trace led with that hook's own frame (and,
  for the error-handler path, an opaque `[C]: ?` dispatch stub above it) - noise unrelated to the
  actual error that pushed the real, useful frames down and could read as if this addon itself
  were implicated. Those leading frames are now stripped before the trace is stored/displayed.

## [1.0.3] - 2026-07-13

### Fixed

- Errors & Stack Traces: the "Okay" button's text was hardcoded to a reddish tint, which read as
  barely-legible red-on-red against the frame's dark red skin. It now uses the same default text
  color as every other button on the window (Prev/Next/Clear/First/Last), and is slightly larger.

## [1.0.2] - 2026-07-13

### Fixed

- Errors & Stack Traces: `seterrorhandler` is a single global slot, not a chain, so whichever
  addon calls it *last* wins for the rest of the session. Tweak addons that install a "hide Lua
  errors" style handler after this module's own `ADDON_LOADED`-time install (e.g. ShaguTweaks'
  "Hide Errors" mod, which replaces the global `error` with a no-op and re-asserts it via
  `seterrorhandler`) silently swallowed every error from that point on, with no indication
  anything had changed. The catcher's handler is now a named, comparable function so it can
  detect via `geterrorhandler()` whether something else has taken the slot, and reclaims it:
  once at install, again at `PLAYER_LOGIN` (deterministically after every other addon's own
  `ADDON_LOADED`/`VARIABLES_LOADED`-time setup has run - covers both normal login and any
  in-session settings toggle that triggers a `ReloadUI()`), and periodically via a lightweight
  watchdog as a backstop against anything reasserted later still. A chat message now announces
  when a reclaim actually happens, so this kind of interference is visible instead of silent.

## [1.0.1] - 2026-07-11

### Fixed
- The background-opacity slider never actually persisted: its initial value-sync ran at file-load
  time, before `ADDON_LOADED`/before SavedVariables are injected, so it could only ever read the
  hardcoded 0.5 default there - and since `Slider:SetValue()` re-fires `OnValueChanged`, that sync
  was also *writing* 0.5 straight back into `TeronDebugToolsDB` every load, permanently
  overwriting whatever the user had actually set before it ever got a chance to load. The sync now
  happens when the Control Panel's Modules tab is actually shown instead, always well after the
  real saved value is available.

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
