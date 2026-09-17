//+------------------------------------------------------------------+
//|                                              PtrStrategy_EA.mq4 |
//|                     Copyright 2026, Peter Johansson / pjohans1   |
//|                                                                  |
//| Automated Expert Advisor strictly implementing Peter's exact     |
//| 4-indicator trading strategy specifications:                     |
//| 1. Ptr Mega Trend (HMA 48 & HMA 78 crossover)                    |
//| 2. Yellow Ptr Arslan (Fast TMA bands: Dev 1.8, HalfLength 21)    |
//| 3. Norepaint zone 3 green (Slow TMA bands: Dev 1.8, HalfLength 40)|
//| 4. White Ptr Arslan (Centered TMA bands: Multiplier 2.8, HL 32)  |
//|                                                                  |
//| Selectable Strategy Modes:                                       |
//| - ENTRY_MEGA_PLUS_BANDS: Primary confirmed strategy (MegaTrend   |
//|   48/78 cross + Yellow & Green band confirmation past White)     |
//| - ENTRY_YELLOW_ONLY: Peter's alternate system (Yellow crosses    |
//|   White alone, no MegaTrend, no Green, as demonstrated on chart) |
//| - ENTRY_MEGA_ONLY: Pure MegaTrend 48/78 crossover alone          |
//|                                                                  |
//| Execution: Strictly on bar open following signal (IsNewBar)      |
//| Exits: Configurable via Properties (Fixed SL/TP, Stop & Reverse) |
//+------------------------------------------------------------------+
#property copyright "Peter Johansson / pjohans1 Strategy"
#property link      ""
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
{
   ENTRY_MEGA_PLUS_BANDS = 0, // MegaTrend 48/78 cross + Yellow & Green confirmed past White (Primary)
   ENTRY_YELLOW_ONLY     = 1, // Yellow crossing White alone, no MegaTrend, no Green (Alternate)
   ENTRY_MEGA_ONLY       = 2  // MegaTrend 48/78 cross alone, no band confirmation
};

enum ENUM_BAND_CONFIRM_MODE
{
   BAND_CONFIRM_OUTER_BANDS  = 0, // Outer Yellow & Green bands dip/push past White bands (Buy: Lower, Sell: Upper)
   BAND_CONFIRM_TMA_CENTERS  = 1, // Yellow & Green TMA centers cross/align past White TMA center
   BAND_CONFIRM_PRICE_PIERCE = 2, // Price Low/High pierces White dotted line, confirmed by Yellow/Green
   BAND_CONFIRM_ANY          = 3  // Either Outer Bands pierce OR TMA Centers align
};

enum ENUM_YELLOW_CROSS_MODE
{
   YELLOW_CROSS_OUTER_BANDS = 0, // Yellow Outer Band crosses/dips past White Outer Band
   YELLOW_CROSS_TMA_CENTER  = 1  // Yellow TMA Center crosses White TMA Center
};

enum ENUM_MEGA_TRIGGER
{
   MEGA_CROSS_48_78 = 0, // Fast HMA (48) crosses Slow HMA (78)
   MEGA_SINGLE_FLIP = 1  // Fast HMA (48) direction flip
};

enum ENUM_EXIT_MODE
{
   EXIT_FIXED_PIPS       = 0, // Fixed Stop Loss & Take Profit in pips
   EXIT_STOP_AND_REVERSE = 1  // Hold position until opposite confirmed signal, then reverse
};

//+------------------------------------------------------------------+
//| External Inputs                                                  |
//+------------------------------------------------------------------+
input group "=== 1. Strategy Entry Logic ==="
input ENUM_ENTRY_MODE        InpEntryMode              = ENTRY_MEGA_PLUS_BANDS; // Entry Strategy Mode
input ENUM_BAND_CONFIRM_MODE InpBandConfirmMode        = BAND_CONFIRM_ANY; // Band Confirmation Method
input ENUM_YELLOW_CROSS_MODE InpYellowCrossMode        = YELLOW_CROSS_OUTER_BANDS; // Yellow-Only Trigger Method
input ENUM_MEGA_TRIGGER      InpMegaTrigger            = MEGA_CROSS_48_78;      // MegaTrend Trigger Mode
input int                    InpConfirmLookbackBars    = 8;                     // Lookback window for band confirmation (bars)
input int                    InpConfirmTimeoutBars     = 5;                     // Max forward bars to wait for band confirm

