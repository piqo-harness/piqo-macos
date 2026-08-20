# Piqo Desktop Beta — user guide

Install the signed DMG by moving Piqo to Applications. On first launch, open
**Settings** and configure a provider in `~/.config/piqo/piqo.toml`. The provider
key is intentionally stored in clear text in that file. Restrict access to your
account and never share the file or diagnostic output without reviewing it.

Create a conversation, choose a local workspace, select provider and model, and
send the first prompt. The workspace is local metadata only in this beta; Piqo
does not grant the server filesystem access. A conversation may have several
runs. Runs can be cancelled, retried, and completed messages can be forked.

Piqo only talks to its embedded loopback sidecar and verifies the startup JSON,
process identity, API health, and SSE event ordering. If the sidecar cannot
start, settings and diagnostics remain available. Use the inspector to see raw
events and redacted stderr. Piqo cannot test provider credentials because v1 has
no provider-test endpoint.

Known v1 limits: no attachments, tools, interactive permissions, tool-result
submission, sub-agent control, remote daemons, session rename/archive/delete,
or direct `piqo.db` access. A `requires_action` or permission event is rendered
as blocked rather than pretending it can be resolved.
