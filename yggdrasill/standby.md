# Yggdrasill 備援腦設定

## 前提條件

- hermes gateway 已安裝（`hermes gateway install`）
- 預設為停止狀態（`systemctl --user stop hermes-gateway.service`）
- Telegram/Discord bot token 設定完成

## 啟動方式

由 Lai.Fu 的 `activate-failover.sh` 自動觸發，或手動：

```bash
systemctl --user start hermes-gateway.service
```

## 停止方式（handback 時）

由 Lai.Fu 的 `handback.sh` 自動觸發，或手動：

```bash
systemctl --user stop hermes-gateway.service
```

## 確保開機不自啟（standby 模式）

```bash
systemctl --user disable hermes-gateway.service
```