input group "=== 2. Indicator Settings (Confirmed from Ptr Settings.pdf) ==="
input int                    InpMegaFastPeriod         = 48;    // Fast HMA Period (Linear Weighted, Close)
input int                    InpMegaSlowPeriod         = 78;    // Slow HMA Period (Linear Weighted, Close)
input int                    InpYellowHalfLength       = 21;    // Yellow TMA Half Length (Non-repainting)
input double                 InpYellowDev              = 1.8;   // Yellow Band Deviation
input int                    InpGreenHalfLength        = 40;    // Green TMA Half Length (Non-repainting)
input double                 InpGreenDev               = 1.8;   // Green Band Deviation
input int                    InpWhiteHalfLength        = 32;    // White Centered TMA Half Length
input int                    InpWhitePeriod            = 100;   // White Bands ATR Period
input double                 InpWhiteMultiplier        = 2.8;   // White Bands Multiplier (Weighted Price)
input string                 InpBandTimeFrame          = "60";  // Yellow/Green TimeFrame (60 = H1)

input group "=== 3. Trade & Risk Management ==="
input ENUM_EXIT_MODE         InpExitMode               = EXIT_FIXED_PIPS; // Exit Management Mode
input double                 InpLots                   = 0.10;            // Fixed Trade Volume
input int                    InpTakeProfitPips         = 50;              // Take Profit in pips
input int                    InpStopLossPips           = 50;              // Stop Loss in pips
input int                    InpTrailingStopPips       = 0;               // Trailing Stop in pips (0 = disabled)
input int                    InpMaxSpreadPoints        = 30;              // Maximum allowable spread in points
input int                    InpSlippage               = 10;              // Maximum slippage in points
input int                    InpMagicNumber            = 20260908;        // EA Magic Number

input group "=== 4. Optional Filters (Disabled by default) ==="
input bool                   InpUseRealStochFilter     = false; // Enable Real Stochastic(32,5,10) zone filter
input int                    InpStochKPeriod           = 32;    // Stochastic %K Period
input int                    InpStochDPeriod           = 5;     // Stochastic %D Period
input int                    InpStochSlowing           = 10;    // Stochastic Slowing
input double                 InpStochZoneUpper         = 90.0;  // Stochastic Overbought level (Sell zone)
input double                 InpStochZoneLower         = 10.0;  // Stochastic Oversold level (Buy zone)
input int                    InpStochZoneLookback      = 10;    // Lookback bars for Stochastic zone touch
input bool                   InpUseHmaStochFilter      = false; // Enable HMA-range extension filter
input int                    InpHmaStochPeriod         = 14;    // HMA range lookback bars
input double                 InpHmaStochLowerLevel     = 10.0;  // HMA range lower %K
input double                 InpHmaStochUpperLevel     = 90.0;  // HMA range upper %K
input bool                   InpUseDivergenceFilter    = false; // Enable Price/Stochastic Divergence filter
input int                    InpDivergenceSwingBars    = 3;     // Swing detection strength bars
input int                    InpDivergenceLookback     = 40;    // Divergence search window bars

input group "=== 5. Chart Display & Comments ==="
input bool                   InpShowOnChartDashboard   = true;  // Display real-time status overlay on chart

//+------------------------------------------------------------------+
//| Indicator Names (Must exist in MQL4\Indicators\)                 |
//+------------------------------------------------------------------+
#define IND_MEGA   "Ptr Mega Trend"
#define IND_YELLOW "Yellow Ptr Arslan"
#define IND_GREEN  "Norepaint zone 3 green"
#define IND_WHITE  "White Ptr Arslan"

//+------------------------------------------------------------------+
//| Global Variables & State Tracking                                |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
int      g_pointAdjust = 1;

struct SPendingMegaSignal
{
   bool     active;
   bool     confirmed;
   int      dir;         // +1 = Buy, -1 = Sell
   int      barsElapsed;
   datetime triggerTime;

   void Reset()
   {
      active = false;
      confirmed = false;
      dir = 0;
      barsElapsed = 0;
      triggerTime = 0;
   }
};
SPendingMegaSignal g_pendingMega;

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pointAdjust = (Digits == 3 || Digits == 5) ? 10 : 1;
   g_pendingMega.Reset();
   g_lastBarTime = 0;

   PrintFormat("[Init] PtrStrategy_EA v2.00 loaded | Symbol: %s | Period: %d | EntryMode: %s | BandConfirm: %s | ExitMode: %s",
               Symbol(), Period(), EnumToString(InpEntryMode), EnumToString(InpBandConfirmMode), EnumToString(InpExitMode));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| New Bar Detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   if(Time[0] == g_lastBarTime) return false;
   g_lastBarTime = Time[0];
   return true;
}

