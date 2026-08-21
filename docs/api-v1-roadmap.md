# macOS Roadmap — API v1

> Source of truth: OpenAPI schema served on August 20, 2026 at `http://127.0.0.1:8080/api/v1/openapi.json` (server version `0.1.0`).
>
> This document describes the client-side scope for the macOS application. It does not assume screens or technologies beyond what the API exposes.

## Contract constraints to address from the start

- Unless the server specifies otherwise in the future, every route is protected by a bearer token (`bearerAuth`, `base64url` format). The server owns authentication and authorization. If future remote access requires a client-held token, the application must store it securely and allow it to be replaced.
- Project and session lists use cursor pagination (`cursor`, `limit`); the UI must support incremental loading and an end-of-list state.
- Long-running generation operations are asynchronous: creating a run returns `202`, and its state and events are then retrieved separately.
- The real-time feed uses Server-Sent Events (SSE) and accepts `Last-Event-ID`. The client must be able to reconnect without losing events.
- Structured errors use `{ error: { code, message } }`. They must become useful recovery-oriented messages without exposing sensitive data.
- Provider secrets are write-only. After creation or update, the UI must never expect or attempt to display an API key; it shows only the credential type and, where applicable, the environment-variable name.

## Features to implement

| Area | Client features | API routes |
| --- | --- | --- |
| Connection and availability | Securely configure the server URL and bearer token; verify health and display the version; show offline and unavailable-server states. | `GET /health` |
| Projects | List with pagination, create, view, rename/update the path, delete with confirmation, and show associated sessions. | `GET/POST /projects`, `GET/PATCH/DELETE /projects/{project_id}`, `GET /projects/{project_id}/sessions` |
| Sessions | List all sessions or those in a project; create a session with optional title and project; open a session and display its metadata (phase, revision, projection, parent/fork). | `GET/POST /sessions`, `GET /sessions/{session_id}` |
| Activity log | Load history in batches (`after`, `limit`); render generic versioned events (`type`, `data`, `occurred_at`); retain the last seen event. | `GET /sessions/{session_id}/events` |
| Real time | Subscribe to the active session through SSE; apply events in order; resume after disconnect using `Last-Event-ID`; show connection and catch-up states. | `GET /sessions/{session_id}/events/stream` |
| Agent execution | Submit a run with required `input` and optional `agent`, `provider`, `model`, `variant`, and `body`; present acceptance, status, attempts, errors, and the resulting session projection. | `POST /sessions/{session_id}/runs`, `GET /sessions/{session_id}/runs/{run_id}` |
| Run controls | Cancel or retry a run, resume a blocked queue, and refresh state until resolution. | `POST /sessions/{session_id}/runs/{run_id}/cancel`, `POST /sessions/{session_id}/runs/{run_id}/retries`, `POST /sessions/{session_id}/queue/resume` |
| Session forks | Create a branch from a specific event, optionally naming it; show parent/child links and the fork point. | `POST /sessions/{session_id}/forks` |
| Agent catalog | Display configured agents, their descriptions, provider, model, and read/write/bash permissions (`allow`, `ask`, `deny`); offer them when submitting a run. | `GET /agents` |
| Providers | List, create, view, update, and delete providers; manage URL, protocol, timeout, headers, and credential method (`none`, API key, environment variable); show streaming capabilities. | `GET/POST /providers`, `GET/PATCH/DELETE /providers/{provider}` |
| Models | View a provider's catalog, replace its manual list, clear it, start discovery, and show its status/error/date. | `GET/PUT/DELETE /providers/{provider}/models`, `POST /providers/{provider}/models/refresh` |
| Configuration | Reload server configuration, then reflect its revision, load time, and the providers actually loaded. | `POST /config/reload` |

## Incremental milestones

### M0 — Communication foundation

Goal: make the application able to communicate with the server securely and reliably.

- Typed HTTP client for all public structures, error encoding/decoding, and bearer-token injection.
- Server connection settings, a minimal connection screen, and a `health` check. Use the macOS Keychain only if a future remote-access flow requires a secret held by the client.
- Loading, cancellation, non-sensitive logging infrastructure, and decoding unit tests.

**Exit criterion:** a user can configure a server, verify that it is reachable, and receive an actionable diagnostic on failure.

### M1 — Project and session navigation

Goal: let users create, organize, and retrieve their working context.

- Paginated project list and complete CRUD, including deletion confirmation and `409` conflict handling.
- Paginated global and project-specific session lists; session creation and opening.
- Detail screen showing title, phase, timestamps, revision, projection, and fork information where available.

**Exit criterion:** a user can create a project and session, find them after relaunching, and move between their views without ambiguous reloads.

### M2 — Execution and live monitoring

Goal: enable the primary workflow: send a request to an agent and follow its progress.

- Run-submission form with required `input` and optional agent, provider, and model selectors.
- Paginated event history and resilient rendering of unknown event types.
- SSE subscription, reconnection from the last received ID, REST catch-up, and run-state updates.
- Run inspection, cancellation, and queue resumption with explicit pending, failed, and successful states.

**Exit criterion:** after a network interruption or an application restart, an execution can be found again and its log reconstructed without visible duplicates.

### M3 — Operational configuration

Goal: allow provider administration and guided use of the available configuration.

- Agent and provider catalog screens with clear permission and streaming-capability display.
- Provider creation, update, and deletion; secure input of secrets and headers; precise handling of `400`, `409`, and `503` errors.
- Model-catalog management: manual editing, clearing, discovery, and discovery-status display.
- Configuration reload action and synchronization of displayed data.

**Exit criterion:** an administrator can configure a provider and its models without exposing a secret, then use it to start a run.

### M4 — Work continuity and resilience

Goal: complete advanced workflows and harden the product before broad release.

- Create branches from events and navigate between parents and children.
- Retry failed runs, with visibility into attempts and the `retry_of` relationship.
- Consistent handling of conflicts, deleted resources (`404`), an unavailable server (`503`), and validation failures (`400`/`422`).
- Schema-based integration tests, SSE reconnection tests, accessibility, empty states, and non-sensitive instrumentation.

**Exit criterion:** recovery workflows—cancellation, retry, forking, reconnection, and server errors—are tested end to end and do not leave the UI in an inconsistent state.

## Decisions to confirm before detailed design

- The exact contents of events and of `projection`, `request`, `input`, and `body` are intentionally untyped in the contract. An event catalog and real examples are needed before finalizing the conversational rendering.
- The possible `phase` and `status` values are not enumerated. The UI must tolerate unknown values, and an enriched contract would be preferable.
- The contract does not define session updates or deletion, nor run deletion; the interface must not promise these actions.
- The business rules behind `409` conflicts are not documented. Server examples are needed to write appropriate recovery messages and actions.
- Bearer-token scope (user, environment, expiration, and renewal) is unspecified; it determines the final connection flow.

## Recommended delivery order

`M0 → M1 → M2 → M3 → M4`

M2 delivers the first complete business workflow. M3 can be deferred if providers are initially preconfigured on the server; otherwise, it becomes a prerequisite for M2 in environments without existing configuration.
