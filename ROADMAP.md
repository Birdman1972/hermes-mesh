# hermes-mesh 架構演進 Roadmap

> **文件定位**：架構決策與演進路線，非操作手冊。
> 操作手冊（安裝、failover、handback、故障排查）見 [README.md](./README.md)。
> 任務進度追蹤見 [tasks.md](./tasks.md)。

| 項目 | 值 |
|---|---|
| 版本 | v0.1.0 |
| 日期 | 2026-06-02 |
| 依據 | Opus 4.7 + GPT-5.5 雙大腦架構研究 + Ken PM 概念討論 |

---

## §1 現況定錨

hermes-mesh 目前是一套 **witness-arbitrated 冷備援（cold standby）**：

| 角色 | 節點 | 平時狀態 |
|---|---|---|
| 主腦 PRIMARY | Wall.E | gateway **active**，對外服務 |
| 見證/仲裁 WATCHDOG | Lai.Fu (Pi 2) | 每 30s 探測 Wall.E，觸發 failover |
| 備援腦 STANDBY | Yggdrasill | gateway **disabled + stopped**，等待喚醒 |

節點規格、failover/handback 流程、split-brain 防護細節 → 見 [README.md](./README.md)。

---

## §2 備援光譜：從冷備援到雲端多活

```
冷備援(現在) ──→ 熱備援 ──→ 半多活 ──→ 全多活(雲端式)
   省心 ←────────────────────────────────→ 高效但複雜
```

### 冷備援（Cold Standby）——現況

- **運作**：Yggdrasill 平時完全關機（disabled+stopped）。Wall.E 掛掉 → Lai.Fu 探測失敗 3 次（~90s）→ SSH 喚醒 Yggdrasill → Yggdrasill 開機、載入設定、連線 Telegram。
- **切換速度**：分鐘級（含開機時間）。
- **平時成本**：Yggdrasill 零耗電、零 token。
- **split-brain 風險**：低（Yggdrasill 關著，要雙活需跨越「開機」門檻）。
- **缺點**：空窗期長；Yggdrasill 設定是否正常無人天天驗證，真要切換時才發現壞了。

### 熱備援（Warm Standby）——中期目標

- **運作**：Yggdrasill 平時已預熱（程式跑著、設定載入、連線建立），但卡在最後一道「閘門」不對外服務。failover 時只需打開閘門，幾秒內接手。
- **切換速度**：秒級。
- **平時成本**：Yggdrasill 一直開著，多耗電；**若預熱連著 LLM 要小心燒 token**。
- **split-brain 風險**：**變高**——Yggdrasill 已經在跑，誤開閘比冷備援更容易發生。
- **前提**：必須先完成 §5 的 lease gate，否則熱備援反而更危險。

### 半多活（Semi Active/Active）——遠期可評估

- **運作**：讀取類請求（查詢/狀態確認）可由多節點分擔；寫入/任務執行仍由單一主腦負責。需要輕量共享層（如 Redis）協調路由。
- **切換速度**：毫秒級。
- **平時成本**：所有節點都在跑，成本倍增。
- **split-brain 風險**：中（寫入仍單一，風險限縮在讀取側）。
- **前提**：hermes 需支援讀寫分離語義；共享路由層需額外維護。

### 全多活（Full Active/Active，雲端式）——需查證 hermes 能力

- **運作**：所有節點同時服務所有請求，前面一個 Load Balancer 分流。
- **切換速度**：毫秒級，無感知。
- **平時成本**：最高（多台同時跑）。
- **split-brain 風險**：最高，需嚴格的一致性保障。
- **前提**：見 §3、§4。

---

## §3 雲端多活的三根柱子

雲端能做到全多活，是因為同時滿足三個前提。hermes-mesh 目前一根都沒有：

| 柱子 | 雲端怎麼做 | hermes-mesh 現況 | 補的代價 |
|---|---|---|---|
| **1. 共享帳本** | 所有節點讀寫同一個資料庫（PostgreSQL + replication） | ❌ 各節點本地 SQLite，永不共享（D1） | 換掉 SQLite → 共享 DB，解決 write conflict 與去重；工程量大 |
| **2. 單一對外身分** | 一個網址/bot token，前面 Load Balancer 分流 | ❌ 各節點獨立 bot token（D4），對外是不同身分 | 統一 bot token + proxy 層；或改用 webhook 模式集中接收再分發 |
| **3. 無狀態工人** | 任一節點做到一半掛掉，另一台可無縫接手（任務狀態存共享 DB） | ❓ 取決於 hermes 設計；LLM agent loop 多半是有狀態的 | hermes 不支援則需在外面包 stateless wrapper |