//+------------------------------------------------------------------+
//| Timeframe Resolver for Multi-Timeframe Indicators                |
//+------------------------------------------------------------------+
string GetBandTimeFrame()
{
   if(InpBandTimeFrame == "current" || InpBandTimeFrame == "0" || InpBandTimeFrame == "")
      return IntegerToString(Period());
   // In Strategy Tester, if requested TF is smaller than chart TF, MT4 does not load it
   if(IsTesting() && StringToInteger(InpBandTimeFrame) > 0 && StringToInteger(InpBandTimeFrame) < Period())
      return IntegerToString(Period());
   return InpBandTimeFrame;
}

//+------------------------------------------------------------------+
//| Indicator Helpers - Exact Buffer Mappings                        |
//+------------------------------------------------------------------+

//--- Ptr Mega Trend: Buffer 2 = HMA line
double MegaHMA(int period, int shift)
{
   return iCustom(NULL, 0, IND_MEGA, period, MODE_LWMA, PRICE_CLOSE, 0,
                  true, clrWhite, clrGold, STYLE_DOT, 1,
                  true, clrWhite, clrGold, 5, 233, 234, 1,
                  2, shift);
}

int MegaDir(int period, int shift)
{
   double cur  = MegaHMA(period, shift);
   double prev = MegaHMA(period, shift + 1);
   if(cur == EMPTY_VALUE || prev == EMPTY_VALUE) return 0;
   if(cur > prev) return 1;
   if(cur < prev) return -1;
   return 0;
}

//--- MegaTrend Trigger Direction on shift
int MegaSignalDir(int shift)
{
   if(InpMegaTrigger == MEGA_SINGLE_FLIP)
   {
      int dirNow  = MegaDir(InpMegaFastPeriod, shift);
      int dirPrev = MegaDir(InpMegaFastPeriod, shift + 1);
      if(dirNow != 0 && dirNow != dirPrev) return dirNow;
      return 0;
   }
   else // MEGA_CROSS_48_78 (Confirmed client default)
   {
      double fastNow  = MegaHMA(InpMegaFastPeriod, shift);
      double slowNow  = MegaHMA(InpMegaSlowPeriod, shift);
      double fastPrev = MegaHMA(InpMegaFastPeriod, shift + 1);
      double slowPrev = MegaHMA(InpMegaSlowPeriod, shift + 1);

      if(fastNow == EMPTY_VALUE || slowNow == EMPTY_VALUE ||
         fastPrev == EMPTY_VALUE || slowPrev == EMPTY_VALUE) return 0;

      bool wasAbove = fastPrev > slowPrev;
      bool isAbove  = fastNow  > slowNow;

      if(isAbove && !wasAbove) return 1;    // Fast crossed above Slow -> BUY
      if(!isAbove && wasAbove) return -1;   // Fast crossed below Slow -> SELL
      return 0;
   }
}

//--- White Ptr Arslan Buffers: 0=Center, 3=Upper Dotted Band, 4=Lower Dotted Band
double WhiteCenter(int shift)
{
   return iCustom(NULL, 0, IND_WHITE, InpWhiteHalfLength, 6, InpWhitePeriod, InpWhiteMultiplier, 0, shift);
}

double WhiteUpper(int shift)
{
   return iCustom(NULL, 0, IND_WHITE, InpWhiteHalfLength, 6, InpWhitePeriod, InpWhiteMultiplier, 3, shift);
}

double WhiteLower(int shift)
{
   return iCustom(NULL, 0, IND_WHITE, InpWhiteHalfLength, 6, InpWhitePeriod, InpWhiteMultiplier, 4, shift);
}

//--- Yellow Ptr Arslan Buffers: 0=Center, 1=Upper Dotted Band, 2=Lower Dotted Band
double YellowCenter(int shift)
{
   return iCustom(NULL, 0, IND_YELLOW, GetBandTimeFrame(), InpYellowHalfLength,
                  PRICE_CLOSE, InpYellowDev, false, false, false, false, true, 0, shift);
}

double YellowUpper(int shift)
{
   return iCustom(NULL, 0, IND_YELLOW, GetBandTimeFrame(), InpYellowHalfLength,
                  PRICE_CLOSE, InpYellowDev, false, false, false, false, true, 1, shift);
}

