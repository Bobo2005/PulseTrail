# PulseTrail — UI/UX Design System Specification

## 1. Design Philosophy: "High-Frequency Telemetry Terminal"

PulseTrail is built for **Reactive Omni Track 1 (*Every Second Counts*)**. The interface must feel like an institutional high-frequency algorithmic execution terminal (inspired by Hyperliquid, Bloomberg Terminal, and Linear)—communicating **sub-second precision, autonomous safety, and crystal-clear stage progression**.

### Core Visual Principles
1. **Zero Ambiguity Under Stress:** When a memecoin is pumping or crashing, the trader must immediately see: *Current Price*, *High-Water Mark*, *Effective Adaptive Trail*, and *Active Stage (0–3)*.
2. **Live Cross-Chain Telemetry:** Visually bridge **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)** with real-time heartbeat indicators, block latency counters (`~200ms Base` $\rightarrow$ `~1.0s Reactive`), and clickable explorer badges.
3. **Proactive Risk Transparency:** Surface pool liquidity warnings, transfer-tax estimates, and honeypot simulation results *before* the user signs a transaction.

---

## 2. Color Palette & Semantic Tokens

### 2.1 Surface & Background Tokens (Dark-First Mode)
| Token | Hex Code | Usage |
| :--- | :--- | :--- |
| `--bg-canvas` | `#07090E` | Primary app background (Deep Obsidian) |
| `--bg-surface-1` | `#0D111A` | Primary cards, position panels, strategy builder |
| `--bg-surface-2` | `#141B29` | Hover states, input fields, secondary containers |
| `--bg-glass` | `rgba(13, 17, 26, 0.78)` | Sticky header & floating telemetry HUD (`backdrop-filter: blur(12px)`) |
| `--border-subtle` | `#1E293B` | Default card & table borders (`1px solid`) |
| `--border-focus` | `#00F0FF` | Active input / selected stage border |

### 2.2 Brand & Accent Tokens
| Token | Hex Code | Usage |
| :--- | :--- | :--- |
| `--accent-pulse` | `#00F0FF` | Primary brand cyan — Reactive VM pulse, active HWM line |
| `--accent-reactive` | `#7C3AED` | Reactive Mainnet (`1597`) badge & cross-chain callback indicator |
| `--accent-base` | `#0052FF` | Base Mainnet (`8453`) network badge |

### 2.3 Semantic Status & Stage Tokens
| Token | Hex Code | Meaning in PulseTrail |
| :--- | :--- | :--- |
| `--status-profit` | `#10B981` | Emerald Green — Profit activation cleared, HWM ratcheting upward |
| `--status-volatility` | `#F59E0B` | Amber Gold — High volatility detected, adaptive trail widened |
| `--status-trigger` | `#EF4444` | Crimson Red — Stop floor breached / stage partial exit triggered |
| `--status-dormant` | `#64748B` | Slate Gray — Stage 0 (Waiting for profit activation threshold) |
| `--text-primary` | `#F8FAFC` | Primary headings and numerical readouts |
| `--text-secondary` | `#94A3B8` | Labels, descriptions, and secondary metadata |
| `--text-muted` | `#475569` | Disabled states, timestamps, hash prefixes |

---

## 3. Typography Scale

- **Primary UI Font (`--font-sans`):** `'Inter'`, `'Plus Jakarta Sans'`, system-ui, sans-serif.
- **Telemetry & Numerical Font (`--font-mono`):** `'JetBrains Mono'`, `'Fira Code'`, monospace (Mandatory `font-variant-numeric: tabular-nums` on all prices, percentages, gas counters, and tx hashes).

| Style | Size / Line Height | Weight | Font Family | Usage |
| :--- | :--- | :--- | :--- | :--- |
| **Hero Metric** | `2.25rem` (`36px`) / `1.1` | `700` | `JetBrains Mono` | Live Token Price & High-Water Mark readout |
| **Section Header (H1)** | `1.5rem` (`24px`) / `1.25` | `600` | `Inter` | Panel titles ("Create Trailing Position") |
| **Card Title (H2)** | `1.125rem` (`18px`) / `1.35` | `600` | `Inter` | Sub-sections ("Multi-Stage Ladder", "Risk Shield") |
| **Body Default** | `0.875rem` (`14px`) / `1.5` | `400` | `Inter` | Standard controls, tooltips, table cells |
| **Telemetry Micro** | `0.75rem` (`12px`) / `1.4` | `500` | `JetBrains Mono` | Tx hashes, block numbers, bps badges, latency tags |

