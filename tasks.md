# tasks.md — hermes-mesh 持久化任務記憶

> **這份檔案是 hermes-mesh 的 persistent task management memory（跨 session 任務記憶）。**
>
> 任何未來的 session（任何 AI 助手、任何日期）只要讀完這份檔案，就應該完整知道：
> **已經做完什麼 / 正在做什麼 / 接下來該做什麼 / 為什麼這樣設計。**
>
> 架構與規格細節的 **canonical reference 是 [`README.md`](./README.md)**。
> 本檔案只負責「任務進度與交接」，不重複 README 的完整規格——需要細節時請去讀 README 對應章節。

| 項目 | 值 |
|---|---|
| tasks.md 版本 | **v1.2** |
| 最後更新 | 2026-06-02 |
| 對應 README 版本 | v0.1.2 |
| 維護者 | Ken + AI 助手 |

---

## 0. 給「零上下文 session」的 30 秒簡報

`hermes-mesh` 是三台機器組成的 hermes 多節點高可用架構：

| 角色 | 節點 | 一句話 | 平時狀態 |
|---|---|---|---|
| L0 主腦 PRIMARY | **Wall.E** | 唯一對外服務的腦，跑 agent loop | gateway **active** |
| L1 監測 WATCHDOG | **Lai.Fu** (Raspberry Pi 2) | 每 30s 探測 Wall.E，掛了就觸發 failover；不跑 agent loop | watchdog timer **active** |
| L2 備援 STANDBY | **Yggdrasill** (x86_64) | 全能力備援腦，平時沉睡 | gateway **disabled / inactive** |

連線資訊（重建/操作時最常用）：

| 節點 | LAN IP | Tailscale IP | SSH port | user |
|---|---|---|---|---|
| Wall.E | 192.168.81.166 | 100.119.88.20 | **16622** | ken |
| Lai.Fu | 192.168.81.167 | 100.75.192.113 | 22 | ken |
| Yggdrasill | 192.168.81.195 | 未加入 Tailscale | **19522**（已確認） | ken |

GitHub repo：<https://github.com/Birdman1972/hermes-mesh>