double YellowLower(int shift)
{
   return iCustom(NULL, 0, IND_YELLOW, GetBandTimeFrame(), InpYellowHalfLength,
                  PRICE_CLOSE, InpYellowDev, false, false, false, false, true, 2, shift);
}

//--- Norepaint zone 3 green Buffers: 0=Center, 1=Upper Dotted Band, 2=Lower Dotted Band
double GreenCenter(int shift)
{
   return iCustom(NULL, 0, IND_GREEN, GetBandTimeFrame(), InpGreenHalfLength,
                  PRICE_CLOSE, InpGreenDev, false, false, false, false, true, 0, shift);
}

double GreenUpper(int shift)
{
   return iCustom(NULL, 0, IND_GREEN, GetBandTimeFrame(), InpGreenHalfLength,
                  PRICE_CLOSE, InpGreenDev, false, false, false, false, true, 1, shift);
}

double GreenLower(int shift)
{
   return iCustom(NULL, 0, IND_GREEN, GetBandTimeFrame(), InpGreenHalfLength,
                  PRICE_CLOSE, InpGreenDev, false, false, false, false, true, 2, shift);
}

//+------------------------------------------------------------------+
//| Band Confirmation Helpers                                        |
//+------------------------------------------------------------------+
// Checks if Yellow and Green crossed or aligned with White within lookback window
bool CheckBandConfirmation(int dir, int shift, int lookbackBars)
{
   bool yellowConfirmed = false;
   bool greenConfirmed  = false;

   for(int k = shift; k < shift + lookbackBars; k++)
   {
      double yUp = YellowUpper(k);
      double yDn = YellowLower(k);
      double yCe = YellowCenter(k);

      double gUp = GreenUpper(k);
      double gDn = GreenLower(k);
      double gCe = GreenCenter(k);

      double wUp = WhiteUpper(k);
      double wDn = WhiteLower(k);
      double wCe = WhiteCenter(k);

      if(wUp == EMPTY_VALUE || wDn == EMPTY_VALUE || yUp == EMPTY_VALUE || gUp == EMPTY_VALUE)
         continue;

      if(dir > 0) // BUY Confirmation: oversold zone touch/pierce past Lower White
      {
         switch(InpBandConfirmMode)
         {
            case BAND_CONFIRM_OUTER_BANDS:
               if(yDn <= wDn) yellowConfirmed = true;
               if(gDn <= wDn) greenConfirmed  = true;
               break;

            case BAND_CONFIRM_TMA_CENTERS:
               if(yCe > wCe) yellowConfirmed = true;
               if(gCe > wCe) greenConfirmed  = true;
               break;

            case BAND_CONFIRM_PRICE_PIERCE:
               if(Low[k] <= wDn)
               {
                  yellowConfirmed = true;
                  greenConfirmed  = true;
               }
               break;

            case BAND_CONFIRM_ANY:
               if(yDn <= wDn || yCe > wCe) yellowConfirmed = true;
               if(gDn <= wDn || gCe > wCe) greenConfirmed  = true;
               break;
         }
      }
      else if(dir < 0) // SELL Confirmation: overbought zone touch/pierce past Upper White
      {
         switch(InpBandConfirmMode)
         {
            case BAND_CONFIRM_OUTER_BANDS:
               if(yUp >= wUp) yellowConfirmed = true;
               if(gUp >= wUp) greenConfirmed  = true;
               break;

            case BAND_CONFIRM_TMA_CENTERS:
               if(yCe < wCe) yellowConfirmed = true;
               if(gCe < wCe) greenConfirmed  = true;
               break;

            case BAND_CONFIRM_PRICE_PIERCE:
               if(High[k] >= wUp)
               {
                  yellowConfirmed = true;
                  greenConfirmed  = true;
               }
               break;

            case BAND_CONFIRM_ANY:
               if(yUp >= wUp || yCe < wCe) yellowConfirmed = true;
               if(gUp >= wUp || gCe < wCe) greenConfirmed  = true;
               break;
         }
      }

      if(yellowConfirmed && greenConfirmed)
         return true;
   }

   return (yellowConfirmed && greenConfirmed);
}

