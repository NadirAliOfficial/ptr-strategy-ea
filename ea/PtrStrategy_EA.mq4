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

//+------------------------------------------------------------------+
//| Center-line helpers — White's own center TMA (buffer 0), and      |
//| Yellow/Green's own center TMA (also buffer 0 in those files)      |
//+------------------------------------------------------------------+
double WhiteValue(int shift)
{
   // White Ptr Arslan's own enPrices enum isn't visible here, pr_weighted
   // is position 6 in that file's enum (pr_close=0 ... pr_weighted=6)
   return iCustom(NULL, 0, IND_WHITE, InpWhiteHalfLength, 6,
                  InpWhitePeriod, InpWhiteMultiplier, 0, shift);
}

double BandCenterValue(string indName, int halfLength, int shift)
{
   return iCustom(NULL, 0, indName, InpBandTimeFrame, halfLength,
                  PRICE_CLOSE, 1.8, false, false, false, false, true,
                  0, shift);
}

double YellowValue(int shift) { return BandCenterValue(IND_YELLOW, InpYellowHalfLength, shift); }
double GreenValue(int shift)  { return BandCenterValue(IND_GREEN, InpGreenHalfLength, shift); }

//--- ENTRY_YELLOW_ONLY: client's alternate idea — Yellow crossing White is the
//    entry trigger on its own, a discrete cross event (this is the primary
//    signal here, not a slow confirmation layered on something else, so a
//    real cross moment is the right check, same as his "Yellow confirmed
//    cross" chart annotation marks a specific bar, not an ongoing state).
int YellowCrossDir(int shift)
{
   double yellowNow  = YellowValue(shift);
   double yellowPrev = YellowValue(shift + 1);
   double whiteNow   = WhiteValue(shift);
   double whitePrev  = WhiteValue(shift + 1);

   if(yellowNow == EMPTY_VALUE || yellowPrev == EMPTY_VALUE ||
      whiteNow == EMPTY_VALUE || whitePrev == EMPTY_VALUE) return 0;

   bool wasAbove = yellowPrev > whitePrev;
   bool isAbove  = yellowNow  > whiteNow;

   if(isAbove && !wasAbove) return 1;    // Yellow crossed up through White
   if(!isAbove && wasAbove) return -1;   // Yellow crossed down through White
   return 0;
}

//--- Confirmed by client: "we only want to see both yellow/green have
//    crossed the White Dotted line." Tested as a discrete cross event for
//    each band independently first — over a full year of EURCHF H4 that
//    produced 0 trades, since Green (half length 40) is roughly twice as
//    slow as Yellow (half length 21) and essentially never crosses within
//    the same few-bar window Yellow does. Switched to a state check
//    instead: at the time of the signal, is Yellow on the far side of
//    White, AND is Green also on the far side of White. Matches how this
//    reads on a chart at a glance, and isn't fragile to the speed gap
//    between the two bands.
bool BandsAlignedAt(int dir, int shift)
{
   double yellowNow = YellowValue(shift);
   double greenNow  = GreenValue(shift);
   double whiteNow  = WhiteValue(shift);

   if(yellowNow == EMPTY_VALUE || greenNow == EMPTY_VALUE || whiteNow == EMPTY_VALUE)
      return false;

   if(dir > 0) return (yellowNow > whiteNow && greenNow > whiteNow);
   if(dir < 0) return (yellowNow < whiteNow && greenNow < whiteNow);
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
   int signalDir = (InpEntryMode == ENTRY_YELLOW_ONLY) ? YellowCrossDir(1) : MegaSignalDir(1);

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
