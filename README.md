# hermes-mesh

> 三層 hermes 多節點高可用協作架構：**主腦 (primary brain)**、**監測觸發 (watchdog/trigger)**、**備援腦 (standby brain)**。
>
> 本文件為 **canonical reference**（標準參考文件）。目標是：即使數年後失去全部記憶，僅憑此文件即可從零完整重建整套系統。

---

## 目錄

- [概觀 (Overview)](#概觀-overview)
- [架構圖 (Architecture Diagram)](#架構圖-architecture-diagram)
- [節點規格 (Node Specifications)](#節點規格-node-specifications)
- [Failover 規格 (Failover Spec)](#failover-規格-failover-spec)
- [Handback 規格 (Handback Spec)](#handback-規格-handback-spec)
- [Split-brain 防護 (Split-brain Guard)](#split-brain-防護-split-brain-guard)
- [檔案結構 (File Structure)](#檔案結構-file-structure)
- [安裝與部署 (Installation & Deployment)](#安裝與部署-installation--deployment)
- [Design Decisions（設計決策）](#design-decisions設計決策)
- [Known Limitations（已知限制）](#known-limitations已知限制)
- [Future Work（未來規劃）](#future-work未來規劃)
- [Version History（版本歷史）](#version-history版本歷史)

> 整體架構演進路線（冷備援→熱備援→多活）與開放決策清單見 [ROADMAP.md](./ROADMAP.md)。

---

## 概觀 (Overview)

`hermes-mesh` 由三台節點組成，分工明確：

| 層級 | 節點 | 角色定位 | 一句話說明 |
|---|---|---|---|
| L0 主腦 | **Wall.E** | PRIMARY BRAIN | 平時唯一對外服務的腦；跑 hermes gateway、kanban dispatcher 與 Claude agent loop |
| L1 監測 | **Lai.Fu** | WATCHDOG / TRIGGER | Raspberry Pi 2，每 30s 探測 Wall.E；**不跑 agent loop**，正常運作 token 成本為零；偵測掛點即觸發 failover |
| L2 備援 | **Yggdrasill** | STANDBY BRAIN | x86_64 全能力備援腦；gateway 預設關閉，僅在 failover 時被喚醒 |

設計核心理念：

1. **便宜的監測層 + 昂貴的運算層分離。** 用一台 1GB RAM 的 Pi 2 當守門人，避免主腦為了「自我監測」而消耗運算與 token。
2. **每個節點本地獨立 SQLite，永不共享。** 杜絕網路檔案系統上的 SQLite 損毀風險。
3. **bot token 嚴格分離。** 每個節點有自己的 Telegram/Discord token，從根本避免 split-brain 雙重回應。

---

## 架構圖 (Architecture Diagram)

```
                            ┌──────────────────────────────┐
        使用者 (Ken)        │   Telegram / Discord clients   │
                            └───────────────┬────────────────┘
                                            │ (平時)
                                            ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  Wall.E  —  PRIMARY BRAIN                       x86_64 Linux        │
   │  hostname: Wall.E-Hermes                                            │
   │  LAN 192.168.81.166 / TS 100.119.88.20  · SSH :16622               │
   │  ┌──────────────┐  ┌─────────────────┐  ┌────────────────────┐    │
   │  │hermes gateway│→ │ kanban dispatcher│→ │ Claude agent loop  │    │
   │  │ (TG+Discord) │  │  local kanban.db │  │  (推理/執行)        │    │
   │  └──────────────┘  └─────────────────┘  └────────────────────┘    │
   └──────────────────────────────────────────────────────────────────┘
                       ▲                                  │
          L1: nc -z TCP :16622                            │ (Wall.E 健康時
          L2: SSH systemctl is-active                     │  Yggdrasill 保持沉睡)
                       │                                  ▼
   ┌──────────────────────────────────────┐   ┌──────────────────────────────┐
   │ Lai.Fu — WATCHDOG / TRIGGER          │   │ Yggdrasill — STANDBY BRAIN    │
   │ Raspberry Pi 2 · armhf 32-bit · 1GB  │   │ x86_64 · LAN 192.168.81.195   │
   │ hostname: Lai-Fu-Hermes          │   │                               │
   │ LAN 192.168.81.167 / TS 100.75.192.113│  │  hermes gateway: INSTALLED    │
   │ SSH :11322                           │   │  但 DISABLED（不自啟）        │
   │                                      │   │                               │
   │ systemd timer 每 30s                 │   │  ┌─────────────────────────┐  │
   │ ┌──────────────┐                     │   │  │ full Claude/hermes 能力  │  │
   │ │ watchdog.sh  │── 連續 3 次失敗 ────────────▶│ failover 時被 SSH 喚醒   │  │
   │ │ (L1+L2 探測) │  activate-failover  │   │  └─────────────────────────┘  │
   │ └──────┬───────┘                     │   └──────────────────────────────┘
   │        │ 觸發時                       │
   │        ├─▶ 寫 lockfile               │
   │        ├─▶ Telegram 通知 Ken         │
   │        └─▶ SSH 喚醒 Yggdrasill ──────────────────────────┘ (上方箭頭)
   │                                      │
   │  ※ 零 agent loop · 零 token 成本     │
   └──────────────────────────────────────┘

   圖例：
     →   平時資料/控制流
     ▲▼  Lai.Fu 對 Wall.E 的健康探測 (L1 TCP + L2 SSH)
     ───▶ failover 觸發路徑（僅在 Wall.E 掛點時啟動）
```

---

## 節點規格 (Node Specifications)

### Wall.E — PRIMARY BRAIN

| 項目 | 值 |
|---|---|
| Hostname | `Wall.E-Hermes` |
| 架構 | x86_64 Linux |
| LAN IP | `192.168.81.166` |
| Tailscale IP | `100.119.88.20` |
| SSH port | `16622` |
| SSH 防火牆 (ufw) | 僅允許 Tailscale + 指定 LAN IP |
| hermes 版本 | `v0.15.1` |
| hermes profile | `default`（模型 `gemini-2.5-flash`） |
| Telegram bot | Wall.E 專屬 token |
| Discord bot | Wall.E 專屬 token |
| Mem0 user_id | `wall-e-user` |
| 跑 agent loop | ✅ 是（主腦） |
| kanban.db | 本地獨立，**永不共享** |

### Lai.Fu — WATCHDOG / TRIGGER

| 項目 | 值 |
|---|---|
| Hostname | `Lai-Fu-Hermes`（舊名 `openclaw`，2026-06-02 更名） |
| 硬體 | Raspberry Pi 2 Model B |
| 架構 | armhf 32-bit (ARMv7) |
| RAM | 1GB |
| LAN IP | `192.168.81.167` |
| Tailscale IP | `100.75.192.113` |
| SSH port | `11322`（hardened 2026-06-04） |
| SSH 防火牆 (ufw) | 僅允許 LAN + Tailscale |
| hermes MemoryMax | `512MB` |
| systemd watchdog | `60s`（Pi 2 BCM2836 硬體最小值，設更低無效） |
| Telegram bot | `@LaiFu890308_bot`（獨立 token） |
| Discord bot | `Lai Fu Hermes#9993`（獨立 token） |
| Mem0 user_id | `laif-user` |
| 跑 agent loop | ❌ 否（armhf 32-bit 不支援 claude-code/codex，512MB 亦不足） |
| `hermes-watchdog.timer` | ✅ installed & active（自 2026-06-02 起） |

> ⚠️ **Lai.Fu 無法執行 claude-code 或 codex**：armhf 32-bit (ARMv7) 不在這些 CLI 的支援平台清單內（僅支援 linux-arm64）。這是把 agent loop 放在 Yggdrasill 而非 Lai.Fu 的硬性原因。

### Yggdrasill — STANDBY BRAIN

| 項目 | 值 |
|---|---|
| 架構 | x86_64 |
| LAN IP | `192.168.81.195` |
| SSH port | `19522` |
| Tailscale IP | `100.93.159.12` |
| 角色 | core compute node，全能力備援 |
| hermes gateway | v0.15.1 已安裝，設為 **DISABLED（不自啟，standby 模式）** |
| 跑 agent loop | ✅ 具備能力（僅 failover 時啟用） |
| kanban.db | 本地獨立（failover 期間使用，恢復後匯出給 Wall.E） |

---

## Failover 規格 (Failover Spec)

由 Lai.Fu 的 `watchdog.sh` 驅動，systemd timer 觸發。

### 探測參數

| 參數 | 值 | 來源 |
|---|---|---|
| Poll interval | `30s` | `hermes-watchdog.timer` → `OnUnitActiveSec=30` |
| Boot delay | `60s` | `hermes-watchdog.timer` → `OnBootSec=60` |
| AccuracySec | `5s` | `hermes-watchdog.timer` |
| DOWN 門檻 | 連續 **3 次**失敗 | `watchdog.sh` → `FAIL_THRESHOLD=3` |
| 實際 debounce | 約 **90s**（3 × 30s） | 設計刻意大於 Pi 2 硬體 watchdog 60s |
| 失敗計數檔 | `/tmp/walle-fail-count` | 健康時歸零 |
| Lockfile | `$HOME/.local/share/hermes-mesh/laifu-active` | 防止重複觸發（持久路徑，非 tmpfs，見 decision_t18_no_heartbeat） |

### 雙層健康探測

| 層級 | 指令 | 意義 |
|---|---|---|
| **L1** | `nc -z -w5 <WALLE_HOST> <WALLE_SSH_PORT>` | TCP liveness（主機/網路是否活著） |
| **L2** | `ssh -o ConnectTimeout=5 -o BatchMode=yes -p <port> ken@<host> 'systemctl --user is-active hermes-gateway.service'` | gateway service 是否真的在跑 |

任一層失敗即計數 +1。L1 失敗則不再嘗試 L2（提早 `exit 0`）。

### 觸發動作（`activate-failover.sh`）

連續 3 次失敗且 lockfile 不存在時執行：

1. `touch` lockfile（`$HOME/.local/share/hermes-mesh/laifu-active`）— 上鎖，防止重複觸發
2. `logger` 記錄 `FAILOVER ACTIVATED`
3. 透過 **Lai.Fu 的 Telegram bot** 通知 Ken：
   `⚠️ Wall.E unreachable — Lai.Fu 監測觸發備援流程，正在喚醒 Yggdrasill。`
4. SSH 至 Yggdrasill 執行 `systemctl --user start hermes-gateway.service` 喚醒備援腦
5. 喚醒失敗則 `logger` 記錄 `WARNING: Failed to wake Yggdrasill`（不中斷流程）

---

## Handback 規格 (Handback Spec)

當 Lai.Fu 偵測到 Wall.E 恢復（且 lockfile 存在）時，由 `handback.sh` 執行控制權交還。

恢復判定：watchdog 完成 L1+L2 探測（健康分支）後累計成功次數；觸發條件：連續 3 次健康探測（`SUCCESS_THRESHOLD=3`，對稱於 failover 的 `FAIL_THRESHOLD`）。

| 步驟 | 動作 |
|---|---|
| 1 | `logger` 記錄 `Handback: Wall.E recovered` |
| 2 | **Drain Yggdrasill**：SSH 停止 `hermes-gateway.service`（graceful） |
| 3 | **Export failover-era tasks**：SSH 至 Yggdrasill `sqlite3 ~/.hermes/kanban/kanban.db .dump` 匯出到 `/tmp/laifu-failover-tasks-<timestamp>.sql` |
| 4 | `scp` 該 dump 到 Wall.E 的 `~/failover-tasks/`（供人工/Wall.E 合併） |
| 5 | 移除 lockfile（解鎖，允許未來再次觸發） |
| 6 | Telegram 通知 Ken：`✅ Wall.E 已恢復，Yggdrasill 備援結束。failover 期間任務已匯出供 Wall.E 合併。` |
| 7 | `logger` 記錄 `Handback complete` |

> 任務調和 (task reconciliation) 為 **手動 / Wall.E 主導**。Lai.Fu 只負責把 Yggdrasill 期間的任務 dump 搬到 Wall.E，**不做自動 merge**，以確保 Pi 2 永遠不進入任何 write path。

---

## Split-brain 防護 (Split-brain Guard)

防止「兩個腦同時對外回應」或「資料庫互相覆寫」的多重機制：

| 機制 | 說明 |
|---|---|
| **分離 bot token** | 每節點各自的 Telegram/Discord token，不存在 token 爭用，兩腦不會同時用同一身分回覆 |
| **本地 SQLite per node** | 每節點本地 `kanban.db`，**永不共享**（不放網路 FS） |
| **Lockfile** | `$HOME/.local/share/hermes-mesh/laifu-active` 確保 failover 只觸發一次，恢復才解鎖 |
| **90s debounce** | 連續 3 次（~90s）才宣告 down，刻意大於 Pi 2 硬體 watchdog (60s) 與 `Restart=always` 反彈時間，避免暫時抖動誤判 |
| **手動 reconciliation** | 任務合併由 Wall.E 主導，Pi 2 不參與寫入 |

---

## 檔案結構 (File Structure)

```
hermes-mesh/
├── README.md                   # 本文件（canonical reference）
├── lai-fu/
│   ├── watchdog.sh             # 主探測腳本（L1+L2 + 失敗計數 + 觸發/handback 分派）
│   ├── activate-failover.sh    # failover 觸發（lockfile + Telegram 通知 + 喚醒 Yggdrasill）
│   ├── handback.sh             # Wall.E 恢復後交還控制（drain + export tasks + 通知）
│   ├── install.sh              # 部署到 Lai.Fu（複製 unit + 啟用 timer）
│   ├── hermes-watchdog.service # oneshot service，ExecStart=watchdog.sh
│   └── hermes-watchdog.timer   # OnBootSec=60, OnUnitActiveSec=30
├── wall-e/
│   ├── health-check.sh         # 主腦健康自檢（gateway / kanban / failover-tasks）
│   ├── install.sh              # 部署到 Wall.E（建立 ~/failover-tasks/ + 執行健康檢查）
│   └── hermes-healthcheck.sh   # Telegram/Discord 告警腳本（hermes-healthcheck.timer 驅動，system-level）
│                                # 部署路徑：/home/ken/.local/bin/hermes-healthcheck.sh（2026-07-23 起納入版控，先前為未追蹤獨立檔案）
├── yggdrasill/
│   ├── laifu-monitor.sh        # 探測 Lai.Fu（L1: nc TCP + L2: SSH，3次失敗告警）
│   ├── hermes-laifu-monitor.service
│   ├── hermes-laifu-monitor.timer  # OnUnitActiveSec=2min
│   └── standby.md              # 備援腦啟/停與 standby 模式說明
└── shared/scripts/
    └── failover-drill.sh       # 全節點連通 + failover/handback 流程驗證（dry-run 預設 / --live 實際演練）
```

### 關鍵腳本變數速查（重建用）

`lai-fu/watchdog.sh`：
```
WALLE_HOST="100.119.88.20"      # Wall.E Tailscale IP
WALLE_SSH_PORT="16622"
WALLE_USER="ken"
FAIL_THRESHOLD=3
COUNTER_FILE="/tmp/walle-fail-count"
LOCK_FILE="$HOME/.local/share/hermes-mesh/laifu-active"
```

`lai-fu/activate-failover.sh` / `handback.sh`：
```
YGGDRASILL_HOST="192.168.81.195"
YGGDRASILL_SSH_PORT="19522"
YGGDRASILL_USER="ken"
HERMES="/home/ken/.local/bin/hermes"
```

---

## 安裝與部署 (Installation & Deployment)

### 前置條件（所有節點）

- 各節點已安裝 hermes 並設定 **各自獨立的** Telegram/Discord token 與 Mem0 user_id（見上方節點規格表）。
- Lai.Fu → Wall.E、Lai.Fu → Yggdrasill 的 SSH 已設定為**免密 key 登入**（`BatchMode=yes` 需要）。
- Tailscale 已在 Wall.E 與 Lai.Fu 上運作（watchdog 走 Tailscale IP）。
- Lai.Fu 上 `nc`、`ssh`、`scp`、`sqlite3`、`logger` 可用。

### Lai.Fu（監測層）

```bash
# 於 Lai.Fu 上
cd ~/hermes-mesh/lai-fu
./install.sh
```

`install.sh` 會：
1. 建立 `~/.config/systemd/user/`
2. `chmod +x` 三個腳本
3. 複製 `hermes-watchdog.service` 與 `.timer` 到 systemd user 目錄
4. `systemctl --user daemon-reload`
5. `systemctl --user enable --now hermes-watchdog.timer`

驗證：
```bash
systemctl --user status hermes-watchdog.timer
journalctl --user -t hermes-watchdog -f      # 觀察探測 log
```

> 若 Lai.Fu 為 headless 並需開機即啟動 user timer，記得啟用 lingering：`loginctl enable-linger ken`。

### Yggdrasill（備援層）

依 `yggdrasill/standby.md`：

```bash
# 安裝 gateway 但保持 standby（不自啟）
systemctl --user disable hermes-gateway.service
systemctl --user stop hermes-gateway.service
```

failover 時由 Lai.Fu 自動 `start`；handback 時自動 `stop`。亦可手動操作同名指令。

### Wall.E（主腦）

正常運作 hermes gateway（`hermes-gateway.service`，user scope）。Lai.Fu 透過 L2 探測此 service 的 `is-active` 狀態。

---

## Design Decisions（設計決策）

> 以下決策經 **dual-brain 對抗稽核**（Opus 4.7 + GPT-5.5）審查，日期 **2026-06-02**。

| # | 決策 | 理由 | 信心 |
|---|---|---|---|
| D1 | **不共享 kanban.db** | SQLite 放在網路檔案系統（NFS/SMB）上的鎖機制不可靠，會造成資料庫損毀。改為每節點本地獨立 DB，failover 後再手動匯出合併。 | 9–10/10 |
| D2 | **Lai.Fu 不跑 agent loop** | armhf 32-bit 不支援 Claude/codex CLI（僅 linux-arm64）；且 1GB RAM 中 hermes 限 512MB，無法承載 agent。Lai.Fu 僅做輕量探測，正常運作 token 成本為零。 | 高 |
| D3 | **Yggdrasill 才是真正的備援腦** | x86_64 全能力，可完整跑 Claude/hermes。把運算備援放在能跑運算的機器，而非 Pi 2。 | 高 |
| D4 | **bot token 嚴格分離** | 每節點獨立 token，避免 token 爭用與 split-brain（兩腦同身分回覆）。 | 高 |
| D5 | **90s debounce** | 連續 3 次（~90s）才宣告 down，刻意大於 Pi 2 硬體 watchdog 60s 與 `Restart=always` 的反彈時間，避免主腦短暫重啟被誤判為掛點。 | 高 |
| D6 | **任務調和手動 / Wall.E 主導** | 不做自動 merge，讓 Pi 2 完全不進入任何 write path，降低 Pi 2 故障污染資料的風險。 | 高 |

---

## Known Limitations（已知限制）

- **Pi 2 硬體限制**
  - armhf 32-bit (ARMv7)，無法跑 claude-code / codex；故 Lai.Fu 永遠只能當守門人，不能當備援腦。
  - 1GB RAM；hermes 受限於 `MemoryMax=512MB`。
  - 硬體 watchdog 最小 timeout 為 **60s**（BCM2836 限制），systemd 設更低無效。
  - 啟用 memory cgroup 需改 `cmdline.txt`（`cgroup_enable=memory cgroup_memory=1`）才能讓 `MemoryMax/MemoryHigh` 生效。
- **failover 對使用者非透明 (no transparent failover)**
  - 切換到 Yggdrasill 時，對外身分是 Yggdrasill 的 bot token，使用者會感知到「換了一個 bot」，並非無縫接管。
- **手動任務調和 (manual task reconciliation)**
  - failover 期間 Yggdrasill 產生的任務以 SQL dump 形式搬到 Wall.E，需人工/Wall.E 主導合併，無自動 merge。
- **單一守門人 (single watchdog)**
  - Lai.Fu 負責探測 Wall.E 並觸發 failover；Yggdrasill 已加入輕量探測 Lai.Fu（T14，v0.1.6），Lai.Fu 掛掉時發 Telegram 告警，但不自動接管（防 split-brain）。
- **恢復判定較樂觀**
  - handback 現已要求連續 `SUCCESS_THRESHOLD=3` 次健康探測才啟動 drain（對稱於 failover 的 `FAIL_THRESHOLD=3`），避免 Wall.E flapping 造成抖動切換。

---

## Future Work（未來規劃，v0.2+）

> 架構演進路線與優先級決策見 [ROADMAP.md](./ROADMAP.md)。

- ✅ **handback 對稱 debounce**（已實作 v0.1.5）：`SUCCESS_THRESHOLD=3` 連續健康探測才交還控制，對稱於 `FAIL_THRESHOLD=3`，避免 Wall.E flapping 造成抖動切換。
- ✅ **第二監測者 / watchdog 互備**（已實作 v0.1.6）：Yggdrasill 每 2 分鐘探測 Lai.Fu（nc TCP + SSH 雙層），連續 3 次失敗發 Telegram 告警，不自動接管（防 split-brain）。部署：`systemctl --user enable --now hermes-laifu-monitor.timer`（在 Yggdrasill 執行）。
- **半透明 failover**：研究共用 bot 身分或前置代理 (proxy) 讓使用者無感切換，同時不破壞 token 分離的 split-brain 防護。
- **自動任務調和**：在不讓 Pi 2 進入 write path 的前提下，由 Wall.E 端自動 merge failover-era tasks。
- ✅ **`wall-e/` 與 `shared/scripts/` 落地**（已實作 v0.1.7）：Wall.E 健康檢查腳本（`wall-e/health-check.sh`）與跨節點 failover drill（`shared/scripts/failover-drill.sh`）。
- **可觀測性**：集中收集三節點的 watchdog/gateway log 與 failover 事件指標（如 failover 次數、MTTR）。
- ✅ **演練機制 (failover drill)**（已實作 v0.1.7）：`shared/scripts/failover-drill.sh`；dry-run 驗證 11 項前置條件，`--live` 執行完整 failover→handback 並計時等待。

---

## Operational Runbook（操作手冊）

### 日常狀態確認

```bash
# 在 Lai.Fu 確認 watchdog timer 正常
systemctl --user status hermes-watchdog.timer
cat /tmp/walle-fail-count          # 應為 0

# 確認 Wall.E gateway 正常（從 Lai.Fu）
ssh -p 16622 ken@100.119.88.20 'systemctl --user is-active hermes-gateway.service'

# 確認 Yggdrasill gateway 處於 standby（從 Wall.E 或任意節點）
ssh ken@192.168.81.195 'systemctl --user is-active hermes-gateway.service'
# 預期輸出：inactive
```

### 手動觸發 Failover（緊急時）

```bash
# 在 Lai.Fu 上執行
cd ~/hermes-mesh/lai-fu
./activate-failover.sh

# 驗證 Yggdrasill 已接手
ssh ken@192.168.81.195 'systemctl --user is-active hermes-gateway.service'
# 預期：active
```

### 手動執行 Handback（Wall.E 恢復後）

```bash
# 確認 Wall.E 健康（先行驗證再 handback）
ssh -p 16622 ken@100.119.88.20 'systemctl --user is-active hermes-gateway.service'

# 在 Lai.Fu 執行 handback
cd ~/hermes-mesh/lai-fu
./handback.sh

# 驗證恢復
ls "$HOME/.local/share/hermes-mesh/laifu-active" 2>/dev/null || echo "lockfile removed OK"
ssh ken@192.168.81.195 'systemctl --user is-active hermes-gateway.service'
# 預期：inactive
```

### Watchdog 故障排查

| 症狀 | 排查步驟 |
|---|---|
| Timer 沒跑 | `journalctl --user -t hermes-watchdog -n 50`；確認 `loginctl enable-linger ken` 已設 |
| L1 失敗但 Wall.E 實際正常 | 確認 Tailscale 狀態 `tailscale status`；改用 LAN IP 測試 |
| L2 失敗但 gateway 正常 | SSH key 可能過期；確認 `ssh -o BatchMode=yes -p 16622 ken@100.119.88.20 exit` |
| Telegram 通知未收到 | Lai.Fu hermes gateway 是否正常；`hermes gateway status` |
| Yggdrasill 無法被喚醒 | 確認 Lai.Fu → Yggdrasill SSH key 已設；`ssh ken@192.168.81.195 exit` |
| False positive failover | 確認 `FAIL_THRESHOLD=3` 未被改低；檢查 Tailscale 抖動 |
| L1/L2 持續失敗但兩節點皆正常（如 fail count 累積數百） | 確認 Lai.Fu 自己的 `tailscaled` 是否開機自啟：`systemctl is-enabled tailscaled`；曾發生 disabled+inactive 導致假 failover（2026-07-22 事故） |

### Disaster Scenarios

| 情境 | 影響 | 對應方式 |
|---|---|---|
| Wall.E down, Lai.Fu 正常 | failover 在約 90s 後自動觸發，Yggdrasill 接管 | 等通知；若未收到通知則手動 `activate-failover.sh` |
| Lai.Fu down, Wall.E 正常 | 監測失效，failover **不會觸發**；使用者仍正常用 Wall.E | 排查 Pi 2；手動重啟 `hermes-watchdog.timer` |
| Wall.E + Lai.Fu 同時 down | 無 failover 觸發，Yggdrasill 保持 standby | 手動 SSH 至 Yggdrasill 執行 `systemctl --user start hermes-gateway.service` |
| Yggdrasill down（Wall.E 正常）| 備援腦不可用，但主腦不受影響 | 排查 Yggdrasill；failover 觸發後 Lai.Fu 會記錄 WARNING |
| Tailscale down，LAN 正常 | L2 探測仍走 Tailscale IP → 誤判 Wall.E down | 臨時修改 `watchdog.sh` 中 `WALLE_HOST` 為 LAN IP `192.168.81.166` |
| LAN down，Tailscale 正常 | 探測走 Tailscale，影響最小 | 無需操作 |
| Telegram/Discord 中斷 | Failover 仍執行，但 Ken 收不到通知 | 主動確認 Yggdrasill 狀態 |
| Wall.E nginx 開機時 Tailscale 介面尚未就緒 | nginx bind 失敗，反向代理服務（如 SearXNG 8888 外部 proxy）短暫不可用 | 已修復（2026-07-22）：nginx.service drop-in 加 `After=/Wants=tailscaled.service`，防止 boot race |

---

## Credential & Secret Inventory（密鑰清單）

> ⚠️ 本節記錄「有哪些密鑰、用途、存放位置」，**不含實際值**。重建時需從備份或重新申請。

| 密鑰 | 用途 | 存放位置 | 節點 |
|---|---|---|---|
| Telegram Bot Token | hermes Telegram gateway | `~/.hermes/.env` → `TELEGRAM_BOT_TOKEN` | Wall.E / Lai.Fu（各自獨立） |
| Discord Bot Token | hermes Discord gateway | `~/.hermes/.env` → `DISCORD_BOT_TOKEN` | Wall.E / Lai.Fu（各自獨立） |
| Gemini API Key | hermes LLM 呼叫 | `~/.hermes/.env` → `GEMINI_API_KEY` | Wall.E / Lai.Fu（各自獨立） |
| Mem0 API Key | hermes 記憶體層 | `~/.hermes/.env` → `MEM0_API_KEY` | 各節點 |
| OpenRouter API Key | hermes fallback LLM | `~/.hermes/.env` → `OPENROUTER_API_KEY` | 各節點 |
| SSH Key (Lai.Fu) | Lai.Fu → Wall.E / Yggdrasill | `~/.ssh/id_ed25519` | Lai.Fu |
| SSH Key (Wall.E) | Wall.E → 其他節點 | `~/.ssh/id_ed25519` | Wall.E |

**節點間 SSH 授權關係（authorized_keys 已設定）：**

| 來源 | 目標 | Port | 用途 |
|---|---|---|---|
| Lai.Fu (ken@Lai-Fu-Hermes, key comment: ken@openclaw) | Wall.E :16622 | `~/.ssh/authorized_keys` on Wall.E | watchdog L2 探測 |
| Lai.Fu (ken@Lai-Fu-Hermes, key comment: ken@openclaw) | Yggdrasill :19522 | `~/.ssh/authorized_keys` on Yggdrasill | failover 喚醒 / handback drain |
| Wall.E (ken) | Lai.Fu :22 | `~/.ssh/authorized_keys` on Lai.Fu | 管理 |

**重要規則：**
- 各節點 Telegram/Discord token **不得複製到其他節點**（token 分離是 split-brain 防護的核心）
- Yggdrasill 的 hermes token 應為 **獨立申請**的 bot，不是 Wall.E 或 Lai.Fu 的副本

---

## Version History（版本歷史）

> **RULE：每次修改本 README 都必須在此表新增一列（日期 | 版本 | 變更 | 作者）。不可省略。**

| 日期 | 版本 | 變更 | 作者 |
|---|---|---|---|
| 2026-06-02 | v0.1.0 | 初版：建立 canonical reference。涵蓋三層架構、節點規格、failover/handback 規格、split-brain 防護、design decisions（dual-brain Opus 4.7 + GPT-5.5 審查）、known limitations、future work。 | Ken + Claude |
| 2026-06-02 | v0.1.1 | 補充 Operational Runbook（日常確認、手動 failover/handback、故障排查）、Disaster Scenarios、Credential Inventory（GPT-5.5 gap review 結果）。 | Ken + Claude |
| 2026-06-02 | v0.1.2 | 更新 Yggdrasill 節點規格：SSH port=19522（已確認）、Tailscale 未加入、scripts 變數速查補 YGGDRASILL_SSH_PORT。 | Ken + Claude |
| 2026-06-02 | v0.1.3 | Lai.Fu hostname 更名：openclaw → Lai-Fu-Hermes（Linux hostname 不支援底線）。 | Ken + Claude |
| 2026-06-02 | v0.1.4 | 新增 ROADMAP.md 連結（架構演進路線、備援光譜、多活決策）；TOC 與 Future Work 加指向。 | Ken + Claude |
| 2026-06-04 | v0.1.5 | 修正 Lai.Fu SSH port 22→11322（harden commit）；修正 Yggdrasill Tailscale IP（未加入→100.93.159.12）；Yggdrasill hermes gateway 標記已安裝（v0.15.1，T08 完成）。 | Ken + Claude（Sonnet 4.6） |
| 2026-06-04 | v0.1.6 | T14 第二監測者：新增 yggdrasill/laifu-monitor.sh + hermes-laifu-monitor.timer（2min 探測，3次失敗告警，不自動接管）；Known Limitations 更新；Future Work 標記已實作。 | Ken + Claude（Sonnet 4.6） |
| 2026-06-05 | v0.1.7 | T16 wall-e/ 落地：新增 wall-e/health-check.sh + install.sh（gateway/kanban/failover-tasks 三項自檢，Wall.E 實測 3 OK）；檔案結構更新（wall-e/ + yggdrasill/ 均展開）。 | Ken + Claude（Sonnet 4.6） |
| 2026-07-22 | v0.1.8 | 事故修復：Wall.E `.env` SEARXNG_URL 誤指向 8888（實際監聽 9119）已修正；Wall.E nginx 開機 bind race 加 drop-in 等待 tailscaled；Wall.E 清理 nouveau-pstate/snap-tailscale 兩個孤兒 failed units；Lai.Fu `tailscaled` 開機未自啟（disabled+inactive）導致 17:04 假 failover（fail_count=602，Yggdrasill 誤接管），已 enable+start 並確認 watchdog 自動 handback 成功。Watchdog 故障排查/Disaster Scenarios 新增對應列。 | Ken + Claude（Sonnet 5） |
