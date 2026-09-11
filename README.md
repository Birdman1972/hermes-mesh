# hermes-mesh

## Current state: suspended

This repository records a **suspended** Hermes Mesh deployment. Wall.E has
been decommissioned and is not part of the active topology. The only retained
nodes are Lai.Fu and Yggdrasill; Hermes gateways, Telegram/Discord delivery,
watchdogs, and automatic failover are disabled.

No repository-managed process may start a Hermes gateway, send a Telegram or
Discord message, probe a peer, or transfer control between nodes.

Two narrow exceptions on Yggdrasill, verified 2026-09-11: a systemd user timer
keeps the Hermes **CLI** updated, and its failure handler sends one Telegram
alert if an update run fails. Neither starts a gateway, probes a peer, nor
transfers control. Details in [yggdrasill/standby.md](yggdrasill/standby.md).

## Retained topology

| Node | Former responsibility | Current state |
|---|---|---|
| Lai.Fu | Lightweight watchdog and local sensor host | Suspended; Hermes and all message delivery disabled |
| Yggdrasill | Standby compute node | Gateway suspended; CLI kept updated by a local timer, which alerts Ken only on update failure |

Wall.E was removed from the active topology on 2026-08-21. Its former scripts,
health checks, addresses, credentials, and failover routes are not retained as
active repository configuration.

## Repository contents

```
hermes-mesh/
├── lai-fu/                  # Retained hardware and local configuration assets
├── yggdrasill/              # Suspension record plus Hermes CLI auto-update units
├── shared/scripts/          # Non-Hermes repository maintenance utilities only
├── data/                    # Historical local data
├── tasks.md                 # Historical task record plus current-state override
└── ROADMAP.md               # Historical architecture research, now inactive
```

`lai-fu/set-threshold.sh` remains only as a local configuration utility. It
records local changes and does not deliver notifications.

## Re-enablement policy

Re-enabling Hermes requires a new explicitly approved architecture plan. The
plan must define the intended nodes, message-delivery policy, service state,
monitoring boundaries, and verification steps before any service is started.

## Historical records

`tasks.md`, `ROADMAP.md`, Git history, and prior releases preserve the former
three-node high-availability design as historical evidence. They do not
describe current operational state and must not be used as deployment
instructions.

## Version history

| Date | Version | Change |
|---|---|---|
| 2026-09-11 | v0.2.1 | Brought the Yggdrasill Hermes CLI auto-update units under version control and recorded the verified unit states. |
| 2026-08-21 | v0.2.0 | Suspended Hermes Mesh, removed Wall.E from the active topology, and removed repository-managed failover, monitoring, and message-delivery automation. |
| 2026-07-23 | v0.1.9 | Historical: Wall.E health-check source was added to version control. |
| 2026-06-02 to 2026-07-22 | v0.1.0–v0.1.8 | Historical: three-node Hermes Mesh high-availability implementation. |
