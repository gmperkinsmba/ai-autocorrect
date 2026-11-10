# AI Autocorrect

Mac menu bar app that fixes supported typos as you type and, on Rewrite, sends selected or pasted text only to the loopback model API you configure.

## Run

```sh
python3 build_app.py
python3 install_app.py
```

## Test

```sh
swift run -Xswiftc -enable-testing AIAutocorrectChecks
swift build --target AIAutocorrect
```

Run the tests before committing. There is no separate lint step.

## Layout

- Core code: `Package.swift`, `Sources/`
- Mac app wrapper, build and install: `build_app.py`, `install_app.py`
- Installer and runtime safety checks: `install_security.py`
- Tests: `tests/`
- Docs: `CONTEXT.md`, `LICENSE`, `README.md`, `SECURITY.md`, `third_party_licenses/`

## Conventions

- `README.md` describes behaviour and limits; `CONTEXT.md` holds the domain terms and rules. Keep both in step with code changes.
- Read `SECURITY.md` before changing request handling, file access, or the installer.
- Demo data, fixtures and examples are made up. Keep them that way.
- Never commit secrets, keys, tokens, or runtime data.
- A behaviour change comes with a test.
