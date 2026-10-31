# Security

AI Autocorrect sends text to a supported local model endpoint. Its client uses a temporary session. It disables proxy settings and rejects redirects. It accepts loopback addresses only. It limits requests and responses. The settings folder and file use owner-only permissions. The app stores no API key. Model behavior depends on the local endpoint you set. Treat sent text as private. Send only what you need. Do not put private writing in a report.

Use your Mac’s disk encryption to protect saved files. The native app has an ad-hoc code signature. This lets the installer check whether its files changed. It does not prove who made the app. The build is not notarized. Settings are plaintext protected by account permissions. The configured local endpoint receives the text you send.

Report security issues through [GitHub private vulnerability reporting](https://github.com/gmperkinsmba/ai-autocorrect/security/advisories/new).