//+------------------------------------------------------------------+
//| Alternate Strategy Trigger: Yellow Crosses White Alone           |
//+------------------------------------------------------------------+
int YellowOnlySignalDir(int shift)
{
   if(InpYellowCrossMode == YELLOW_CROSS_OUTER_BANDS)
   {
      double yDnNow  = YellowLower(shift);
      double yDnPrev = YellowLower(shift + 1);
      double wDnNow  = WhiteLower(shift);
      double wDnPrev = WhiteLower(shift + 1);

      double yUpNow  = YellowUpper(shift);
      double yUpPrev = YellowUpper(shift + 1);
      double wUpNow  = WhiteUpper(shift);
      double wUpPrev = WhiteUpper(shift + 1);

      if(yDnNow == EMPTY_VALUE || yDnPrev == EMPTY_VALUE ||
         wDnNow == EMPTY_VALUE || wDnPrev == EMPTY_VALUE ||
         yUpNow == EMPTY_VALUE || yUpPrev == EMPTY_VALUE ||
         wUpNow == EMPTY_VALUE || wUpPrev == EMPTY_VALUE) return 0;

      // BUY: Yellow Lower crosses/pierces White Lower and starts bouncing, or penetrates down
      bool dippedBelowLower = (yDnNow <= wDnNow && yDnPrev > wDnPrev);
      bool hookedUpFromLower = (yDnNow > wDnNow && yDnPrev <= wDnPrev);
      if(dippedBelowLower || hookedUpFromLower) return 1;

      // SELL: Yellow Upper crosses/pierces White Upper and starts turning, or penetrates up
      bool pushedAboveUpper = (yUpNow >= wUpNow && yUpPrev < wUpPrev);
      bool hookedDownFromUpper = (yUpNow < wUpNow && yUpPrev >= wUpPrev);
      if(pushedAboveUpper || hookedDownFromUpper) return -1;

      return 0;
   }
   else // YELLOW_CROSS_TMA_CENTER
   {
      double yCeNow  = YellowCenter(shift);
      double yCePrev = YellowCenter(shift + 1);
      double wCeNow  = WhiteCenter(shift);
      double wCePrev = WhiteCenter(shift + 1);

      if(yCeNow == EMPTY_VALUE || yCePrev == EMPTY_VALUE ||
         wCeNow == EMPTY_VALUE || wCePrev == EMPTY_VALUE) return 0;

      bool crossedUp = (yCeNow > wCeNow && yCePrev <= wCePrev);
      bool crossedDn = (yCeNow < wCeNow && yCePrev >= wCePrev);

      if(crossedUp) return 1;
      if(crossedDn) return -1;
      return 0;
   }
}

//+------------------------------------------------------------------+
//| Optional Filters                                                 |
//+------------------------------------------------------------------+
bool PassesRealStochFilter(int dir, int shift)
{
   if(!InpUseRealStochFilter) return true;

   for(int i = shift; i < shift + InpStochZoneLookback; i++)
   {
      double k = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing,
                             MODE_SMA, 0, MODE_MAIN, i);
      if(k == EMPTY_VALUE) continue;

      if(dir > 0 && k <= InpStochZoneLower) return true;
      if(dir < 0 && k >= InpStochZoneUpper) return true;
   }
   return false;
}

bool PassesHmaStochFilter(int dir, int shift)
{
   if(!InpUseHmaStochFilter) return true;

   double first = MegaHMA(InpMegaFastPeriod, shift);
   if(first == EMPTY_VALUE) return false;

   double hi = first, lo = first;
   for(int i = shift + 1; i < shift + InpHmaStochPeriod; i++)
   {
      double v = MegaHMA(InpMegaFastPeriod, i);
      if(v == EMPTY_VALUE) return false;
      if(v > hi) hi = v;
      if(v < lo) lo = v;
   }
   if(hi == lo) return false;
   double k = (first - lo) / (hi - lo) * 100.0;

   if(dir > 0) return (k <= InpHmaStochLowerLevel);
   if(dir < 0) return (k >= InpHmaStochUpperLevel);
   return false;
}

int FindSwingPoint(bool isHigh, int startShift, int endShift)
{
   for(int i = startShift; i <= endShift; i++)
   {
      double target = isHigh ? iHigh(NULL, 0, i) : iLow(NULL, 0, i);
      bool isSwing = true;
      for(int j = 1; j <= InpDivergenceSwingBars; j++)
      {
         if(i - j < 0) { isSwing = false; break; }
         if(isHigh)
         {
            if(iHigh(NULL, 0, i - j) > target || iHigh(NULL, 0, i + j) > target)
               { isSwing = false; break; }
         }
         else
         {
            if(iLow(NULL, 0, i - j) < target || iLow(NULL, 0, i + j) < target)
               { isSwing = false; break; }
         }
      }
      if(isSwing) return i;
   }
   return -1;
}

