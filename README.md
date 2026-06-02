# hermes-mesh

三層 hermes 多節點協作架構：監測、委派、備援。

## 架構

```
Wall.E (primary)          ← 主腦：hermes gateway + kanban dispatcher + Claude agent
    ↑ 監測
Lai.Fu (watchdog)         ← 監測層：偵測 Wall.E 狀態，觸發備援，不跑 agent loop
    ↓ 喚醒
Yggdrasill (standby)      ← 備援腦：Wall.E 故障時接管，x86_64 全能力
```

## 節點角色

| 節點 | 角色 | 說明 |
|---|---|---|
| Wall.E | 主腦 | hermes gateway（Telegram/Discord）+ kanban + Claude agent |
| Lai.Fu | 監測/觸發 | 30s 心跳探測，Wall.E 掛點通知 Ken + 喚醒 Yggdrasill |
| Yggdrasill | 備援腦 | Wall.E 故障時啟動，x86_64，完整 Claude/hermes 能力 |

## 目錄結構

```
lai-fu/       Lai.Fu 監測腳本與 systemd timer
wall-e/       Wall.E 相關設定與健康檢查
yggdrasill/   Yggdrasill 備援啟動設定
shared/       跨節點共用腳本與工具
```

## Failover 流程

1. Lai.Fu 每 30s 探測 Wall.E（TCP + SSH health check）
2. 連續 3 次失敗（約 90s）→ 宣告 Wall.E down
3. Lai.Fu 通知 Ken（Telegram）並 SSH 喚醒 Yggdrasill
4. Yggdrasill 啟動 hermes gateway 接管
5. Wall.E 恢復後：Yggdrasill drain → export failover tasks → 交還主控