---

## 4. Core UI Components & Interactive Patterns

### 4.1 Dual-Chain Telemetry Header Bar
- **Left:** PulseTrail logo with animated cyan radar pulse icon.
- **Center:** Dual live status pills:
  - `Base Mainnet (8453) • 200ms • Connected` (Blue pulse dot)
  - `Reactive Mainnet (1597) • 1.0s • Subscribed` (Purple/Cyan pulse dot)
- **Right:** Contract Gas Reserve Health (`Callback Proxy Reserve: 0.05 ETH | Reactive Reserve: 15 REACT`) + Wallet Connect button.

### 4.2 Interactive Price & Trail Visualizer (The "Ratchet Chart")
A real-time chart showing four horizontal/stepped price lines:
1. **Current Pool Price (Solid White/Cyan Line)** — Updates on every `Sync` event.
2. **Entry & Activation Threshold (Dashed Emerald Line)** — Shows exact price needed to unlock Stage 1.
3. **High-Water Mark (Stepped Neon Cyan Line)** — Only steps upward; visually demonstrates the ratchet effect.
4. **Adaptive Trailing Trigger (Shaded Amber/Crimson Band)** — Dynamically expands downward when volatility spikes and tightens when volatility cools.

### 4.3 4-Stage Ladder Progress Stepper
A horizontal 4-node state machine visualizer inside every active position card:
- **Node 0: Dormant (Pre-Activation)** — Displays `+15% Target ($1.15)` and optional Hard Floor (`$0.85`).
- **Node 1: Stage 1 (40% Exit)** — Shows Base Trail (`8%`) + Volatility Add-on (`+2.4%`) = `10.4% Effective Trail`.
- **Node 2: Stage 2 (30% Exit)** — Shows Base Trail (`6%`) + Volatility Add-on (`+2.4%`) = `8.4% Effective Trail`.
- **Node 3: Stage 3 (30% Final Closeout)** — Shows Base Trail (`5%`) + Volatility Add-on (`+2.4%`) = `7.4% Effective Trail`.

### 4.4 Pre-Flight Security & Liquidity Shield Card
Displayed automatically when a user pastes a token or pair address:
- **Pool Reserve Depth Check:** Green check if position `< 3%` of pool reserves; Amber warning if `3%–10%`; Red alert if `> 10%` ("High Price Impact: Recommend 40/30/30 split").
- **Honeypot & Tax Dry-Run Badge:** Simulates `swapExactTokensForTokensSupportingFeeOnTransferTokens` via `eth_call`. Displays estimated transfer tax (`Buy: 0% | Sell: 2.0% | Honeypot Check: PASSED`).

### 4.5 Cross-Chain Proof & Latency Explorer Table
A dedicated bottom drawer / tab designed explicitly for Hackathon Judges (**Criterion 1: Execution**):
- Lists every executed stage with 3 linked columns:
  1. **Origin Event (Base `8453`):** `Sync` Tx Hash (`basescan.org/tx/...`) + Timestamp $T_0$.
  2. **Reactive Brain (Reactive `1597`):** `react()` Tx Hash (`reactscan.net/tx/...`) + Timestamp $T_1$.
  3. **Destination Swap (Base `8453`):** `executeStageExit()` Tx Hash (`basescan.org/tx/...`) + Timestamp $T_2$.
- **End-to-End Latency Badge:** Highlights $\Delta T = T_2 - T_0$ (e.g., `1.8s Full Cross-Chain Loop`).

---

## 5. Layout Grid & Responsive Breakpoints

- **Desktop (`>= 1280px`):** 12-column CSS Grid (`max-width: 1440px`, `gap: 20px`, `padding: 24px`).
  - **Left Column (5 cols):** Strategy Configuration & Pre-Flight Risk Shield.
  - **Right Column (7 cols):** Live Ratchet Visualizer, Active Positions State Machine, and Cross-Chain Latency Proof Log.
- **Tablet / Compact (`768px – 1279px`):** Stacked 2-column layout.
- **Mobile (`< 768px`):** Single-column vertical feed with sticky bottom action bar ("Create Trailing Stop" / "Emergency Withdraw").