bool PassesDivergenceFilter(int dir, int shift)
{
   if(!InpUseDivergenceFilter) return true;

   if(dir > 0) // Bullish divergence
   {
      int swingOld = FindSwingPoint(false, shift + InpDivergenceSwingBars, shift + InpDivergenceLookback);
      if(swingOld < 0) return false;
      int swingNew = FindSwingPoint(false, shift, swingOld - InpDivergenceSwingBars - 1);
      if(swingNew < 0) return false;

      double priceOld = iLow(NULL, 0, swingOld);
      double priceNew = iLow(NULL, 0, swingNew);
      double stochOld = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, 0, MODE_MAIN, swingOld);
      double stochNew = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, 0, MODE_MAIN, swingNew);
      if(stochOld == EMPTY_VALUE || stochNew == EMPTY_VALUE) return false;

      return (priceNew < priceOld && stochNew > stochOld);
   }
   else if(dir < 0) // Bearish divergence
   {
      int swingOld = FindSwingPoint(true, shift + InpDivergenceSwingBars, shift + InpDivergenceLookback);
      if(swingOld < 0) return false;
      int swingNew = FindSwingPoint(true, shift, swingOld - InpDivergenceSwingBars - 1);
      if(swingNew < 0) return false;

      double priceOld = iHigh(NULL, 0, swingOld);
      double priceNew = iHigh(NULL, 0, swingNew);
      double stochOld = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, 0, MODE_MAIN, swingOld);
      double stochNew = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, 0, MODE_MAIN, swingNew);
      if(stochOld == EMPTY_VALUE || stochNew == EMPTY_VALUE) return false;

      return (priceNew > priceOld && stochNew < stochOld);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trade Execution & Position Management                            |
//+------------------------------------------------------------------+
bool FindOpenPosition(int &ticket, bool &isBuy, double &lots, double &openPrice)
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      ticket    = OrderTicket();
      isBuy     = (OrderType() == OP_BUY);
      lots      = OrderLots();
      openPrice = OrderOpenPrice();
      return true;
   }
   return false;
}

void ClosePosition(int ticket, bool isBuy)
{
   double closePrice = isBuy ? Bid : Ask;
   RefreshRates();
   if(!OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrOrange))
   {
      PrintFormat("[Trade Error] Failed to close ticket #%d: error %d", ticket, GetLastError());
   }
   else
   {
      PrintFormat("[Trade] Closed position ticket #%d at %.5f", ticket, closePrice);
   }
}

void ApplyTrailingStop(int ticket, bool isBuy)
{
   if(InpTrailingStopPips <= 0) return;

   double trailDist = InpTrailingStopPips * g_pointAdjust * Point;
   RefreshRates();

   if(isBuy)
   {
      double newSL = NormalizeDouble(Bid - trailDist, Digits);
      if(Bid - OrderOpenPrice() > trailDist)
      {
         if(OrderStopLoss() < newSL || OrderStopLoss() == 0)
         {
            if(!OrderModify(ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue))
               PrintFormat("[Trade Error] Trailing stop modify failed for buy #%d: error %d", ticket, GetLastError());
         }
      }
   }
   else
   {
      double newSL = NormalizeDouble(Ask + trailDist, Digits);
      if(OrderOpenPrice() - Ask > trailDist)
      {
         if(OrderStopLoss() > newSL || OrderStopLoss() == 0)
         {
            if(!OrderModify(ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed))
               PrintFormat("[Trade Error] Trailing stop modify failed for sell #%d: error %d", ticket, GetLastError());
         }
      }
   }
}