**結論**：缺任何一根柱子，硬要多活就會：任務重複執行、Ken 同時收到兩個機器人回話、對話歷史分裂。這就是 R10「只能一台」的根本原因——不是笨，是務實妥協。

---

## §4 關鍵約束：hermes 是第三方工具

hermes（v0.15.1）在 hermes-mesh 中當**黑盒子**使用，其原始碼不在本 repo。

多活與否，最終取決於 hermes 引擎本身是否支援：

| 待查證項 | 查證方式 | 影響 |
|---|---|---|
| hermes 支援多 worker 共吃同一個任務佇列嗎？ | `hermes --help` 或查 hermes 官方文件/OSS repo | 若支援 → 半多活可行 |
| hermes gateway 可以用 webhook 模式（而非 long polling）嗎？ | 同上 | 若支援 → 統一對外身分可行 |
| hermes 的 agent loop 是無狀態的嗎？ | 同上 | 若是 → 全多活柱子 3 可補 |
| hermes 支援指向外部共享 DB 嗎？ | 同上 | 若支援 → 全多活柱子 1 可補 |

> ⚠️ **在查清楚這四項之前，不應該基於「hermes 可能支援多活」做任何架構決策。**

---

## §5 最高優先決策：R10 從文件規則 → 系統強制

> 這比目錄整理、比升熱備援都更優先。——GPT-5.5 adversarial review 結論

**現狀**：R10「任何時刻最多只有一個 gateway active」目前只是 tasks.md 裡的文字規定，依靠：
- Yggdrasill 預設 disabled（人工配置）
- lockfile `/run/user/*/laifu-active`（Lai.Fu 本地，重啟消失）
- 90s debounce（降低誤判）
- 人工規則守則

這是 **best-effort**，不是 **hard invariant**。若 Lai.Fu 到 Wall.E 的路徑斷了但 Wall.E 仍能服務，Lai.Fu 會誤判並喚醒 Yggdrasill → 雙 active → split-brain。

**目標**：升級成 **gateway 啟動條件（lease gate / fencing）**：

```
目前（best-effort）：
  Lai.Fu 判斷 Wall.E 掛了 → SSH start Yggdrasill

目標（hard invariant）：
  Lai.Fu 判斷 Wall.E 掛了
    → 進入 transitioning 狀態，拒絕 Wall.E 續租
    → 等 TTL + grace（Wall.E guard 若正常會自停）
    → 確認 Wall.E 已停 → 才 SSH start Yggdrasill
```

**參考典範**：Kubernetes Lease（leader election）、Pacemaker STONITH/fencing、Consul session lock TTL。

**為什麼比熱備援更優先**：
- 冷備援下，R10 破功的後果是「暫時雙活 → 手動修復」。
- 熱備援下，Yggdrasill 已預熱，誤開閘門比冷備援容易一百倍——沒有 lease gate，熱備援反而更危險。
- 任何往多活演進的路線，都需要這道門先在。

**後續任務**：待實作，需獨立 DoD + 雙大腦稽核（列為 T18 候選）。

---

## §6 建議路線（PM 視角）

```
Phase 0（現在進行）：完成冷備援基礎
  T08 Yggdrasill hermes 安裝 standby
  T09 獨立 bot token
  T12 端到端 failover 演練

Phase 1（近期）：把冷備援做「硬」
  T18 lease gate：R10 從文件規則 → gateway 啟動條件
  T13 handback 對稱 debounce

Phase 2（中期，視需求決定）：評估熱備援
  前提：Phase 1 完成
  前提：查清楚 hermes 多活能力（§4 四項）
  若 hermes 不支援多活 → 熱備援是終點，不必再往前
  若 hermes 支援 → 可設計共享資料庫 + 統一身分方案

Phase 3（遠期，需求驅動）：全多活
  前提：Phase 2 完成且 hermes 原生支援
  前提：使用量真的大到需要水平擴展
  否則：過度設計，不划算
```

> 「好架構 = 符合你真實需求的最簡架構，不是最炫的架構。」

---

## §7 文件與 repo 分散化方向

> 這是獨立 track，不影響 §6 的執行路線。

**問題**：目前 README.md（463 行）+ tasks.md（305 行）把三節點全部包山包海。任何 AI session 或新人接手都必須讀完整份才能上工，改一個節點容易動到另一個節點的描述。

**方向**：節點自治單元 + 細腰共用契約（Node-Autonomous Cells + Thin-Waist Shared Contract）

