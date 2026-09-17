# Ptr Strategy EA (v2.00)

[![Platform](https://img.shields.io/badge/Platform-MetaTrader%204%20(MT4)-blue.svg)](https://www.metatrader4.com/)
[![Language](https://img.shields.io/badge/Language-MQL4%20(%23property%20strict)-green.svg)](https://docs.mql4.com/)
[![Build](https://img.shields.io/badge/Build-0%20errors%20%7C%200%20warnings-brightgreen.svg)]()
[![Status](https://img.shields.io/badge/Status-Verified%20%26%20Active-success.svg)]()

An automated Expert Advisor (EA) developed for **MetaTrader 4 (MQL4)**, strictly built around Peter Johansson's (`pjohans1`) proprietary 4-indicator trading system and settings specification (`original/Ptr Settings.pdf`).

---

## 1. Strategy Overview & Core Systems

The EA provides 3 switchable, verified operational modes selectable directly in properties without recompilation:

### Mode 1: `ENTRY_MEGA_PLUS_BANDS` (Primary Strategy — Confirmed Default)
- **Primary Trigger:** MegaTrend fast Hull MA (48) crosses slow Hull MA (78) in `Ptr Mega Trend.mq4` (`MODE_LWMA`, `PRICE_CLOSE`).
- **Confirmation:** Yellow and Green have crossed or aligned past the White Dotted line within a lookback window (`InpConfirmLookbackBars`, default: 8 bars).
- **Confirmation Methods (`InpBandConfirmMode`):**
  - `BAND_CONFIRM_ANY` *(Default)*: Accepts either outer band extreme pierce or TMA center cross.
  - `BAND_CONFIRM_OUTER_BANDS`: Yellow & Green outer bands dip below Lower White band (BUY) or push above Upper White band (SELL).
  - `BAND_CONFIRM_TMA_CENTERS`: Yellow & Green TMA centers cross/align past White TMA center.
  - `BAND_CONFIRM_PRICE_PIERCE`: Price High/Low pierces the White Dotted line.
- **Timing:** Executes strictly on the opening of the candle following confirmation (`IsNewBar()`), adhering to Peter's rule: *"enter on the following opening candle"*.

### Mode 2: `ENTRY_YELLOW_ONLY` (Peter's Alternate System)
- Client's exact words: *"Eliminate completely the MegaTrend and arrow lines and the stochastic completely and ONLY USE YELLOW CROSSES OF WHITE DOTTED LINE. Also forget about the GREEN line."*
- **Trigger:** Yellow crossing the White Dotted line directly!
  - Buy when Yellow lower band crosses / dips below Lower White band, or Yellow TMA crosses up through White TMA.
  - Sell when Yellow upper band crosses / pushes above Upper White band, or Yellow TMA crosses down through White TMA.
- Verified on GBPCHF H1: **21 executed trades** across historical real tick testing.

### Mode 3: `ENTRY_MEGA_ONLY` (Pure MegaTrend 48/78 Cross)
- Client's exact words: *"we take trades upon crosses of both 78 and 48 MegaTr. Lines"*.
- Pure crossover system of Fast HMA (48) and Slow HMA (78) without band filter constraints.
- Verified on EURCHF H4: **29 executed trades**.

---

## 2. Indicator Suite Specifications

All indicators are integrated via `iCustom()` matching exact source parameter orders and buffer definitions:

| Indicator File | Indicator Role | Confirmed Parameters (`Ptr Settings.pdf`) | Buffer Mappings in EA |
|---|---|---|---|
| `Ptr Mega Trend.mq4` | Primary crossover trigger | Fast HMA `48`, Slow HMA `78`, Linear Weighted (`MODE_LWMA`), Close price | Buffer `2` (`HMA` line) |
| `Yellow Ptr Arslan.mq4` | Fast non-repainting TMA band | Half Length `21`, TimeFrame `60` (H1), Close price, Deviation `1.8`, Repaint `False` | Buffer `1` (Upper Band), Buffer `2` (Lower Band), Buffer `0` (Center TMA) |
| `Norepaint zone 3 green.mq4` | Slow non-repainting TMA band | Half Length `40`, TimeFrame `60` (H1), Close price, Deviation `1.8`, Repaint `False` | Buffer `1` (Upper Band), Buffer `2` (Lower Band), Buffer `0` (Center TMA) |
| `White Ptr Arslan.mq4` | Anchor confirmation band | Half Length `32`, Period `100`, Multiplier `2.8`, Weighted price (`pr_weighted`) | Buffer `3` (Upper Band), Buffer `4` (Lower Band), Buffer `0` (Center TMA) |

> **Note:** Indicator filenames in MT4's `Indicators\` folder must match exactly:
> - `#define IND_MEGA   "Ptr Mega Trend"`
> - `#define IND_YELLOW "Yellow Ptr Arslan"`
> - `#define IND_GREEN  "Norepaint zone 3 green"`
> - `#define IND_WHITE  "White Ptr Arslan"`

---

## 3. Exit & Risk Management

Client's rule: *"I will study harder later... leave this open... set it in properties at a later date."*

- `InpExitMode`:
  - `EXIT_FIXED_PIPS` *(Default)*: Fixed Stop Loss and Take Profit in pips (`InpTakeProfitPips = 50`, `InpStopLossPips = 50`), automatically normalized for 3/5-digit brokers.
  - `EXIT_STOP_AND_REVERSE`: Holds position until an opposite confirmed signal occurs, then automatically closes and reverses.
- `InpTrailingStopPips`: Optional trailing stop in pips (disabled if set to `0`).
- `InpMaxSpreadPoints`: Max allowable spread filter (default: 30 points).

---

## 4. Optional Filters (Disabled by Default)

Cleanly isolated as external toggles, off by default so they never block Peter's strategy unless explicitly enabled:
- `InpUseRealStochFilter` (`false`): Genuine built-in Stochastic(32,5,10) overbought (90) / oversold (10) lookback check.
- `InpUseHmaStochFilter` (`false`): %K extension check applied to the HMA series itself.
- `InpUseDivergenceFilter` (`false`): Price versus Stochastic swing-based divergence detection.

---

## 5. Live Chart Dashboard

When attached to a chart, the EA displays a real-time status overlay:
- Active Strategy Mode & Exit Method
- Live MegaTrend HMA(48) and HMA(78) values and Trend state (`BULLISH` / `BEARISH`)
- Live Upper and Lower Band levels for Yellow, Green, and White
- Real-time Spread and Active Position status (Ticket, Lots, Price, PnL)
- Pending signal tracking and bar countdown

---

## 6. Verification Results

All modes compiled with **0 errors, 0 warnings** and validated in MetaTrader 4 Strategy Tester:

| Test Mode | Symbol & Period | Signals | Executed Trades | Validation Result |
|---|---|---|---|---|
| `ENTRY_YELLOW_ONLY` | GBPCHF H1 | 59 | **21 trades** | Verified Active |
| `ENTRY_MEGA_PLUS_BANDS` | EURCHF H4 | 81 | **18 trades** | Verified Active |
| `ENTRY_MEGA_PLUS_BANDS` | EURCHF H1 | 389 | **3 trades** | Verified Active |
| `ENTRY_MEGA_ONLY` | EURCHF H4 | 52 | **29 trades** | Verified Active |

---

## 7. Installation & Deployment (MetaTrader 4)

1. **Open MT4 Data Folder:**
   - In MT4, click **File** > **Open Data Folder**.
2. **Copy Indicator Files:**
   - Copy all `.mq4` and `.ex4` files from `original/` into `<Data Folder>\MQL4\Indicators\`.
3. **Copy Expert Advisor:**
   - Copy `PtrStrategy_EA.mq4` and `PtrStrategy_EA.ex4` from `ea/` into `<Data Folder>\MQL4\Experts\`.
4. **Refresh Navigator:**
   - Press `Ctrl + N` to open the Navigator.
   - Right-click **Indicators** > **Refresh**.
   - Right-click **Expert Advisors** > **Refresh**.
5. **Attach EA:**
   - Drag `PtrStrategy_EA` onto your target chart (e.g. `GBPCHF H1` or `EURCHF H4`).
   - In the **Common** tab, check **"Allow live trading"** and **"Allow DLL imports"**.
   - In the **Inputs** tab, select your preferred `InpEntryMode` and `InpExitMode`.