void OpenTrade(int dir)
{
   RefreshRates();
   double spread = (Ask - Bid) / Point;
   if(spread > InpMaxSpreadPoints)
   {
      PrintFormat("[Trade] Blocked: spread (%.1f pts) exceeds max allowable (%.1f pts)", spread, (double)InpMaxSpreadPoints);
      return;
   }

   int openTicket = -1;
   bool openIsBuy = false;
   double openLots = 0, openPx = 0;
   bool hasPos = FindOpenPosition(openTicket, openIsBuy, openLots, openPx);

   // Handle Stop & Reverse
   if(hasPos)
   {
      if((dir > 0 && !openIsBuy) || (dir < 0 && openIsBuy))
      {
         if(InpExitMode == EXIT_STOP_AND_REVERSE)
         {
            PrintFormat("[Trade] Stop & Reverse triggered. Closing opposite ticket #%d", openTicket);
            ClosePosition(openTicket, openIsBuy);
         }
         else
         {
            PrintFormat("[Trade] Position already open in opposite direction (ticket #%d). New entry skipped.", openTicket);
            return;
         }
      }
      else
      {
         // Already long and got Buy, or already short and got Sell
         return;
      }
   }

   RefreshRates();
   double price = (dir > 0) ? Ask : Bid;
   double sl = 0, tp = 0;

   if(InpExitMode == EXIT_FIXED_PIPS)
   {
      double slDist = InpStopLossPips   * g_pointAdjust * Point;
      double tpDist = InpTakeProfitPips * g_pointAdjust * Point;
      sl = (dir > 0) ? NormalizeDouble(price - slDist, Digits) : NormalizeDouble(price + slDist, Digits);
      tp = (dir > 0) ? NormalizeDouble(price + tpDist, Digits) : NormalizeDouble(price - tpDist, Digits);
   }

   int ticket = OrderSend(Symbol(), (dir > 0) ? OP_BUY : OP_SELL, InpLots,
                          price, InpSlippage, sl, tp,
                          "PtrStrategy", InpMagicNumber, 0,
                          (dir > 0) ? clrBlue : clrRed);

   if(ticket < 0)
   {
      PrintFormat("[Trade Error] OrderSend failed (%s) at %.5f: error %d",
                  (dir > 0) ? "BUY" : "SELL", price, GetLastError());
   }
   else
   {
      PrintFormat("[Trade] Executed %s #%d at %.5f | SL: %.5f | TP: %.5f | Lots: %.2f",
                  (dir > 0) ? "BUY" : "SELL", ticket, price, sl, tp, InpLots);
   }
}

//+------------------------------------------------------------------+
//| Real-time Chart Dashboard                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpShowOnChartDashboard) return;

   int openTicket = -1;
   bool openIsBuy = false;
   double openLots = 0, openPx = 0;
   bool hasPos = FindOpenPosition(openTicket, openIsBuy, openLots, openPx);

   double h48 = MegaHMA(InpMegaFastPeriod, 1);
   double h78 = MegaHMA(InpMegaSlowPeriod, 1);
   double yUp = YellowUpper(1);
   double yDn = YellowLower(1);
   double gUp = GreenUpper(1);
   double gDn = GreenLower(1);
   double wUp = WhiteUpper(1);
   double wDn = WhiteLower(1);

   string posText = "None";
   if(hasPos)
   {
      posText = StringFormat("#%d %s %.2f @ %.5f | PnL: %.2f USD",
                             openTicket, openIsBuy ? "BUY" : "SELL", openLots, openPx, OrderProfit());
   }

   string dash = "========================================\n";
   dash += "   PTR STRATEGY EA v2.00 (Peter Johansson)\n";
   dash += "========================================\n";
   dash += StringFormat(" Mode: %s\n", EnumToString(InpEntryMode));
   dash += StringFormat(" Exit Method: %s\n", EnumToString(InpExitMode));
   dash += StringFormat(" MegaTrend HMA(48): %.5f | HMA(78): %.5f [%s]\n",
                        h48, h78, (h48 > h78) ? "BULLISH" : "BEARISH");
   dash += StringFormat(" Yellow Bands: Upper=%.5f | Lower=%.5f\n", yUp, yDn);
   dash += StringFormat(" Green Bands:  Upper=%.5f | Lower=%.5f\n", gUp, gDn);
   dash += StringFormat(" White Bands:  Upper=%.5f | Lower=%.5f\n", wUp, wDn);
   dash += StringFormat(" Spread: %.1f pts | Active Position: %s\n", (Ask - Bid)/Point, posText);
   if(g_pendingMega.active)
   {
      dash += StringFormat(" [Pending Mega Cross]: %s (%d/%d bars elapsed)\n",
                           (g_pendingMega.dir > 0) ? "BUY" : "SELL",
                           g_pendingMega.barsElapsed, InpConfirmTimeoutBars);
   }
   dash += "========================================";

   Comment(dash);
}

