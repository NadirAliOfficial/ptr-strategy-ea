//+------------------------------------------------------------------+
//| PtrStrategy_EA.mq4                                                |
//| Trades the Ptr indicator set. InpEntryMode selects between the    |
//| confirmed main system (MegaTrend HMA48/78 cross plus Yellow and   |
//| Green both aligned past White) and the client's simpler alternate |
//| idea (Yellow crossing White alone, no MegaTrend, no Green). See   |
//| README.md for exactly what's confirmed vs still being tried.      |
//|                                                                    |
//| InpExitMode is left as a switch — client explicitly wants this    |
//| decided later, in the EA's own Properties, no rebuild needed.     |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
{
   ENTRY_MEGA_ONLY,        // MegaTrend flip alone triggers entry
   ENTRY_MEGA_PLUS_BANDS,  // MegaTrend flip + Yellow AND Green both aligned past White
   ENTRY_YELLOW_ONLY       // Yellow crossing White alone, no MegaTrend, no Green — client's alternate idea
};

enum ENUM_MEGA_TRIGGER
{
   MEGA_SINGLE_FLIP,   // Fast HMA direction flip (InpMegaFastPeriod)
   MEGA_CROSS_48_78    // Fast HMA crosses Slow HMA (Fast/Slow periods)
};

enum ENUM_EXIT_MODE
{
   EXIT_FIXED_PIPS,       // Fixed stop loss / take profit in pips
   EXIT_STOP_AND_REVERSE  // Hold until the opposite signal, then flip
};

//+------------------------------------------------------------------+
//| Inputs — confirmed by the client directly                         |
//+------------------------------------------------------------------+
input group "=== Strategy — confirmed by client ==="
input ENUM_ENTRY_MODE   InpEntryMode         = ENTRY_MEGA_PLUS_BANDS;   // "We only want to see both yellow/green have crossed the White Dotted line"
input ENUM_MEGA_TRIGGER InpMegaTrigger       = MEGA_CROSS_48_78;        // "we take trades upon crosses of both 78 and 48 MegaTr. Lines"
input ENUM_EXIT_MODE    InpExitMode          = EXIT_FIXED_PIPS;         // Left open by client, adjust in Properties
input int               InpConfirmTimeoutBars = 3;      // Bars allowed for band confirm after a Mega flip

input group "=== HMA extension filter (optional) ==="
input bool   InpUseHmaStochFilter  = false;   // Require the fast HMA itself to be in an extreme zone
input int    InpHmaStochPeriod     = 14;      // Lookback bars for the HMA's own high/low range
input double InpHmaStochLowerLevel = 10;      // Buy only if HMA %K is below this
input double InpHmaStochUpperLevel = 90;      // Sell only if HMA %K is above this

input group "=== Real Stochastic zone filter (optional) ==="
input bool   InpUseRealStochFilter = false;   // Require an actual price Stochastic in the zone too
input int    InpStochKPeriod2      = 32;      // %K period, per client's chart (32,5,10)
input int    InpStochDPeriod2      = 5;       // %D period
input int    InpStochSlowing2      = 10;      // Slowing
input double InpStochZoneUpper     = 90;      // Sell zone: Stochastic at/above this
input double InpStochZoneLower     = 10;      // Buy zone: Stochastic at/below this
input int    InpStochZoneLookback  = 10;      // Bars to look back for the zone touch, not just the current bar

input group "=== Divergence filter (optional) ==="
input bool   InpUseDivergenceFilter = false;   // Require price/Stochastic divergence at the two most recent swings
input int    InpDivergenceSwingBars = 3;       // Bars each side to confirm a swing point
input int    InpDivergenceLookback  = 40;      // Bars to search back for the two swings

//+------------------------------------------------------------------+
//| Inputs — indicator settings, confirmed from client's settings sheet|
//+------------------------------------------------------------------+
input group "=== Indicator Settings (confirmed) ==="
input int    InpMegaFastPeriod  = 48;     // Ptr Mega Trend HMA period (fast)
input int    InpMegaSlowPeriod  = 78;     // Ptr Mega Trend HMA period (slow)
input int    InpYellowHalfLength = 21;    // Yellow Ptr Arslan half length
input int    InpGreenHalfLength  = 40;    // Norepaint zone 3 green half length
input int    InpWhiteHalfLength  = 32;    // White Ptr Arslan half length — used as the confirmation line
input int    InpWhitePeriod      = 100;   // White Ptr Arslan bands period
input double InpWhiteMultiplier  = 2.8;   // White Ptr Arslan bands deviation
input string InpBandTimeFrame    = "60";  // Yellow/Green TimeFrame setting (H1 per sheet)