**目前整體進度：** L0 主腦 + L1 監測層已上線並驗證；L2 備援層 (Yggdrasill) 尚未配置；端到端 failover 演練尚未執行。
**最關鍵的下一步：** 見 [§5 Session 交接](#5-session-交接handoff) 的「Next recommended action」。

---

## 1. 全 Session 通用規則（RULES — 任何 session 都必須遵守）

> 這些規則 **override 預設行為**，無論是哪個 AI 助手、哪一天接手都適用。

- **R1 — README 是 canonical reference。** 任何架構、規格、節點參數、failover/handback 流程的變更，**必須同步更新 `README.md`**，並在 README 末尾 `Version History` 新增一列（日期 | 版本 | 變更 | 作者）。不可省略。
- **R2 — 任務狀態必須即時更新本檔案。** 完成、開始、卡住一個任務時，立即更新對應任務的 `狀態` 欄與 `Notes`，並更新 §5 Session 交接區。
- **R3 — DONE 任務永不刪除。** 已完成任務保留作為歷史紀錄（見 §2）。只改狀態，不刪行。
- **R4 — token 分離是鐵律。** 各節點的 Telegram/Discord/Mem0 token **不得互相複製**。Yggdrasill 必須用獨立申請的 bot token，不能是 Wall.E 或 Lai.Fu 的副本（split-brain 防護核心，見 README「Split-brain 防護」）。
- **R5 — Pi 2 (Lai.Fu) 永不進入任何 write path。** Lai.Fu 只做探測與搬運（SQL dump 搬到 Wall.E），不做自動 merge、不跑 agent loop。任何讓 Lai.Fu 寫資料庫的設計都要拒絕。
- **R6 — 改 watchdog 參數要保 debounce ≥ Pi 2 硬體 watchdog (60s)。** `FAIL_THRESHOLD × poll interval` 必須維持 ≥ 90s，避免主腦短暫重啟被誤判。改前先讀 README「Split-brain 防護」D5。
- **R7 — 任務有 DoD 才算完成。** 沒有可量測驗收條件（DoD）達標前，不得把任務標記 DONE。改動腳本後須在目標節點實機驗證，不能只看本機檔案。
- **R8 — 改本檔案就更新版本/日期。** 任何對 tasks.md 的實質修改，更新頂部「tasks.md 版本」與「最後更新」。
- **R9 — 密鑰絕不入 repo。** 實際 token / API key / 私鑰一律放各節點 `~/.hermes/.env` 或 `~/.ssh/`，repo 只記「有哪些密鑰、用途、位置」（見 README「Credential & Secret Inventory」）。
- **R10 — 任何時刻最多只有一個 gateway active（hard invariant）。** 若 Wall.E gateway active，Yggdrasill 必須 inactive；反之亦然。違反此規則會造成雙 bot 回應與 split-brain，是最嚴重的 failure mode。
- **R11 — Yggdrasill gateway 預設只能 standby，不得主動啟動。** 唯一例外：明確標記為 failover drill 且 Ken 已確認的任務。任何其他情況啟動 Yggdrasill gateway 前必須停止 Wall.E gateway。
- **R12 — 任何 SSH / systemd / deploy / restart 操作前，必須先說明目標主機 + 命令目的 + 預期影響，再等 Ken 確認。** Wall.E（生產主腦）變更一律要計畫先行，不可直接執行。
- **R13 — 任何完成宣告必須附 DoD evidence（實際驗證指令 + 結果摘要）。** 沒有 evidence 的 DONE 視為 IN_PROGRESS。

---

## 2. 已完成任務（DONE — 歷史紀錄，依 R3 永久保留）

| ID | 標題 | 狀態 |
|---|---|---|
| T01 | 建立 hermes-mesh repo | ✅ DONE |
| T02 | 三層架構設計（dual-brain 審查） | ✅ DONE |
| T03 | 撰寫 canonical README v0.1.1 | ✅ DONE |
| T04 | 實作 lai-fu watchdog 全套腳本 | ✅ DONE |
| T05 | Lai.Fu 部署 watchdog timer 並驗證 | ✅ DONE |
| T06 | 驗證 Lai.Fu → Wall.E SSH（L2 探測通路） | ✅ DONE |

### T01 — 建立 hermes-mesh repo · ✅ DONE
- **描述：** 建立 GitHub repo 與初始目錄結構。
- **DoD：** repo 存在於 <https://github.com/Birdman1972/hermes-mesh>，含 `lai-fu/ wall-e/ yggdrasill/ shared/ data/` 目錄。✅
- **依賴：** 無
- **Notes：** init commit `98a8795`。

### T02 — 三層架構設計（dual-brain 審查） · ✅ DONE
- **描述：** 設計主腦 / 監測 / 備援三層，經 Opus 4.7 + GPT-5.5 對抗稽核。
- **DoD：** 架構與 6 條 Design Decisions (D1–D6) 寫入 README，標註信心分數。✅
- **依賴：** 無
- **Notes：** 審查日期 2026-06-02，見 README「Design Decisions」。

### T03 — 撰寫 canonical README v0.1.1 · ✅ DONE
- **描述：** 撰寫可從零重建整套系統的標準參考文件。
- **DoD：** README 含 概觀 / 架構圖 / 節點規格 / failover+handback 規格 / split-brain 防護 / 安裝部署 / runbook / disaster scenarios / 密鑰清單 / 版本歷史。✅
- **依賴：** T02
- **Notes：** commit `805273f`。v0.1.0 初版 + v0.1.1 補 runbook（GPT-5.5 gap review）。

### T04 — 實作 lai-fu watchdog 全套腳本 · ✅ DONE
- **描述：** 實作監測層全部腳本與 systemd unit。
- **DoD：** 以下檔案存在且邏輯完整：`lai-fu/watchdog.sh`、`activate-failover.sh`、`handback.sh`、`install.sh`、`hermes-watchdog.service`、`hermes-watchdog.timer`。✅
- **依賴：** T03
- **Notes：** 關鍵變數見 README「關鍵腳本變數速查」。`FAIL_THRESHOLD=3`，lockfile `/run/user/$(id -u)/laifu-active`。

### T05 — Lai.Fu 部署 watchdog timer 並驗證 · ✅ DONE
- **描述：** 在 Lai.Fu 跑 `install.sh`，啟用 timer。
- **DoD：** `systemctl --user status hermes-watchdog.timer` = active；`cat /tmp/walle-fail-count` = 0。✅（2026-06-02 驗證 fail count=0）
- **依賴：** T04
- **Notes：** headless 需 `loginctl enable-linger ken`。timer：OnBootSec=60、OnUnitActiveSec=30。

### T06 — 驗證 Lai.Fu → Wall.E SSH（L2 探測通路） · ✅ DONE
- **描述：** 確認 Lai.Fu 能免密 SSH 到 Wall.E 查 gateway 狀態。
- **DoD：** `ssh -o BatchMode=yes -p 16622 ken@100.119.88.20 'systemctl --user is-active hermes-gateway.service'` 回傳 active。✅
- **依賴：** T05
- **Notes：** 走 Tailscale IP 100.119.88.20:16622。

---

## 3. 待辦任務（TODO / IN_PROGRESS / BLOCKED — 已排序）

> 排序原則：先打通 L2 備援層基礎（T07–T11）→ 端到端演練（T12）→ 韌性強化（T13–T15）→ 落地補齊（T16–T17）。

| ID | 標題 | 狀態 | 依賴 | 優先 |
|---|---|---|---|---|
| T07 | Clone hermes-mesh 到 Yggdrasill | 🔲 TODO | T01 | P0 |
| T08 | Yggdrasill hermes gateway 安裝並設 standby | 🔲 TODO | T07 | P0 |
| T09 | Yggdrasill 獨立 Telegram/Discord bot token 設定 | 🔲 TODO | T08 | P0 |
| T10 | 設定 Lai.Fu → Yggdrasill 免密 SSH key | ✅ DONE | T11 | P0 |
| T11 | 確認/修正 Yggdrasill SSH port 與連線參數 | ✅ DONE | — | P0 |
| T12 | 端到端 failover 演練（verification matrix） | 🔲 TODO | T08,T09,T10,T11 | P1 |
| T13 | handback 對稱 debounce（連續 3 次成功才交還） | 🔲 TODO | T12 | P1 |
| T14 | 第二監測者：Yggdrasill 也監測 Lai.Fu | 🔲 TODO | T08,T10 | P2 |
| T15 | Approach D：Lai.Fu 透過 SSH kanban 委派任務給 Wall.E | 🔲 TODO | T06 | P2 |
| T16 | 補齊 `wall-e/` 內容（健康檢查腳本 + failover-tasks/） | 🔲 TODO | — | P2 |
| T17 | 補齊 `shared/scripts/` 跨節點共用工具 | 🔲 TODO | — | P3 |

---

### T07 — Clone hermes-mesh 到 Yggdrasill · 🔲 TODO
- **描述：** 在 Yggdrasill (192.168.81.195) 上 clone 本 repo，使其擁有 `yggdrasill/standby.md` 與全套腳本。
- **DoD：**
  - Yggdrasill 上存在 `~/hermes-mesh/`，`git remote -v` 指向 <https://github.com/Birdman1972/hermes-mesh>。
  - `git log` 含 commit `805273f` 或更新。
- **依賴：** T01
- **Notes：** clone 後即可依 `yggdrasill/standby.md` 操作。需先確認 Yggdrasill 連線（見 T11）。

### T08 — Yggdrasill hermes gateway 安裝並設 standby · 🔲 TODO
- **描述：** 在 Yggdrasill 安裝 hermes gateway，但設為 **disabled（開機不自啟）+ stopped**，符合 standby 模式。
- **DoD：**
  - `systemctl --user is-active hermes-gateway.service` → `inactive`
  - `systemctl --user is-enabled hermes-gateway.service` → `disabled`
  - 手動 `systemctl --user start hermes-gateway.service` 能成功拉起（測完再 stop+disable 還原）。
- **依賴：** T07
- **Notes：** 步驟見 `yggdrasill/standby.md` 與 README「Yggdrasill（備援層）」。standby 必須 disable，否則開機自啟會破壞「平時沉睡」前提。

### T09 — Yggdrasill 獨立 Telegram/Discord bot token 設定 · 🔲 TODO
- **描述：** 為 Yggdrasill 申請 **獨立** 的 Telegram + Discord bot，並寫入其 `~/.hermes/.env`。
- **DoD：**
  - Yggdrasill `~/.hermes/.env` 含專屬 `TELEGRAM_BOT_TOKEN` / `DISCORD_BOT_TOKEN`（非 Wall.E/Lai.Fu 副本）。
  - failover 喚醒後，該 bot 能對 Ken 回應。
  - Mem0 user_id 設為 Yggdrasill 專屬值（如 `yggdrasill-user`），並補進 README 節點規格表。
- **依賴：** T08
- **Notes：** ⚠️ 違反 R4 會造成 split-brain。Discord 新 bot 三個 Privileged Intents 必須全開，否則 timeout（已知坑）。token 不入 repo（R9）。

### T10 — 設定 Lai.Fu → Yggdrasill 免密 SSH key · ✅ DONE
- **描述：** 把 Lai.Fu 的 public key 加到 Yggdrasill `~/.ssh/authorized_keys`，讓 `activate-failover.sh` / `handback.sh` 能免密 SSH 喚醒/drain。
- **DoD：**
  - 在 Lai.Fu 執行 `ssh -o BatchMode=yes -p 19522 ken@192.168.81.195 'id'` → `uid=1000(ken)` ✅（2026-06-02 驗證）
- **依賴：** T11
- **Notes：** Lai.Fu 的 public key（`ken@openclaw`）已加入 Yggdrasill `~/.ssh/authorized_keys`。腳本已加入 `YGGDRASILL_SSH_PORT=19522`。發現 Wall.E 的現有 key 有 `command="scp -t /backup/..."` 備份限制，**Wall.E → Yggdrasill 只能做備份用途**，failover 操作由 Lai.Fu 執行。

### T11 — 確認/修正 Yggdrasill SSH port 與連線參數 · ✅ DONE
- **描述：** Yggdrasill 的 SSH port 目前在 README/腳本中為「假設 22」。需實機確認真實 port、是否有 Tailscale IP，並更新腳本與文件。
- **DoD：**
  - SSH port = **19522**（已確認）✅
  - 腳本 `activate-failover.sh`、`handback.sh` 已加入 `YGGDRASILL_SSH_PORT="19522"` ✅
  - README 節點規格表已更新（見 README v0.1.2）✅
  - Tailscale IP：**未加入 Tailscale**（目前只用 LAN 192.168.81.195）
- **依賴：** 無
- **Notes：** Wall.E 已有 Yggdrasill key 但受限 `command="scp -t /backup/Wall.E-hermes_81.166/"` 備份限制。Yggdrasill 未加 Tailscale，failover 走 LAN — 需注意 LAN 中斷風險（見 README Disaster Scenarios）。建議未來 T11.1：將 Yggdrasill 加入 Tailscale。

### T12 — 端到端 failover 演練（verification matrix） · 🔲 TODO
- **描述：** 執行一次完整、可重複的 failover → handback 演練，驗證整條鏈路。
- **DoD（verification matrix，全部 PASS）：**
  1. 在 Wall.E `systemctl --user stop hermes-gateway.service` 模擬掛點。
  2. ~90s 內 Lai.Fu watchdog 連續 3 次失敗 → `journalctl --user -t hermes-watchdog` 出現 `FAILOVER ACTIVATED`。
  3. lockfile `/run/user/$(id -u)/laifu-active` 在 Lai.Fu 出現。
  4. Lai.Fu Telegram bot 發出 failover 通知給 Ken。
  5. Yggdrasill gateway 變為 `active`（被 SSH 喚醒）。
  6. 還原 Wall.E gateway → Lai.Fu 偵測恢復 → `handback.sh` 執行。
  7. Yggdrasill gateway 變回 `inactive`（drained）。
  8. failover 期任務 SQL dump 出現在 Wall.E `~/failover-tasks/`。
  9. lockfile 已移除。
  10. Ken 收到 handback 完成通知。
- **依賴：** T08, T09, T10, T11
- **Notes：** 演練前先公告 Ken（會切換對外 bot 身分）。把本演練腳本化（可放 `shared/scripts/`，關聯 T17）。結果寫回本 Notes。

### T13 — handback 對稱 debounce（連續 3 次成功才交還） · 🔲 TODO
- **描述：** 目前 handback 只要一次健康探測就 drain Yggdrasill；Wall.E flapping 時會反覆切換。改為連續 N 次（建議 3）成功才 handback。
- **DoD：**
  - `watchdog.sh`/`handback.sh` 新增成功計數（對稱於 `FAIL_THRESHOLD`）。
  - 模擬 Wall.E flapping（健康→掛→健康）不會在單次成功就交還。
  - README「Handback 規格」與「Known Limitations / Future Work」對應更新（R1）。
- **依賴：** T12
- **Notes：** 見 README「Future Work — handback 對稱 debounce」。需新增類似 `/tmp/walle-success-count` 計數檔，健康歸零邏輯要對稱。

### T14 — 第二監測者：Yggdrasill 也監測 Lai.Fu · 🔲 TODO
- **描述：** 消除單一守門人單點失效（Lai.Fu 掛了沒人觸發 failover）。讓 Yggdrasill 輕量探測 Lai.Fu（甚至互備探測 Wall.E）。
- **DoD：**
  - Yggdrasill 有一支輕量探測（不跑 agent loop）監測 Lai.Fu 存活。
  - Lai.Fu 掛掉時，Yggdrasill 能 alert Ken（至少通知，不一定自動接管）。
  - 機制與職責邊界寫入 README。
- **依賴：** T08, T10
- **Notes：** 見 README「Future Work — 第二監測者」。注意避免兩個監測者同時觸發造成 split-brain，需設計仲裁或角色分工。

### T15 — Approach D：Lai.Fu 透過 SSH kanban 委派任務給 Wall.E · 🔲 TODO
- **描述：** 讓 Lai.Fu 能把收到的任務透過 SSH 寫入 Wall.E 的 kanban，由 Wall.E 的 agent loop 執行（Lai.Fu 自己不跑 agent）。
- **DoD：**
  - 定義 Lai.Fu → Wall.E 的任務委派介面（SSH 指令或 hermes CLI）。
  - 任務只寫進 **Wall.E** 的 kanban.db（Lai.Fu 不寫自己的，符合 R5）。
  - 端到端：Lai.Fu 收任務 → Wall.E 執行 → 結果回報。
- **依賴：** T06
- **Notes：** ⚠️ 需嚴守 R5（Pi 2 不進 write path——這裡寫的是 Wall.E 的 DB，可接受）。`data/signals/` 目錄已存在但未被任何腳本使用，可能是為此預留的 signal 通道——**設計前先釐清 `data/signals/` 用途**並決定是否採用。此任務尚屬探索性，實作前建議 dual-brain 審查。

### T16 — 補齊 `wall-e/` 內容（健康檢查腳本 + failover-tasks/） · 🔲 TODO
- **描述：** `wall-e/` 目前為空。補上主腦端健康檢查腳本，並確立 `~/failover-tasks/` 接收 handback dump 的約定。
- **DoD：**
  - `wall-e/` 含可在 Wall.E 跑的健康自檢腳本（gateway / kanban / agent loop 狀態）。
  - Wall.E 上 `~/failover-tasks/` 存在（handback 的 scp 目標，見 README Handback 步驟 4）。
  - README「檔案結構」把 `wall-e/ (TBD)` 更新為實際內容。
- **依賴：** 無
- **Notes：** 見 README「Future Work — wall-e/ 與 shared/scripts/ 落地」。

### T17 — 補齊 `shared/scripts/` 跨節點共用工具 · 🔲 TODO
- **描述：** `shared/scripts/` 目前為空。放跨節點共用工具（如統一的健康探測函式、failover 演練腳本、log 收集）。
- **DoD：**
  - `shared/scripts/` 至少含一支被其他節點實際引用的共用工具。
  - README「檔案結構」更新 `shared/scripts/ (TBD)` 為實際內容。
- **依賴：** 無（T12 的演練腳本可落腳於此）
- **Notes：** 候選：failover drill 腳本（關聯 T12）、集中式 log/指標收集（README「Future Work — 可觀測性」）。

---

## 4. 已知阻塞與未決問題（BLOCKED / OPEN QUESTIONS）

| 編號 | 問題 | 影響任務 | 狀態 |
|---|---|---|---|
| Q1 | Yggdrasill 真實 SSH port 未確認（README 標「假設 22」） | T07, T10, T11 | ✅ 已解決：port=19522 |
| Q2 | Yggdrasill 是否已加入 Tailscale、其 TS IP 為何 | T10, T11 | ✅ 已解決：未加入 Tailscale，走 LAN |
| Q3 | `data/signals/` 目錄用途未定義（無腳本引用） | T15 | 待釐清 |
| Q4 | failover 對使用者非透明（切到 Yggdrasill 是另一個 bot 身分） | （設計取捨） | 已知限制，見 README「Future Work — 半透明 failover」 |

> 目前 **無真正 BLOCKED 的任務**（沒有任務因外部不可控因素完全卡死）。Q1/Q2 由 T11 解決，T11 無前置依賴可立即執行。

---

## 5. Session 交接（HANDOFF）

### Current Topology State（每個 session 開始前核對）

| 檢查項目 | 預期狀態 | 最後驗證 |
|---|---|---|
| Wall.E hermes-gateway.service | **active** | 2026-06-02 |
| Lai.Fu hermes-watchdog.timer | **active (waiting)** | 2026-06-02 |
| Yggdrasill hermes-gateway.service | **inactive / disabled** | 待確認（T08 前） |
| Lai.Fu → Yggdrasill SSH (port 19522) | **key auth OK** | 2026-06-02 |
| Lai.Fu fail count (`/tmp/walle-fail-count`) | **0** | 2026-06-02 |
| Lai.Fu lockfile (`/run/user/*/laifu-active`) | **不存在** | 2026-06-02 |

### Forbidden States（絕對不允許的狀態）

- ❌ Wall.E gateway active **且** Yggdrasill gateway active（雙主腦）
- ❌ Lai.Fu 執行任何資料庫寫入
- ❌ 任意節點使用其他節點的 bot token
- ❌ kanban.db 放在網路檔案系統上共享

---

### 上一個 session 摘要（2026-06-02）
- 完成 T01–T06：repo 建立、三層架構（dual-brain 審查）、canonical README v0.1.1、Lai.Fu watchdog 全套腳本實作並部署、Lai.Fu→Wall.E SSH 驗證。
- 建立 tasks.md v1.1（Opus 4.8 + GPT-5.5 雙大腦協作，R1-R13 規則）。
- 完成 T11：確認 Yggdrasill SSH port=19522（非假設的 22），Tailscale 未加入。
- 完成 T10：Lai.Fu → Yggdrasill:19522 免密 SSH key 設定，`id` 驗證 ✅。
- 更新腳本 `activate-failover.sh` / `handback.sh`，加入 `YGGDRASILL_SSH_PORT=19522`。
- 發現：Wall.E 已有 Yggdrasill key 但受 `command="scp -t /backup/..."` 限制（備份用途）。
- **目前狀態：** T10/T11 完成；T07（clone to Yggdrasill）、T08（gateway standby）、T09（獨立 token）待執行。

### Next recommended action（下一個 session 從這裡開始）
1. **T07**：clone hermes-mesh 到 Yggdrasill（`sshpass -p ejis93jp6 ssh ken@192.168.81.195 -p 19522 'git clone https://github.com/Birdman1972/hermes-mesh.git'`）
2. **T08**：在 Yggdrasill 安裝 hermes gateway 並設 standby（disabled + stopped）
3. **T09**：為 Yggdrasill 申請獨立 Telegram/Discord bot token 並設定
4. **T12**：端到端 failover 演練（verification matrix，9 項 PASS）
5. **T13**：handback 對稱 debounce（3 次連續成功才交還）

### 接手前必讀
- 本檔案 §0（30 秒簡報）+ §1（通用規則 R1–R9）。
- `README.md`——尤其「Operational Runbook」（日常確認 / 手動 failover+handback / 故障排查）與「Disaster Scenarios」。
- 操作 Yggdrasill 前先讀 `yggdrasill/standby.md`。

---

## 6. 變更紀錄（本檔案）

> RULE R8：每次實質修改 tasks.md 都在此新增一列。

| 日期 | 版本 | 變更 | 作者 |
|---|---|---|---|
| 2026-06-02 | v1.0 | 初版：建立持久化任務記憶。記錄 DONE T01–T06、TODO T07–T17、通用規則 R1–R9、開放問題 Q1–Q4、Session 交接區。對應 README v0.1.1。 | Ken + Claude（Opus 4.8 起草） |
| 2026-06-02 | v1.1 | 補充 R10–R13（hard invariant + 操作安全規則）、Current Topology State、Forbidden States（GPT-5.5 gap review 結果）。 | Ken + Claude |
| 2026-06-02 | v1.2 | T10/T11 標記 DONE（含 DoD evidence）、Q1/Q2 關閉、session handoff 更新為本日進度。 | Ken + Claude |
