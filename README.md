# SloppyType

**First principle:** Help writers fix common typos. Keep control of their wording in their hands.

SloppyType checks text in its own editor. It fixes a small set of common typos at word boundaries. It remembers words you want to keep. You can undo the last correction and restore the original text and cursor.

## Run

Requires Python 3.10 or newer. No packages are needed.

```sh
python3 server.py
```

Open `http://127.0.0.1:8351`. The server listens on loopback only. Stop it with Ctrl+C.

## Use

Type in the SloppyType editor. A known typo is corrected when you press space or Enter. You can also press **Correct draft** to check the full text. **Undo correction** restores the exact previous text and cursor. If you keep typing after a correction, undo turns off so it cannot remove new text.

Add words to keep them as written. Add an exception to protect a term that matches a supported typo. Add a custom correction as a one-word typo and replacement pair. Choose the entries to include before you export the dictionary.

Settings can pause correction in the editor. The password input is a mock test surface and has no correction handler. The excluded app choice is also a test mode. The app does not read other fields, apps, or system text. This version is not an operating system typing hook.

## Data and privacy

Your dictionary and pause setting are stored locally outside this folder in `~/.local/share/sloppytype/`. The folder is owner-only. Data is not encrypted. Remove that folder to clear local data. Text is not sent to a service.

The built-in corrections are a short original demo list: `teh`, `recieve`, `seperate`, `adress`, and `occured`. They are not a bundled third-party dictionary.

## Test

```sh
python3 -m unittest discover -s tests -v
```

Tests check typo fixes, exact undo data, dictionary exceptions, and export selection. They also check pause behavior, sensitive mock surfaces, invalid requests, missing request tokens, invalid origins, and payload limits.

## Limits

SloppyType supports only its own browser editor. It does not run in other apps or read password fields. This demo does not validate market fit or user outcomes.

## License

MIT. See `LICENSE`.