//+------------------------------------------------------------------+
//| Inputs — trade settings                                           |
//+------------------------------------------------------------------+
input group "=== Trade Settings ==="
input double InpLots            = 0.10;
input int    InpMagicNumber     = 20260908;
input int    InpSlippage        = 10;
input int    InpTakeProfitPips  = 50;      // used when InpExitMode = EXIT_FIXED_PIPS
input int    InpStopLossPips    = 50;      // used when InpExitMode = EXIT_FIXED_PIPS
input int    InpMaxSpreadPoints = 30;

//+------------------------------------------------------------------+
//| Indicator file names — must match exactly what's in Indicators\   |
//+------------------------------------------------------------------+
#define IND_MEGA   "Ptr Mega Trend"
#define IND_YELLOW "Yellow Ptr Arslan"
#define IND_GREEN  "Norepaint zone 3 green"
#define IND_WHITE  "White Ptr Arslan"

//+------------------------------------------------------------------+
//| Globals                                                            |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
int      g_pointAdjust = 1;   // 10 on 3/5-digit brokers, matches indicator source convention

struct PendingSignal
{
   bool     active;      // a Mega flip is being tracked
   bool     confirmed;   // ready to execute on the next bar open
   int      dir;         // +1 buy, -1 sell
   int      barsSeen;    // bars spent waiting for band alignment

   void Reset()
   {
      active = false; confirmed = false; dir = 0; barsSeen = 0;
   }
};
PendingSignal g_pending;

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pointAdjust = (Digits == 3 || Digits == 5) ? 10 : 1;
   g_pending.Reset();
   g_lastBarTime = 0;

   Print("[Init] PtrStrategy_EA — EntryMode=", EnumToString(InpEntryMode),
         " MegaTrigger=", EnumToString(InpMegaTrigger),
         " ExitMode=", EnumToString(InpExitMode));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| MegaTrend helpers                                                  |
//+------------------------------------------------------------------+
//--- raw HMA value (buffer 2 in Ptr Mega Trend.mq4) for a given period
double MegaHMA(int period, int shift)
{
   return iCustom(NULL, 0, IND_MEGA, period, MODE_LWMA, PRICE_CLOSE, 0,
                  true, clrSeaGreen, clrCrimson, STYLE_SOLID, 2,
                  true, clrLavender, clrMagenta, 5, 233, 234, 1,
                  2, shift);
}

//--- direction of a single HMA line: +1 rising, -1 falling, 0 flat/unknown
int MegaDir(int period, int shift)
{
   double cur  = MegaHMA(period, shift);
   double prev = MegaHMA(period, shift + 1);
   if(cur == EMPTY_VALUE || prev == EMPTY_VALUE) return 0;
   if(cur > prev) return 1;
   if(cur < prev) return -1;
   return 0;
}

//--- signal direction per InpMegaTrigger, using the just-closed bar (shift=1)
int MegaSignalDir(int shift)
{
   if(InpMegaTrigger == MEGA_SINGLE_FLIP)
   {
      int dirNow  = MegaDir(InpMegaFastPeriod, shift);
      int dirPrev = MegaDir(InpMegaFastPeriod, shift + 1);
      if(dirNow != 0 && dirNow != dirPrev) return dirNow;   // fresh flip
      return 0;
   }
   else // MEGA_CROSS_48_78
   {
      double fastNow  = MegaHMA(InpMegaFastPeriod, shift);
      double slowNow  = MegaHMA(InpMegaSlowPeriod, shift);
      double fastPrev = MegaHMA(InpMegaFastPeriod, shift + 1);
      double slowPrev = MegaHMA(InpMegaSlowPeriod, shift + 1);
      if(fastNow == EMPTY_VALUE || slowNow == EMPTY_VALUE ||
         fastPrev == EMPTY_VALUE || slowPrev == EMPTY_VALUE) return 0;

      bool wasAbove = fastPrev > slowPrev;
      bool isAbove  = fastNow  > slowNow;
      if(isAbove && !wasAbove) return 1;    // fast crossed above slow
      if(!isAbove && wasAbove) return -1;   // fast crossed below slow
      return 0;
   }
}

