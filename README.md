# Ptr Strategy EA

[![Platform](https://img.shields.io/badge/Platform-MetaTrader%204%20(MT4)-blue.svg)](https://www.metatrader4.com/)
[![Language](https://img.shields.io/badge/Language-MQL4%20(%23property%20strict)-green.svg)](https://docs.mql4.com/)
[![Build](https://img.shields.io/badge/Build-0%20errors%20%7C%200%20warnings-brightgreen.svg)]()
[![Status](https://img.shields.io/badge/Status-Compiled%20%26%20Verified-success.svg)]()

An automated Expert Advisor (EA) developed for **MetaTrader 4 (MQL4)**, built around the client's proprietary four-indicator **"Ptr"** system:
* **Ptr Mega Trend**: Hull Moving Average (HMA), loaded at two periods (48 and 78) — a cross between them is the primary trigger.
* **Yellow Ptr Arslan**: Faster non-repainting Triangular Moving Average (TMA) band — its own center line crossing White confirms.
* **Norepaint zone 3 green**: Slower non-repainting TMA band — its own center line crossing White also confirms.
* **White Ptr Arslan**: Centered repainting TMA band. Initially assumed visual-only; confirmed by the client to actually be the confirmation line Yellow and Green must cross.

The EA is designed with switchable inputs for strategy variants rather than hardcoded assumptions, allowing full configuration without needing code recompilations.

## Client's alternate idea — now built as a third entry mode

Client's own words: *"Eliminate completely the MegaTrend and arrow lines and the
stochastic completely and ONLY USE YELLOW CROSSES OF WHITE DOTTED LINE. Also forget
about the GREEN line."* Followed up with a real chart example (GBP/CHF H1, marked
"Yellow confirmed cross") showing it in action. Built as `ENTRY_YELLOW_ONLY` — see
Strategy Rules below. Not the default, `ENTRY_MEGA_PLUS_BANDS` still is, but it's a
real switch now, not just a note, ready to test whenever the client wants.

Also confirmed with the client directly: there is no real Stochastic calculation
anywhere in this strategy (see the MegaTrend Trigger section below) — the "Stochastic
90/10 levels" are purely the visual reference lines the MegaTrend arrows are drawn
against on his chart, not a value the code computes or compares against HMA.

---

## Indicator Suite Specifications

All indicators are integrated via `iCustom()` matching exact source parameter orders and buffer definitions:

| Indicator File | Role | Confirmed Parameters | Buffer Used in EA |
|---|---|---|---|
| `Ptr Mega Trend.mq4` | Primary trigger: HMA(48) crosses HMA(78) | Fast HMA `48`, Slow HMA `78`, Linear Weighted (`MODE_LWMA`), Close price | Buffer `2` (`HMA` line), called once per period |
| `Yellow Ptr Arslan.mq4` | Confirmation: its center line crossing White | Half Length `21` (corrected from default 60), TimeFrame `60` (H1), Close price, Dev `1.8` | Buffer `0` (center TMA) |
| `Norepaint zone 3 green.mq4` | Confirmation: its center line crossing White | Half Length `40`, TimeFrame `60` (H1), Close price, Dev `1.8` | Buffer `0` (center TMA) |
| `White Ptr Arslan.mq4` | The band Yellow and Green must cross | Half Length `32`, Period `100`, Multiplier `2.8`, Weighted price | Buffer `3` (upper, buy uses lower / sell uses upper) and `4` (lower). Buffer `0`, the center, is `color1=clrNONE` in the source — never drawn, no visible midline exists at all, confirmed directly by the client after an earlier version of this EA compared against that invisible line by mistake. |

> **Note:** In MT4, indicator filenames must match `#define IND_...` in `PtrStrategy_EA.mq4` exactly:
> - `#define IND_MEGA "Ptr Mega Trend"`
> - `#define IND_YELLOW "Yellow Ptr Arslan"`
> - `#define IND_GREEN "Norepaint zone 3 green"`
> - `#define IND_WHITE "White Ptr Arslan"`

---

## Strategy Rules & Switchable Modes

To accommodate client preferences without rebuilding, key trading behaviors are exposed as external inputs:

### 1. Entry Trigger (`InpEntryMode`) — CONFIRMED
Client's own words: *"We do not care about any crosses of Green/Yellow by themselves
at all. We only want to see both yellow/green have crossed the White Dotted line."*
* `ENTRY_MEGA_PLUS_BANDS` *(Default, confirmed)*: MegaTrend crosses, AND Yellow and Green are both on the far side of White (in the signal direction) within `InpConfirmTimeoutBars` bars (default: 3). Checked as a state (Yellow > White and Green > White for a buy), not a discrete cross event for each — tested the discrete-event version first over a full year of EURCHF H4, it produced 0 trades because Green (half length 40) is roughly twice as slow as Yellow (half length 21) and essentially never crosses within the same short window Yellow does. The state check matches how this reads on a chart at a glance and isn't fragile to that speed gap.
* `ENTRY_MEGA_ONLY`: MegaTrend cross alone, no band confirmation. Kept as a switch, not the confirmed behavior.
* `ENTRY_YELLOW_ONLY`: Client's alternate idea. Yellow crossing White is the entry trigger on its own — a discrete cross event (checked with `YellowCrossDir`), not a state, since here it's the primary signal rather than a slow confirmation layered on something else. No MegaTrend, no Green, `InpMegaTrigger` and `InpConfirmTimeoutBars` don't apply in this mode. Not the default, ready to test.

### 2. MegaTrend Trigger (`InpMegaTrigger`) — CONFIRMED
Client's settings sheet, in his own words: *"We do not wait for arrows, but we take
trades upon crosses of both 78 and 48 MegaTr. Lines."* (The "Stochastic 90/10 levels"
mentioned alongside this are just the visual reference lines the MegaTrend arrows are
drawn against on his chart — there is no real Stochastic indicator or calculation
involved anywhere in this strategy, confirmed directly by the client after an earlier
misread of his chart screenshot.)
* `MEGA_CROSS_48_78` *(Default, confirmed)*: The fast HMA(48) crosses the slow HMA(78).
* `MEGA_SINGLE_FLIP`: A single HMA(48) direction flip. Kept as a switch, not the confirmed behavior.

The client kept describing wanting the 48/78 cross to happen "at" the 90/10 zone,
which isn't literally possible (HMA is a price value, it has no real position on a
0-100 scale — those levels only appear because MT4 auto-scales two unrelated
indicators into one shared window). The real, computable equivalent: `InpUseHmaStochFilter`
(off by default) runs a standard %K formula against the HMA series itself instead of
price — how far the current HMA value sits within its own last `InpHmaStochPeriod`
bars' range, as an actual 0-100 number. When on, a MegaTrend cross only counts if
that reading is below `InpHmaStochLowerLevel` (buy) or above `InpHmaStochUpperLevel`
(sell).

Client's later chart showed a genuine, real MT4 Stochastic (32,5,10) plotted alongside
MegaTrend, not just visual reference lines like the earlier example. `InpUseRealStochFilter`
(off by default) checks the actual built in Stochastic against `InpStochZoneLower`/`InpStochZoneUpper`
as a real AND condition on top of the MegaTrend cross — client's own words, using
Stochastic alone fires too early, so this only tightens the existing system, it does
not replace it.

**Known limitation, confirmed with real debug data:** Yellow (half length 21, a
smoothed ~42-bar triangular filter) mathematically cannot reach White's outer bands
(±2.8×ATR(100) from center) — over 6,078 bars of GBPCHF H1, price pierced those bands
133 times, Yellow never once got closer than 16 pips to either one. `ENTRY_YELLOW_ONLY`
and the outer-band confirmation in `ENTRY_MEGA_PLUS_BANDS` are both currently unfireable
as a result — this is a real structural mismatch between Yellow's smoothing and White's
band width, not a code bug. Needs a decision from the client: loosen White's multiplier,
or drop the requirement that it be the *outer* band specifically.

### 3. Exit Method (`InpExitMode`) — left open by the client
Client's own words: *"I will study harder later... leave this open... set it in properties at a later date."*
* `EXIT_FIXED_PIPS` *(Default)*: Fixed SL/TP in pips (`InpTakeProfitPips`, `InpStopLossPips`), 3/5-digit broker point normalization.
* `EXIT_STOP_AND_REVERSE`: Hold until the opposite confirmed signal, then close and reverse.

### 5. Bar Execution Timing (Confirmed)
Entries strictly execute on the **open of the bar following confirmation** (`IsNewBar()`), adhering to the client rule: *"enter on the following opening candle"*.

---

## Input Parameters Overview

```mql4
//=== Strategy Triggers ===
input ENUM_ENTRY_MODE   InpEntryMode          = ENTRY_MEGA_PLUS_BANDS; // Entry confirmation mode
input ENUM_MEGA_TRIGGER InpMegaTrigger        = MEGA_CROSS_48_78;       // MegaTrend calculation mode
input ENUM_EXIT_MODE    InpExitMode           = EXIT_FIXED_PIPS;       // Exit management mode
input int               InpConfirmTimeoutBars = 3;                     // Max bars to wait for band confirm

//=== Indicator Settings (Confirmed from client sheet) ===
input int    InpMegaFastPeriod   = 48;    // MegaTrend fast HMA period
input int    InpMegaSlowPeriod   = 78;    // MegaTrend slow HMA period
input int    InpYellowHalfLength = 21;    // Yellow TMA band half length
input int    InpGreenHalfLength  = 40;    // Green TMA band half length
input int    InpWhiteHalfLength  = 32;    // White TMA line — the confirmation target
input int    InpWhitePeriod      = 100;   // White TMA bands period
input double InpWhiteMultiplier  = 2.8;   // White TMA bands deviation
input string InpBandTimeFrame    = "60";  // Band timeframe (60 = H1)

//=== Trade & Risk Management ===
input double InpLots             = 0.10;     // Trade volume
input int    InpMagicNumber      = 20260908; // EA magic number
input int    InpTakeProfitPips   = 50;       // Take Profit in pips
input int    InpStopLossPips     = 50;       // Stop Loss in pips
input int    InpMaxSpreadPoints  = 30;       // Max allowable spread filter
input int    InpSlippage         = 10;       // Max allowable slippage
```

---

## Installation & Deployment (MetaTrader 4)

1. **Locate MT4 Data Folder:**
   * Open MetaTrader 4.
   * Go to **File** > **Open Data Folder** (typically `%APPDATA%\MetaQuotes\Terminal\<Terminal_ID>\`).

2. **Copy Indicator Files:**
   * Copy all `.mq4` and `.ex4` files from the `original/` folder into:
     ```
     <Data Folder>\MQL4\Indicators\
     ```

3. **Copy Expert Advisor:**
   * Copy `PtrStrategy_EA.mq4` and `PtrStrategy_EA.ex4` from `ea/` into:
     ```
     <Data Folder>\MQL4\Experts\
     ```

4. **Refresh Navigator:**
   * In MT4, open the **Navigator** panel (`Ctrl + N`).
   * Right-click **Indicators** &rarr; **Refresh**.
   * Right-click **Expert Advisors** &rarr; **Refresh**.

5. **Attach EA:**
   * Drag `PtrStrategy_EA` onto your target chart (e.g. `EURCHF`, `H1`).
   * In the **Common** tab, ensure **"Allow live trading"** and **"Allow DLL imports"** are enabled.

---

## Compilation Status

The codebase was compiled and verified using MetaEditor 4 (build 1420+):

```text
Information: Compiling 'PtrStrategy_EA.mq4'
Result: 0 errors, 0 warnings
```

All 4 indicator files and the EA have pre-compiled `.ex4` binaries included in the repository.

---

## Repository Layout

```
ptr-strategy-ea/
├── ea/
│   ├── PtrStrategy_EA.mq4            # Source code of the Expert Advisor
│   └── PtrStrategy_EA.ex4            # Pre-compiled executable deliverable
├── original/
│   ├── Norepaint zone 3 green.mq4    # Slow non-repainting TMA band indicator source
│   ├── Norepaint zone 3 green.ex4    # Compiled binary
│   ├── Ptr Mega Trend.mq4            # Hull MA trend indicator source
│   ├── Ptr Mega Trend.ex4            # Compiled binary
│   ├── Yellow Ptr Arslan.mq4         # Fast non-repainting TMA band indicator source
│   ├── Yellow Ptr Arslan.ex4         # Compiled binary
│   ├── White Ptr Arslan.mq4          # Centered repainting TMA band source (visual only)
│   ├── White Ptr Arslan.ex4          # Compiled binary
│   └── Ptr Settings.pdf              # Original client settings specification
├── .gitignore
└── README.md
```

---

## Deliverables & Testing

* **Compiled EA**: [`ea/PtrStrategy_EA.ex4`](ea/PtrStrategy_EA.ex4)
* **Pre-compiled Indicators**: All 4 indicators available under [`original/`](original/)
* **Strategy Tester**: Configured for backtesting and demo validation on EUR/CHF H1.

---

## Terms

Technical development on the EA source code adhering to client trading rules. No performance guarantees regarding market profits, win rates, or drawdown.
