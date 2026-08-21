# Piqo Desktop Beta

Piqo is a native macOS 26 (Apple Silicon) desktop client for the fixed
[`piqo-server` client protocol v1](https://github.com/piqo-harness/piqo-server/blob/main/docs/CLIENT_PROTOCOL.md).
It provides streamed text conversations, provider/model selection, multiple
windows, event inspection, safe local configuration editing, and reconnecting
SSE streams. It is deliberately a beta: tools, permission approvals, tool
results, attachments, and sub-agents are shown as blocked rather than executed.

## Development

Requirements: Xcode 26.6, macOS 26, and Apple Silicon. The root Swift package
is a fast development build; `Piqo.xcodeproj` is the distributable application
project.

```sh
swift build
(cd Packages/PiqoKit && swift test)
```

Place the verified `piqo-server` release binary in
`Piqo.app/Contents/Helpers/piqo-server` when archiving. During development,
`PIQO_SIDECAR_PATH=/absolute/path/to/piqo-server` overrides that location.

See [the English guide](docs/USER_GUIDE.en.md),
[le guide français](docs/USER_GUIDE.fr.md), and [contributing](CONTRIBUTING.md).

## Security model

Piqo runs a local, signed helper and only accepts its loopback origin. Its
bearer token stays in memory. Provider keys intentionally remain in clear text
in `~/.config/piqo/piqo.toml`, as specified by the product; do not put that file
in source control. Diagnostics and default exports redact secrets and omit
prompts/responses.

MIT licensed; see [LICENSE](LICENSE). Third-party notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