//--- Client described watching the MegaTrend lines against the chart's
//    90/10 reference levels. Those levels only exist because MT4 auto
//    scales two unrelated indicators sharing one window, there is no real
//    relationship between HMA's price value and the number "10" or "90".
//    A real, computable equivalent: run the standard %K formula (current
//    minus the lowest of the last N, divided by the range of the last N)
//    against the HMA series itself instead of price, so "the HMA is near
//    the top/bottom of its own recent range" becomes an actual number.
double HmaStochK(int period, int shift)
{
   double first = MegaHMA(period, shift);
   if(first == EMPTY_VALUE) return EMPTY_VALUE;

   double hi = first, lo = first;
   for(int i = shift + 1; i < shift + InpHmaStochPeriod; i++)
   {
      double v = MegaHMA(period, i);
      if(v == EMPTY_VALUE) return EMPTY_VALUE;
      if(v > hi) hi = v;
      if(v < lo) lo = v;
   }
   if(hi == lo) return EMPTY_VALUE;
   return (first - lo) / (hi - lo) * 100.0;
}

//--- Gate for InpUseHmaStochFilter — true if the fast HMA is extended
//    enough in the signal direction, or the filter is switched off.
bool HmaExtendedEnough(int dir, int shift)
{
   if(!InpUseHmaStochFilter) return true;

   double k = HmaStochK(InpMegaFastPeriod, shift);
   if(k == EMPTY_VALUE) return false;

   if(dir > 0) return (k < InpHmaStochLowerLevel);
   if(dir < 0) return (k > InpHmaStochUpperLevel);
   return false;
}

//--- Client's latest chart shows a genuine, real MT4 Stochastic (32,5,10),
//    unlike the earlier "90/10 levels" which turned out to just be visual
//    reference lines. This is the real thing, built in, no custom file
//    needed. Client's own words: using Stochastic alone fires too early,
//    so this is only checked as an extra AND condition on top of the
//    existing MegaTrend/band system, not a replacement for it.
//
//    Tested same-bar first: a bullish HMA48/78 crossover only prints after
//    price has already risen for several bars, which pushes Stochastic up,
//    not down to oversold — the two conditions can never be true on the
//    same bar by construction, confirmed on real data (0/52 passed).
//    Fixed to look back InpStochZoneLookback bars instead of just the
//    current one, matching the confirmation-window pattern already used
//    for Yellow/Green — Stochastic hitting the zone shortly before the
//    crossover is what actually happens on a real reversal.
bool RealStochInZone(int dir, int shift)
{
   if(!InpUseRealStochFilter) return true;

   for(int i = shift; i < shift + InpStochZoneLookback; i++)
   {
      double k = iStochastic(NULL, 0, InpStochKPeriod2, InpStochDPeriod2, InpStochSlowing2,
                             MODE_SMA, 0, MODE_MAIN, i);
      if(k == EMPTY_VALUE) continue;

      if(dir > 0 && k <= InpStochZoneLower) return true;
      if(dir < 0 && k >= InpStochZoneUpper) return true;
   }
   return false;
}

//--- Divergence — what the client has pointed at repeatedly on his charts.
//    A swing point is a bar whose low (or high) is the most extreme among
//    InpDivergenceSwingBars bars on each side. Bullish divergence: a more
//    recent swing low is a LOWER price than an earlier one, while the
//    Stochastic value at that more recent low is HIGHER than at the
//    earlier one — price making a new low without momentum confirming it.
//    Bearish divergence is the mirror image on swing highs.
int FindSwingLow(int startShift, int endShift)
{
   for(int i = startShift; i <= endShift; i++)
   {
      double lowI = iLow(NULL, 0, i);
      bool isSwing = true;
      for(int j = 1; j <= InpDivergenceSwingBars; j++)
      {
         if(i - j < 0) { isSwing = false; break; }
         if(iLow(NULL, 0, i - j) < lowI || iLow(NULL, 0, i + j) < lowI)
         {
            isSwing = false;
            break;
         }
      }
      if(isSwing) return i;
   }
   return -1;
}

