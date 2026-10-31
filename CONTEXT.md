# Context

## Writer

A person typing text in the SloppyType editor.

## Correction

A deterministic replacement of one supported typo at a word boundary. The app stores the exact text and selection before a correction so undo can restore both.

## Dictionary entry

A user-owned word to keep as written, an exception that suppresses a built-in typo, or a custom typo-to-replacement pair. Export includes only entries the user selects.

## Surface

The built-in editor is the only supported surface. Password and excluded-app options are mock test contexts. No OS or other-app interception exists.

## Local store

SQLite holds user entries and the pause setting under the user's local data folder. No text or entries leave the device.
