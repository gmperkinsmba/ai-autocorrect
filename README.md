# AI Autocorrect

**First principle:** Fix typing and rewrite selected text locally without losing the user's meaning.

AI Autocorrect is a Mac menu bar app. It fixes supported typos as you type. When you choose Rewrite, it sends selected or pasted text only to the loopback model API you configure.

## Install and run

Build on a Mac with Swift 5.10 or newer and the macOS SDK:

```sh
python3 build_app.py
python3 install_app.py
```

Open **AI Autocorrect** from Finder or add it to the Dock. The app runs in the menu bar. Choose **Quit AI Autocorrect** to close it. The build is ad-hoc signed and is not notarized. If macOS blocks the first launch, Control-click the app, choose **Open**, and confirm.

To uninstall, move `~/Applications/AI Autocorrect.app` to the Trash. Your settings are in `~/Library/Application Support/AI Autocorrect/settings.json`. Remove that folder only if you also want to remove your local word list and preferences.

## Use

Turn on **Typing correction** and allow Accessibility access in System Settings. Corrections run at a space or Return in supported text fields. AI Autocorrect uses macOS spelling suggestions, a short built-in list, and your own corrections. Add words to keep in Settings. Pause corrections from the menu at any time.

Undo restores the last full field snapshot and selection only while the field still matches. The one undo copy stays in memory until the next edit or quit. It is never saved.

Use the menu to humanize selected or pasted text. Use a local model server that accepts requests in the OpenAI format. Enter its API URL and model name in the rewrite window. Choose **Test connection** or **Find models**. The default URL is `http://127.0.0.1:1234/v1`. The app contacts only a loopback address. It does not start a model server, use cloud keys, or follow redirects. Rewriting sends only the text you submit to that local API.

To rewrite a selection, select text in a supported app and press **Command+Shift+H**. This is the default shortcut. Change it under **Settings > Humanize shortcut**, then choose **Save settings**. If another app owns the shortcut, AI Autocorrect reports that it is unavailable.

Start the local OpenAI-compatible model server you choose. In the rewrite window, enter its local API URL and model name. Choose **Test connection** or **Find models** to check the setup. This client needs no cloud account or API key.

The rewrite prompt keeps names, numbers, dates, quotes, URLs, and code. If the model changes protected text, the rewrite is refused and the original stays editable. The optional tiny typo is on by default. It can remove one space from ordinary prose for about every 250 words. Review the result before using it.

The AI-style percentage is a rule-based signal. It shows which patterns matched. It is not a probability, and it cannot tell who wrote the text.

Choose **Check writing** to score the pasted text on this Mac without sending it to a model or changing it. The check shows its percentage, matched patterns, and the same authorship limit.

## Accessibility behavior

Typing correction reads accessible field text only after checking the field role and app. Secure, password, credential-labeled, excluded, unknown, URL, and code contexts are skipped. Accessibility support varies by app. If a field does not allow a safe selection edit, the app leaves it unchanged.

## Privacy and limits

The app does not use a key event tap, save typed text, or log it.

The settings file is stored outside this folder with owner-only permissions. It contains preferences and user word entries, not text. Humanizing uses the local endpoint you choose. The app does not inspect or control that endpoint's storage behavior.

AI Autocorrect is packaged for macOS only. Source compatibility on other systems is untested. No Linux or Unix build is provided.

## Development

Run the native behavior checks and compile the app:

```sh
swift run -Xswiftc -enable-testing AIAutocorrectChecks
swift build --target AIAutocorrect
```

The app has no browser mode or manual server launch path.

## License

MIT. See `LICENSE`.