```
hermes-mesh/
├── README.md         ← 瘦身：只留地圖（拓樸圖 + 索引）
├── ROADMAP.md        ← 本文件
├── CONTRACT.md       ← 唯一跨節點硬契約（R10/R4/R5/port/SSH 矩陣）
├── decisions/        ← ADR：D1–D6 各一檔
├── wall-e/           ← 自治：README + TASKS + config/ + scripts/
├── lai-fu/           ← 自治：README + TASKS + config/nodes.env（★解硬編碼）
├── yggdrasill/       ← 自治：README + TASKS + config/ + scripts/
└── shared/           ← 只放 ≥2 節點真正引用的（health-probe、drills）
```

**落地順序**（低風險優先）：
1. 先拆 docs（頂層 README 瘦身 + 各節點 README + CONTRACT.md）— 零風險，立即可做
2. 抽 `lai-fu/config/nodes.env`（解三支腳本的 host/port 硬編碼）— 改動小，立即見效
3. tasks.md 拆 per-node TASKS + 保留精簡全局索引
4. `shared/lib/` 等 T14（第二監測者）真的需要時再做

**原則**：shared/ 只放「已被 ≥2 節點實際引用」的東西；不為單一使用點建抽象（YAGNI）。

**風險**：
- **契約漂移**：分散後跨節點值（port、SSH 矩陣）可能在多份文件不一致 → 緩解：所有跨節點值只存 CONTRACT.md，各節點文件只引用不複製。
- **AI 冷啟動失靈**：tasks.md 拆掉後需保留一個極短全局 index → 頂層 README 充當地圖。
- **過早抽象**：三節點、六支腳本，硬套架構模式可能比集中式更難維護 → 先拆文件（低風險），腳本結構等規模擴大再動。

---

## §8 開放決策（待 Ken 拍板）

以下決策尚未定案，列出雙大腦共識建議供 Ken 參考：

| 決策 | 雙大腦建議 | 選項 |
|---|---|---|
| **Split-brain lease gate 優先嗎？** | ✅ 是，比其他事都優先（GPT-5.5 強調） | A) 是，列為 T18 立即排入 Phase 1 / B) 暫緩，Phase 0 完成再議 |
| **目標備援等級** | 短期冷備援做穩，中期評估熱備援（前提是 §4 查清楚） | A) 冷備援即終點 / B) 中期升熱備援 / C) 查清楚 hermes 能力後再定 |
| **目錄要不要重組** | 先拆 docs，腳本維持現狀 | A) 扁平結構（wall-e/ lai-fu/ 放根層，Opus 建議）/ B) nodes/ 子目錄（GPT-5.5 建議，更整齊但改動多）|
| **hermes 多活能力查證** | 應該查，但不急於現在 | A) 現在就 SSH 到 Wall.E 查 hermes --help / B) Phase 0 完成後再查 |

---

## §9 典範速查表

| 典範 | 借鑑點 | 局限 |
|---|---|---|
| **Patroni**（PostgreSQL HA） | witness 仲裁者獨立於資料平面；standby disabled-by-default；promotion/demotion protocol | 假設資料複製與 DCS，不適合直接套 SQLite 不共享場景 |
| **Pacemaker + qdevice** | STONITH fencing 概念；quorum witness → 支持 T14 第二監測者 | 對三台家用節點太重，Pi 2 不適合作控制平面 |
| **Ansible inventory/host_vars** | per-host 差異管理；group_vars 共用行為；「只抽真正共用」哲學 | 變數 precedence 複雜，不應讓 Ansible 成為 runtime truth |
| **Kubernetes Lease** | leader election lease gate；owner + TTL + renewal 模型 | K8s API 對邊緣三節點太重，但 lease 模式本身可獨立實作 |
| **Consul session lock** | TTL 到期自動釋放；service/hermes-gateway/leader 單 key leader lock | 引入 Consul 自己也要 HA，可能成為新單點 |
| **ADR（Architecture Decision Records）** | 每個決策獨立一檔，節點 session 只讀相關 ADR | — |
| **Terragrunt monorepo** | 「只抽真正共用，容許重複」哲學；避免為單一使用點建共用層 | — |

---

## §10 版本歷史

| 日期 | 版本 | 變更 | 作者 |
|---|---|---|---|
| 2026-06-02 | v0.1.0 | 初版：依據 Opus 4.7 + GPT-5.5 雙大腦研究 + Ken PM 概念討論建立。涵蓋備援光譜（冷/熱/半多活/全多活）、雲端多活三根柱子、hermes 第三方約束、lease gate 優先決策、文件分散化方向、開放決策清單、典範速查表。 | Ken + Claude（Sonnet 4.6 整合） |
