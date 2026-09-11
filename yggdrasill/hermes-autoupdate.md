# Hermes Agent auto update (Yggdrasill)

Hermes Agent has no built-in auto update. A systemd **user** timer runs
`hermes update --yes` daily at 04:30 with a randomized delay, and sends a
Telegram alert if the run fails.

## Files and install paths

| Repo file | Installed path |
|---|---|
| `hermes-autoupdate.timer` | `~/.config/systemd/user/hermes-autoupdate.timer` |
| `hermes-autoupdate.service` | `~/.config/systemd/user/hermes-autoupdate.service` |
| `hermes-autoupdate-alert.service` | `~/.config/systemd/user/hermes-autoupdate-alert.service` |
| `hermes-autoupdate-alert.sh` | `~/.local/bin/hermes-autoupdate-alert.sh` (mode 755) |

## Install

```
cp hermes-autoupdate*.timer hermes-autoupdate*.service ~/.config/systemd/user/
install -m 755 hermes-autoupdate-alert.sh ~/.local/bin/
systemctl --user daemon-reload
systemctl --user enable --now hermes-autoupdate.timer
loginctl enable-linger "$USER"
```

## Check

```
systemctl --user list-timers hermes-autoupdate.timer
journalctl --user -u hermes-autoupdate.service -n 50
```

Do not run `npm audit fix` inside the Hermes checkout: it rewrites the upstream
lockfile and the next `hermes update` auto-stash will conflict.
