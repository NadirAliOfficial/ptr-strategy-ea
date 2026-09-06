# Ptr Strategy EA

Client project. An MQL4 Expert Advisor built around a four-indicator "Ptr"
set (MegaTrend HMA, Yellow/Green no-repaint TMA bands, White repainting TMA
kept for visual reference only), analyzed and coded to match the client's
own settings sheet and trading rules.

## Indicators (as supplied by the client)

| File | Role | Confirmed settings |
|---|---|---|
| `Ptr Mega Trend.mq4` | HMA trend, up/down flip arrows | HMA period 48 (fast) and 78 (slow), Linear Weighted, Close price |
| `Yellow Ptr Arslan.mq4` | No-repaint TMA band, faster | Half length 21 (corrected from the file's own default of 60), H1, Close price, deviation 1.8 |
| `Norepaint zone 3 green.mq4` | No-repaint TMA band, slower | Half length 40, H1, Close price, deviation 1.8 |
| `White Ptr Arslan.mq4` | Centered, repainting TMA band | Half length 32, weighted price, ATR period 100, deviation ×2.8 — visual reference only, not used in entry logic per the client |

## Strategy — confirmed vs pending

The EA is built with the exact entry/exit rule as a switchable input rather
than guessed into fixed behaviour, since the client's own messages left it
genuinely ambiguous. A clarifying question covering all three points below
was sent; the EA already supports either answer without a rebuild.

- **Entry trigger** — `InpEntryMode`: MegaTrend flip alone (`ENTRY_MEGA_ONLY`),
  or MegaTrend flip plus a same-direction Yellow/Green band reversal within
  `InpConfirmTimeoutBars` bars (`ENTRY_MEGA_PLUS_BANDS`, current default).
- **MegaTrend signal** — `InpMegaTrigger`: the fast HMA(48) flipping direction
  on its own (`MEGA_SINGLE_FLIP`, current default), or the fast HMA crossing
  the slow HMA(78) (`MEGA_CROSS_48_78`).
- **Exit method** — `InpExitMode`: fixed stop loss / take profit in pips
  (`EXIT_FIXED_PIPS`, current default), or hold until the opposite signal
  and reverse (`EXIT_STOP_AND_REVERSE`).

Confirmed and not in question: entries fire on the open of the bar *after*
a signal is confirmed ("enter on the following opening candle"), matching
the client's own wording exactly.

## Status

EA source written (`ea/PtrStrategy_EA.mq4`). Not yet compiled — this needs
a real MetaTrader 4 install (MQL4 and MQL5 are different languages; MT5's
MetaEditor cannot compile true MQL4, confirmed directly). Compiling is in
progress on a Windows machine with MT4 installed.

## Deliverables

- Compiled EA (`.ex4`)
- `.set` file with the confirmed settings once the three open questions are answered
- Video proof: a Strategy Tester run on the client's EUR/CHF history with
  each trade labelled by what triggered it
- Client tests the compiled EA on their own demo account before final payment

## Terms

Technical development on the EA code only, matching the client's own
described strategy. No guarantee of profit, win rate, or reduced drawdown.

## Repository layout

```
original/   client's four indicator files as received, plus their settings sheet
ea/         the EA source built against them
```