//+------------------------------------------------------------------+
//| OnTick Event Handler                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Maintain Trailing Stop on active positions on each tick
   int activeTicket = -1;
   bool activeIsBuy = false;
   double activeLots = 0, activePx = 0;
   if(FindOpenPosition(activeTicket, activeIsBuy, activeLots, activePx))
   {
      ApplyTrailingStop(activeTicket, activeIsBuy);
   }

   // 2. Update dashboard comment
   UpdateDashboard();

   // 3. Execution strictly on bar open (IsNewBar) per Peter's rule:
   // "enter on the following opening candle"
   if(!IsNewBar()) return;

   int signalToExecute = 0;

   //-----------------------------------------------------------------
   // Strategy Mode 1: ENTRY_MEGA_PLUS_BANDS (Peter's Primary System)
   //-----------------------------------------------------------------
   if(InpEntryMode == ENTRY_MEGA_PLUS_BANDS)
   {
      int freshMegaDir = MegaSignalDir(1);
      if(freshMegaDir != 0)
      {
         g_pendingMega.Reset();
         g_pendingMega.active      = true;
         g_pendingMega.dir         = freshMegaDir;
         g_pendingMega.barsElapsed = 0;
         g_pendingMega.triggerTime = Time[1];

         // Check if band confirmation was already met leading into or at this cross
         if(CheckBandConfirmation(freshMegaDir, 1, InpConfirmLookbackBars))
         {
            g_pendingMega.confirmed = true;
            PrintFormat("[Signal] MegaTrend %s cross WITH Band Confirmation satisfied -> executing at open!",
                        (freshMegaDir > 0) ? "BUY" : "SELL");
         }
         else
         {
            PrintFormat("[Signal] MegaTrend %s cross detected. Waiting up to %d bars for band alignment...",
                        (freshMegaDir > 0) ? "BUY" : "SELL", InpConfirmTimeoutBars);
         }
      }
      else if(g_pendingMega.active && !g_pendingMega.confirmed)
      {
         g_pendingMega.barsElapsed++;

         if(CheckBandConfirmation(g_pendingMega.dir, 1, 1))
         {
            g_pendingMega.confirmed = true;
            PrintFormat("[Signal] Band Confirmation received for pending %s signal (%d bars elapsed)!",
                        (g_pendingMega.dir > 0) ? "BUY" : "SELL", g_pendingMega.barsElapsed);
         }
         else if(g_pendingMega.barsElapsed >= InpConfirmTimeoutBars)
         {
            PrintFormat("[Signal] Pending %s timed out after %d bars without band confirmation. Resetting.",
                        (g_pendingMega.dir > 0) ? "BUY" : "SELL", g_pendingMega.barsElapsed);
            g_pendingMega.Reset();
         }
      }

      if(g_pendingMega.active && g_pendingMega.confirmed)
      {
         signalToExecute = g_pendingMega.dir;
         g_pendingMega.Reset();
      }
   }

   //-----------------------------------------------------------------
   // Strategy Mode 2: ENTRY_YELLOW_ONLY (Peter's Alternate System)
   //-----------------------------------------------------------------
   else if(InpEntryMode == ENTRY_YELLOW_ONLY)
   {
      int yellowSig = YellowOnlySignalDir(1);
      if(yellowSig != 0)
      {
         PrintFormat("[Signal] ENTRY_YELLOW_ONLY triggered: %s", (yellowSig > 0) ? "BUY" : "SELL");
         signalToExecute = yellowSig;
      }
   }

   //-----------------------------------------------------------------
   // Strategy Mode 3: ENTRY_MEGA_ONLY (Pure MegaTrend 48/78 Cross)
   //-----------------------------------------------------------------
   else if(InpEntryMode == ENTRY_MEGA_ONLY)
   {
      int megaSig = MegaSignalDir(1);
      if(megaSig != 0)
      {
         PrintFormat("[Signal] ENTRY_MEGA_ONLY triggered: %s", (megaSig > 0) ? "BUY" : "SELL");
         signalToExecute = megaSig;
      }
   }

   //-----------------------------------------------------------------
   // 4. Filter Verification & Trade Execution
   //-----------------------------------------------------------------
   if(signalToExecute != 0)
   {
      // Verify optional filters if enabled
      if(!PassesRealStochFilter(signalToExecute, 1))
      {
         PrintFormat("[Filter] Trade %s blocked by Real Stochastic filter.", (signalToExecute > 0) ? "BUY" : "SELL");
         return;
      }
      if(!PassesHmaStochFilter(signalToExecute, 1))
      {
         PrintFormat("[Filter] Trade %s blocked by HMA Stochastic filter.", (signalToExecute > 0) ? "BUY" : "SELL");
         return;
      }
      if(!PassesDivergenceFilter(signalToExecute, 1))
      {
         PrintFormat("[Filter] Trade %s blocked by Divergence filter.", (signalToExecute > 0) ? "BUY" : "SELL");
         return;
      }

      // Execute Trade
      OpenTrade(signalToExecute);
   }
}
//+------------------------------------------------------------------+