int FindSwingHigh(int startShift, int endShift)
{
   for(int i = startShift; i <= endShift; i++)
   {
      double highI = iHigh(NULL, 0, i);
      bool isSwing = true;
      for(int j = 1; j <= InpDivergenceSwingBars; j++)
      {
         if(i - j < 0) { isSwing = false; break; }
         if(iHigh(NULL, 0, i - j) > highI || iHigh(NULL, 0, i + j) > highI)
         {
            isSwing = false;
            break;
         }
      }
      if(isSwing) return i;
   }
   return -1;
}

double StochAt(int shift)
{
   return iStochastic(NULL, 0, InpStochKPeriod2, InpStochDPeriod2, InpStochSlowing2,
                      MODE_SMA, 0, MODE_MAIN, shift);
}

bool BullishDivergence(int shift)
{
   int swingOld = FindSwingLow(shift + InpDivergenceSwingBars, shift + InpDivergenceLookback);
   if(swingOld < 0) return false;
   int swingNew = FindSwingLow(shift, swingOld - InpDivergenceSwingBars - 1);
   if(swingNew < 0) return false;

   double priceOld = iLow(NULL, 0, swingOld);
   double priceNew = iLow(NULL, 0, swingNew);
   double stochOld = StochAt(swingOld);
   double stochNew = StochAt(swingNew);
   if(stochOld == EMPTY_VALUE || stochNew == EMPTY_VALUE) return false;

   return (priceNew < priceOld && stochNew > stochOld);
}

bool BearishDivergence(int shift)
{
   int swingOld = FindSwingHigh(shift + InpDivergenceSwingBars, shift + InpDivergenceLookback);
   if(swingOld < 0) return false;
   int swingNew = FindSwingHigh(shift, swingOld - InpDivergenceSwingBars - 1);
   if(swingNew < 0) return false;

   double priceOld = iHigh(NULL, 0, swingOld);
   double priceNew = iHigh(NULL, 0, swingNew);
   double stochOld = StochAt(swingOld);
   double stochNew = StochAt(swingNew);
   if(stochOld == EMPTY_VALUE || stochNew == EMPTY_VALUE) return false;

   return (priceNew > priceOld && stochNew < stochOld);
}

bool DivergenceConfirmed(int dir, int shift)
{
   if(!InpUseDivergenceFilter) return true;
   if(dir > 0) return BullishDivergence(shift);
   if(dir < 0) return BearishDivergence(shift);
   return false;
}

//+------------------------------------------------------------------+
//| White's bands — buffer 0 (the center TMA) is colour1=clrNONE in   |
//| the source, it is never drawn, there is no visible middle line.   |
//| Only buffer 3 (upper) and buffer 4 (lower) are actually white and |
//| visible on the client's chart — those are "White Dotted Line".   |
//+------------------------------------------------------------------+
double WhiteUpperValue(int shift)
{
   // White Ptr Arslan's own enPrices enum isn't visible here, pr_weighted
   // is position 6 in that file's enum (pr_close=0 ... pr_weighted=6)
   return iCustom(NULL, 0, IND_WHITE, InpWhiteHalfLength, 6,
                  InpWhitePeriod, InpWhiteMultiplier, 3, shift);
}

double WhiteLowerValue(int shift)
{
   return iCustom(NULL, 0, IND_WHITE, InpWhiteHalfLength, 6,
                  InpWhitePeriod, InpWhiteMultiplier, 4, shift);
}

double BandCenterValue(string indName, int halfLength, int shift)
{
   return iCustom(NULL, 0, indName, InpBandTimeFrame, halfLength,
                  PRICE_CLOSE, 1.8, false, false, false, false, true,
                  0, shift);
}

double YellowValue(int shift) { return BandCenterValue(IND_YELLOW, InpYellowHalfLength, shift); }
double GreenValue(int shift)  { return BandCenterValue(IND_GREEN, InpGreenHalfLength, shift); }

