# Contributing

Use Swift 6.3 / Xcode 26.6 and keep the v1 protocol surface manually modelled:
unknown fields, event types, statuses, and error codes must survive decoding.
Run `swift build` and `(cd Packages/PiqoKit && swift test)` before proposing a
change. Do not modify `piqo-server` from this repository, read `piqo.db`, add
telemetry, or log tokens/provider keys/prompts/responses.

When updating the bundled helper, update `Sidecar.lock.json`, verify its SHA-256
and API/protocol version, then exercise the integration suite with a temporary
HOME and fake local provider.
