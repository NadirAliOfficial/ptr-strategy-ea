//+------------------------------------------------------------------+
//| PtrStrategy_EA.mq4                                                |
//| Trades the Ptr indicator set: MegaTrend (HMA) + Yellow/Green      |
//| no-repaint TMA bands, White TMA kept for visual reference only.   |
//|                                                                    |
//| Two open questions from the client are not guessed into fixed     |
//| behaviour, they are switches — see README.md in this repo for     |
//| the exact wording of what's confirmed vs still pending:           |
//|   InpEntryMode    — MegaTrend alone, or MegaTrend + band confirm  |
//|   InpMegaTrigger  — single HMA(48) flip, or HMA(48)/HMA(78) cross |
//|   InpExitMode     — fixed pips, or hold-and-reverse               |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
{
   ENTRY_MEGA_ONLY,        // MegaTrend flip alone triggers entry
   ENTRY_MEGA_PLUS_BANDS   // MegaTrend flip + Yellow/Green band confirm
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
//| Inputs — pending client confirmation (see README)                 |
//+------------------------------------------------------------------+
input group "=== PENDING CLIENT CONFIRMATION (see README) ==="
input ENUM_ENTRY_MODE   InpEntryMode         = ENTRY_MEGA_PLUS_BANDS;
input ENUM_MEGA_TRIGGER InpMegaTrigger       = MEGA_SINGLE_FLIP;
input ENUM_EXIT_MODE    InpExitMode          = EXIT_FIXED_PIPS;
input int               InpConfirmTimeoutBars = 3;      // Bars allowed for band confirm after a Mega flip

//+------------------------------------------------------------------+
//| Inputs — indicator settings, confirmed from client's settings sheet|
//+------------------------------------------------------------------+
input group "=== Indicator Settings (confirmed) ==="
input int    InpMegaFastPeriod  = 48;     // Ptr Mega Trend HMA period (fast)
input int    InpMegaSlowPeriod  = 78;     // Ptr Mega Trend HMA period (slow)
input int    InpYellowHalfLength = 21;    // Yellow Ptr Arslan half length
input int    InpGreenHalfLength  = 40;    // Norepaint zone 3 green half length
input int    InpWhiteHalfLength  = 32;    // White Ptr Arslan half length (visual only)
input int    InpWhitePeriod      = 100;   // White Ptr Arslan bands period (visual only)
input double InpWhiteMultiplier  = 2.8;   // White Ptr Arslan bands deviation (visual only)
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
   int      barsSeen;    // bars spent waiting for band confirmation

   void Reset() { active = false; confirmed = false; dir = 0; barsSeen = 0; }
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
//| Yellow / Green band helpers — reversal arrows built into each     |
//| indicator (buffer 3 = down arrow, buffer 4 = up arrow)            |
//+------------------------------------------------------------------+
bool BandUpArrow(string indName, int halfLength, int shift)
{
   double v = iCustom(NULL, 0, indName, InpBandTimeFrame, halfLength,
                       PRICE_CLOSE, 1.8, false, false, false, false, true,
                       4, shift);
   return (v != EMPTY_VALUE);
}

bool BandDownArrow(string indName, int halfLength, int shift)
{
   double v = iCustom(NULL, 0, indName, InpBandTimeFrame, halfLength,
                       PRICE_CLOSE, 1.8, false, false, false, false, true,
                       3, shift);
   return (v != EMPTY_VALUE);
}

bool YellowUpArrow(int shift)   { return BandUpArrow(IND_YELLOW, InpYellowHalfLength, shift); }
bool YellowDownArrow(int shift) { return BandDownArrow(IND_YELLOW, InpYellowHalfLength, shift); }
bool GreenUpArrow(int shift)    { return BandUpArrow(IND_GREEN, InpGreenHalfLength, shift); }
bool GreenDownArrow(int shift)  { return BandDownArrow(IND_GREEN, InpGreenHalfLength, shift); }

//--- true if either Yellow or Green fired a same-direction reversal
//    arrow on the given closed bar
bool BandsConfirmAt(int dir, int shift)
{
   if(dir > 0) return (YellowUpArrow(shift) || GreenUpArrow(shift));
   if(dir < 0) return (YellowDownArrow(shift) || GreenDownArrow(shift));
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

   //--- 2) Fresh MegaTrend flip on the bar that just closed (shift=1)
   int megaDir = MegaSignalDir(1);
   if(megaDir != 0 && (!g_pending.active || g_pending.dir != megaDir))
   {
      g_pending.active    = true;
      g_pending.confirmed = (InpEntryMode == ENTRY_MEGA_ONLY);
      g_pending.dir       = megaDir;
      g_pending.barsSeen  = 0;

      Print("[Signal] MegaTrend ", megaDir > 0 ? "BUY" : "SELL",
            InpEntryMode == ENTRY_MEGA_ONLY
               ? " — executing next open."
               : " — waiting up to " + IntegerToString(InpConfirmTimeoutBars) + " bars for band confirmation.");
   }

   //--- 3) Still waiting on Yellow/Green band confirmation
   if(g_pending.active && !g_pending.confirmed)
   {
      g_pending.barsSeen++;

      if(BandsConfirmAt(g_pending.dir, 1))
      {
         g_pending.confirmed = true;
         Print("[Signal] Band confirmation received, executing next open.");
      }
      else if(g_pending.barsSeen >= InpConfirmTimeoutBars)
      {
         Print("[Signal] Band confirmation timed out after ", g_pending.barsSeen, " bars, discarding.");
         g_pending.Reset();
      }
   }
}