//--- ENTRY_YELLOW_ONLY: client's alternate idea — Yellow crossing White is
//    the entry trigger on its own, a discrete cross event. Confirmed by the
//    client directly: crossing below the LOWER white band is a BUY, crossing
//    above the UPPER white band is a SELL (opposite of a simple midline
//    cross — there is no visible midline at all, see WhiteUpperValue above).
int YellowCrossDir(int shift)
{
   double yellowNow  = YellowValue(shift);
   double yellowPrev = YellowValue(shift + 1);
   double lowerNow   = WhiteLowerValue(shift);
   double lowerPrev  = WhiteLowerValue(shift + 1);
   double upperNow   = WhiteUpperValue(shift);
   double upperPrev  = WhiteUpperValue(shift + 1);

   if(yellowNow == EMPTY_VALUE || yellowPrev == EMPTY_VALUE ||
      lowerNow == EMPTY_VALUE || lowerPrev == EMPTY_VALUE ||
      upperNow == EMPTY_VALUE || upperPrev == EMPTY_VALUE) return 0;

   bool wasBelowLower = yellowPrev < lowerPrev;
   bool isBelowLower  = yellowNow  < lowerNow;
   if(isBelowLower && !wasBelowLower) return 1;    // crossed down through lower band — BUY

   bool wasAboveUpper = yellowPrev > upperPrev;
   bool isAboveUpper  = yellowNow  > upperNow;
   if(isAboveUpper && !wasAboveUpper) return -1;   // crossed up through upper band — SELL

   return 0;
}

//--- Confirmed by client: "we only want to see both yellow/green have
//    crossed the White Dotted line," specifically the lower band for buys,
//    upper band for sells (there is no visible midline, see above). Tested
//    as a discrete cross event for each band independently first — over a
//    full year of EURCHF H4 that produced 0 trades, since Green (half
//    length 40) is roughly twice as slow as Yellow (half length 21) and
//    essentially never crosses within the same few-bar window Yellow does.
//    Switched to a state check instead: at the time of the signal, are
//    Yellow and Green both beyond the relevant band already.
bool BandsAlignedAt(int dir, int shift)
{
   double yellowNow = YellowValue(shift);
   double greenNow  = GreenValue(shift);

   if(yellowNow == EMPTY_VALUE || greenNow == EMPTY_VALUE) return false;

   if(dir > 0)
   {
      double lowerNow = WhiteLowerValue(shift);
      if(lowerNow == EMPTY_VALUE) return false;
      return (yellowNow < lowerNow && greenNow < lowerNow);
   }
   if(dir < 0)
   {
      double upperNow = WhiteUpperValue(shift);
      if(upperNow == EMPTY_VALUE) return false;
      return (yellowNow > upperNow && greenNow > upperNow);
   }
   return false;
}

//+------------------------------------------------------------------+
//| New bar detection                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   if(Time[0] == g_lastBarTime) return false;
   g_lastBarTime = Time[0];
   return true;
}

//+------------------------------------------------------------------+
//| Position helpers                                                   |
//+------------------------------------------------------------------+
bool FindOpenPosition(int &ticket, bool &isBuy)
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      ticket = OrderTicket();
      isBuy  = (OrderType() == OP_BUY);
      return true;
   }
   return false;
}

void ClosePosition(int ticket, bool isBuy)
{
   double price = isBuy ? Bid : Ask;
   if(!OrderClose(ticket, OrderLots(), price, InpSlippage))
      Print("[Trade] Close failed ticket=", ticket, " error=", GetLastError());
}

//+------------------------------------------------------------------+
//| Open a trade in the given direction                               |
//+------------------------------------------------------------------+
void OpenTrade(int dir)
{
   double spread = (Ask - Bid) / Point;
   if(spread > InpMaxSpreadPoints)
   {
      Print("[Trade] Blocked — spread too wide (", spread, " pts).");
      return;
   }

   double price = dir > 0 ? Ask : Bid;
   double sl = 0, tp = 0;

   if(InpExitMode == EXIT_FIXED_PIPS)
   {
      double slDist = InpStopLossPips   * g_pointAdjust * Point;
      double tpDist = InpTakeProfitPips * g_pointAdjust * Point;
      sl = dir > 0 ? price - slDist : price + slDist;
      tp = dir > 0 ? price + tpDist : price - tpDist;
   }
   // EXIT_STOP_AND_REVERSE — no fixed SL/TP, managed by the reverse logic below

   int ticket = OrderSend(Symbol(), dir > 0 ? OP_BUY : OP_SELL, InpLots,
                          price, InpSlippage, sl, tp,
                          "PtrStrategy", InpMagicNumber, 0,
                          dir > 0 ? clrBlue : clrRed);

   if(ticket < 0)
      Print("[Trade] OrderSend failed error=", GetLastError());
   else
      Print("[Trade] ", dir > 0 ? "BUY" : "SELL", " opened ticket=", ticket,
            " price=", price, " sl=", sl, " tp=", tp);
}

