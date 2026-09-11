# Yggdrasill Hermes suspension

Yggdrasill is retained as a suspended node. Its Hermes gateway and Telegram/
Discord delivery are disabled. This repository provides no automatic startup,
failover, handback, or reverse-monitoring path.

Do not enable or start Hermes from this repository. Re-enabling the node
requires a new, explicitly approved architecture and deployment plan.

## Verified state (2026-09-11, on Yggdrasill)

| Unit | Enabled | Active |
|---|---|---|
| `hermes-gateway.service` (user) | disabled | inactive |
| `hermes-autoupdate.timer` (user) | enabled | active |
| `hermes-mesh-sync.timer` (user) | enabled | active |

The gateway stays suspended. Only the Hermes **CLI** is kept current by
`hermes-autoupdate.timer`, so a future re-enablement does not start from a
badly outdated checkout. Keeping the CLI updated does not start a gateway,
probe a peer, or transfer control.

**Exception to the no-delivery rule:** `hermes-autoupdate-alert.sh` sends one
Telegram message to Ken when an update run fails, falling back to a local
desktop notification. This is failure alerting for the update job itself, not
mesh messaging. See [hermes-autoupdate.md](hermes-autoupdate.md).
