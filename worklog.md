# Worklog: Fix Whisper model reload freeze

## Problem

After a few minutes of idle, pressing the hotkey to activate VoiceInk would freeze the UI for 30-60 seconds (spinning cursor, unresponsive). Consecutive rapid uses worked fine. The app was never closed between uses.

## Root Cause

`cleanupModelResources()` was called after **every single use** (transcription complete, cancel, dismiss), which set `whisperContext = nil` and called `whisper_free()`. On next activation, the model had to be reloaded from disk via `whisper_init_from_file_with_params()` — a synchronous C call running on `@MainActor`, blocking the main thread entirely.

When the model file data was still in the OS filesystem page cache (right after use), the reload was fast. After a few minutes idle, macOS reclaimed those cached pages (especially under memory pressure from other apps like ML Studio), causing a full disk read of the model file (hundreds of MB), taking 30-60 seconds.

## Changes

### 1. Idle timer instead of immediate cleanup (`WhisperState+ModelManager.swift`)

- Added `scheduleModelCleanup()`: starts a 20-minute idle timer; only releases the model if unused for 20 minutes
- Added `cancelModelCleanup()`: cancels the timer when recording starts
- `cleanupModelResources()` itself unchanged — still used by Power Mode model switching

### 2. Replaced all immediate cleanup calls

**`WhisperState.swift`** — 4 call sites changed from `await cleanupModelResources()` to `scheduleModelCleanup()`:
- After transcription cancelled in toggleRecord (line ~167)
- After transcription cancelled in transcribeAudio (line ~299)
- After transcription succeeded (line ~501)
- After transcription failed (line ~512)

Removed the `defer { cleanupModelResources() }` block in `transcribeAudio` (no longer needed).

Added `cancelModelCleanup()` at the start of the recording branch in `toggleRecord()` to prevent the timer from firing during an active recording session.

**`WhisperState+UI.swift`** — 1 call site changed:
- `dismissMiniRecorder()`: `await cleanupModelResources()` → `scheduleModelCleanup()`

### 3. Model loading moved off main thread (`LibWhisper.swift`)

Rewrote `WhisperContext.createContext(path:)` to run `whisper_init_from_file_with_params()` inside `Task.detached(priority: .userInitiated)`. The heavy C call now executes on a background thread; only the lightweight `WhisperContext` wrapper creation happens on `@MainActor`. This means even the first load after app launch (or after the 20-min timer fires) will **not** freeze the UI.

Removed the now-unused `initializeModel(path:)` private method.

### 4. Diagnostic timing logs

Added `CFAbsoluteTimeGetCurrent()` timing to:
- `WhisperContext.createContext()` — logs model load duration
- `loadModel()` in `WhisperState+ModelManager.swift` — logs total load time
- `toggleRecord()` in `WhisperState.swift` — logs audio engine start time and full recording sequence time

All logs use `Logger.notice` level. To view after a freeze:
```sh
log show --predicate 'processImagePath CONTAINS "VoiceInk"' --last 5m | grep -E "⏳|✅|❌"
```

### 5. New property (`WhisperState.swift`)

- Added `var modelCleanupTimer: Timer?` to `WhisperState`

## Files Modified

| File | What changed |
|------|-------------|
| `VoiceInk/Whisper/LibWhisper.swift` | Model loading moved to background thread + timing logs |
| `VoiceInk/Whisper/WhisperState+ModelManager.swift` | Added timer-based cleanup + timing logs in loadModel |
| `VoiceInk/Whisper/WhisperState.swift` | Replaced 4x cleanup calls with timer, added timing logs, added timer property |
| `VoiceInk/Whisper/WhisperState+UI.swift` | Replaced 1x cleanup call with timer |

## Not Modified

- `VoiceInk/PowerMode/ActiveWindowService.swift` — keeps direct `cleanupModelResources()` calls (correct: switching models requires immediate cleanup)

## Thinking Process

### How we found the root cause

1. User reported: hotkey activation freezes for 30-60s after idle, works fine on rapid consecutive use, no app restart involved.

2. The "works after rapid reuse, fails after idle" pattern pointed to something being released and needing re-initialization. The idle duration (5-10 min) matched OS page cache eviction timing.

3. Traced the hotkey flow: `HotkeyManager.handleShortcutTriggered()` → `WhisperState.handleToggleMiniRecorder()` → `toggleMiniRecorder()` → `toggleRecord()`.

4. Found `cleanupModelResources()` called at the end of every use path (5 call sites), which sets `whisperContext = nil` and calls `whisper_free()`.

5. Found `whisper_init_from_file_with_params()` (a heavy synchronous C function) runs on `@MainActor` — blocking the main thread during reload.

6. Connected the dots: every use releases the model → next use reloads from disk → OS page cache determines speed → idle evicts cache → freeze.

### User's insight about ML Studio

User pointed out this issue appeared after installing ML Studio (which consumes significant memory). This accelerates the OS page cache eviction — with less free memory, macOS reclaims cached file pages faster, shortening the window where rapid reuse is fast. This was the **triggering condition**, but the underlying design (release-after-every-use) was always suboptimal.

### Why not just "never release"?

User suggested a 20-minute idle timer rather than never releasing. Reasoning: the model can be hundreds of MB in memory. If the user stops using VoiceInk for a while, that memory should be freed. The 20-minute window covers typical active usage sessions while still being a good citizen on memory.

## Trade-offs

### Memory vs. responsiveness

- **Before**: ~0 MB idle memory for whisper model, but 30-60s freeze on every activation after idle.
- **After**: Model stays resident (~150-800 MB depending on model size) for up to 20 minutes after last use, but activation is always instant.
- The 20-minute timer is a compromise. Could be made configurable in settings if users on low-memory machines need shorter retention.

### Background thread model loading

- **Pro**: Even when the model DOES need to reload (first launch, after 20-min timer), the UI stays responsive. User can cancel, interact, etc.
- **Con**: There's a brief period where recording has started but the model isn't loaded yet. If the user records and stops very quickly (< model load time), the transcription will await the load — but the UI won't freeze, it'll just show the processing state.
- **Thread safety**: whisper.cpp requires single-threaded access to a context. We only use `Task.detached` for *creating* a new context (no shared state). Once created, all access goes through `@MainActor` as before. This is safe.

### Keeping `cleanupModelResources()` for Power Mode

Power Mode can switch transcription models mid-session. When switching from model A to model B, the old context MUST be released immediately (not after 20 min) to free memory before loading the new model. So `ActiveWindowService.swift` keeps the direct `cleanupModelResources()` calls.

### External scripts sharing the model file

User was concerned that keeping the model in memory would prevent other local scripts from using the same whisper model file. This is not an issue — whisper model files are read-only, and multiple processes can independently load the same file. The only cost is doubled memory usage when both are active simultaneously.
