# Raw Strategy Tester Trade Logs

This directory contains the unedited, raw MetaTrader 4 Strategy Tester journal logs capturing all signal evaluations, order placements, stop losses, and take profits across backtests.

## 1. Verified Core Systems (v2.00)

| Log File | Strategy Mode | Symbol & TF | Trades | Highlights |
|---|---|---|---|---|
| [erified_GBPCHF_H1_ENTRY_YELLOW_ONLY.log](verified_GBPCHF_H1_ENTRY_YELLOW_ONLY.log) | ENTRY_YELLOW_ONLY | GBPCHF H1 | **21** | **52.4% Win Rate, +50.0 Pips Net Profit** (Peter's alternate system) |
| [erified_EURCHF_H4_BAND_CONFIRM_ANY.log](verified_EURCHF_H4_BAND_CONFIRM_ANY.log) | ENTRY_MEGA_PLUS_BANDS | EURCHF H4 | **18** | Full Primary System (MegaTrend 48/78 + Yellow/Green confirmation) |
| [erified_EURCHF_H4_ENTRY_MEGA_ONLY.log](verified_EURCHF_H4_ENTRY_MEGA_ONLY.log) | ENTRY_MEGA_ONLY | EURCHF H4 | **29** | Pure MegaTrend 48/78 crossover |
| [erified_EURCHF_H1_MEGA_PLUS_BANDS.log](verified_EURCHF_H1_MEGA_PLUS_BANDS.log) | ENTRY_MEGA_PLUS_BANDS | EURCHF H1 | **3** | Primary System tested on H1 |
| [erified_EURCHF_H4_TMA_CENTERS.log](verified_EURCHF_H4_TMA_CENTERS.log) | ENTRY_MEGA_PLUS_BANDS | EURCHF H4 | **18** | TMA center alignment mode |

## 2. Multi-Pair Filter Suite Test Logs (Real Ticks, H4)

Each test run below covered EURCHF, GBPCHF, and AUDNZD on H4:

- **Suite 1: HMA Stochastic Filter**
  - eurchf_hma_stoch_filter.log
  - gbpchf_hma_stoch_filter.log
  - udnzd_hma_stoch_filter.log

- **Suite 2: Real Stochastic (32,5,10) Zone 82/18 Filter**
  - eurchf_real_stoch_82_18.log
  - gbpchf_real_stoch_82_18.log
  - udnzd_real_stoch_82_18.log

- **Suite 3: Real Stochastic (32,5,10) + Swing Divergence Filter**
  - eurchf_real_stoch_plus_divergence.log
  - gbpchf_real_stoch_plus_divergence.log
  - udnzd_real_stoch_plus_divergence.log