//+------------------------------------------------------------------+
//| OnTick                                                             |
//| Runs once per new bar. "confirmed" means: act on the FIRST tick   |
//| of the very next bar, i.e. "enter on the following opening        |
//| candle" as the client specified.                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   //--- 1) Execute anything confirmed as of the previous closed bar
   if(g_pending.active && g_pending.confirmed)
   {
      int  posTicket = -1;
      bool posIsBuy  = false;
      bool hasPosition = FindOpenPosition(posTicket, posIsBuy);

      if(hasPosition && posIsBuy != (g_pending.dir > 0))
      {
         Print("[Trade] Closing opposite position ticket=", posTicket,
               " before ", g_pending.dir > 0 ? "BUY" : "SELL");
         ClosePosition(posTicket, posIsBuy);
         hasPosition = false;
      }

      if(!hasPosition)
         OpenTrade(g_pending.dir);
      else
         Print("[Trade] Skipped — already in a ", g_pending.dir > 0 ? "BUY" : "SELL", " position.");

      g_pending.Reset();
      //--- fall through: this same closed bar can also start a new signal below
   }

   //--- 2) Fresh signal on the bar that just closed (shift=1) — source
   //    depends on entry mode: MegaTrend for the two Mega-based modes,
   //    or Yellow crossing White directly for the client's alternate idea.
   //    HmaExtendedEnough only applies to the MegaTrend-based modes, and
   //    is a no-op (always true) when InpUseHmaStochFilter is off.
   int signalDir = (InpEntryMode == ENTRY_YELLOW_ONLY) ? YellowCrossDir(1) : MegaSignalDir(1);
   if(signalDir != 0 && InpEntryMode != ENTRY_YELLOW_ONLY && !HmaExtendedEnough(signalDir, 1))
   {
      Print("[Signal] MegaTrend ", signalDir > 0 ? "BUY" : "SELL",
            " ignored — HMA not extended enough (InpUseHmaStochFilter).");
      signalDir = 0;
   }
   if(signalDir != 0 && InpEntryMode != ENTRY_YELLOW_ONLY && !RealStochInZone(signalDir, 1))
   {
      Print("[Signal] MegaTrend ", signalDir > 0 ? "BUY" : "SELL",
            " ignored — Stochastic not in zone (InpUseRealStochFilter).");
      signalDir = 0;
   }
   if(signalDir != 0 && !DivergenceConfirmed(signalDir, 1))
   {
      Print("[Signal] ", signalDir > 0 ? "BUY" : "SELL",
            " ignored — no divergence (InpUseDivergenceFilter).");
      signalDir = 0;
   }

   if(signalDir != 0 && (!g_pending.active || g_pending.dir != signalDir))
   {
      g_pending.Reset();
      g_pending.active    = true;
      g_pending.confirmed = (InpEntryMode == ENTRY_MEGA_ONLY || InpEntryMode == ENTRY_YELLOW_ONLY);
      g_pending.dir       = signalDir;

      if(InpEntryMode == ENTRY_YELLOW_ONLY)
         Print("[Signal] Yellow crossed White, ", signalDir > 0 ? "BUY" : "SELL", " — executing next open.");
      else
         Print("[Signal] MegaTrend ", signalDir > 0 ? "BUY" : "SELL",
               InpEntryMode == ENTRY_MEGA_ONLY
                  ? " — executing next open."
                  : " — waiting up to " + IntegerToString(InpConfirmTimeoutBars) +
                    " bars for Yellow and Green to align past White.");
   }

   //--- 3) Still waiting on confirmation — checked as a state each bar:
   //    Yellow and Green both on the far side of White, in signal direction.
   if(g_pending.active && !g_pending.confirmed)
   {
      g_pending.barsSeen++;

      if(BandsAlignedAt(g_pending.dir, 1))
      {
         g_pending.confirmed = true;
         Print("[Signal] Yellow and Green both aligned past White, executing next open.");
      }
      else if(g_pending.barsSeen >= InpConfirmTimeoutBars)
      {
         Print("[Signal] Bands never aligned within ", g_pending.barsSeen, " bars, discarding.");
         g_pending.Reset();
      }
   }
}
