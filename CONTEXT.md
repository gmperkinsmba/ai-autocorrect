# Context

**First principle:** Fix typing and rewrite selected text locally without losing the user's meaning.

## Typing correction

AI Autocorrect watches Accessibility value-change notifications for supported editable fields. It reads the current field only after rejecting secure, credential-labeled, unknown, and excluded controls. At a typed space or Return, it can replace one word through the selected-text range. It never captures keyboard events or submits text.

## User dictionary

The user can keep a word as written or add a one-word typo-to-replacement pair. User settings override the short built-in correction list. The user can pause typing correction at any time.

## Undo

One exact field snapshot and selection stay in memory after a correction. Undo restores them only while the field is unchanged. The snapshot is cleared after later edits or when the app quits. It is not written to disk.

## Humanizer

Selected or pasted text goes only to a user-configured loopback OpenAI-compatible API after an explicit rewrite action. The app caps request and response sizes, rejects redirects, and requires protected names, numbers, dates, quotes, URLs, and code to remain in the result. A failed check leaves the original editable.

## Surface limits

Accessibility support differs across apps. Secure, password, credential-labeled, unknown, excluded, URL, and code contexts are skipped. AI Autocorrect is a native Mac menu bar app. There is no browser or server mode. The owner-only settings file lives at `~/Library/Application Support/AI Autocorrect/settings.json`. It stores preferences and user dictionary entries, not typed text, selections, model output, or logs.
