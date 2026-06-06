//+------------------------------------------------------------------+
//|                                         GoldStuff_TrendGrid_EA.mq5|
//|                              Gold Specialist - Trend + Grid Recovery|
//|                              Version 3.2 - Pip-Adaptive + ATR-Based|
//+------------------------------------------------------------------+
#property copyright "GoldStuff EA"
#property link      ""
#property version   "3.20"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
{
   MODE_TREND_ONLY = 0,        // Trend Following Only
   MODE_TREND_GRID = 1,        // Trend + Grid Recovery (Recommended)
   MODE_GRID_ONLY = 2          // Grid Recovery Only
};

enum ENUM_TREND_METHOD
{
   TREND_EMA_CROSS = 0,       // EMA Crossover
   TREND_RSI_EMA = 1,         // RSI + EMA Confirmation
   TREND_MULTI = 2            // Multi-Indicator (EMA+RSI+ADX)
};

enum ENUM_GRID_STYLE
{
   GRID_FIXED = 0,             // Fixed Grid Distance
   GRID_ATR = 1,               // ATR-Based Dynamic Grid
   GRID_FIBONACCI = 2          // Fibonacci Grid Levels
};

//+------------------------------------------------------------------+
//| USER INPUT PARAMETERS (only key adjustable ones)                   |
//+------------------------------------------------------------------+
input string            S1                 = "===== MAIN SETTINGS =====";
input ulong             MagicNumber        = 777001;     // Magic Number
input ENUM_SIGNAL_MODE  SignalMode         = MODE_TREND_GRID; // Signal Mode
input ENUM_TREND_METHOD TrendMethod       = TREND_MULTI;   // Trend Method
input ENUM_GRID_STYLE   GridStyle         = GRID_ATR;      // Grid Style

input string            S2                 = "===== LOT & RISK =====";
input double            RiskPercent        = 1.0;         // Risk % Per Trade
input double            FixedLot           = 0.01;        // Fixed Lot (if AutoLot=false)
input bool              AutoLot            = true;        // Auto Lot Sizing
input int               MaxOpenTrades      = 10;          // Max Open Trades
input double            MaxDailyDrawdown   = 5.0;         // Max Daily DD %

input string            S3                 = "===== TRADE MANAGEMENT =====";
input int               i_StopLoss         = 500;         // SL (display only, ATR used)
input int               i_TakeProfit       = 300;         // TP (display only, ATR used)
input bool              EnableGrid         = true;        // Enable Grid Recovery
input int               MaxGridLevels      = 8;           // Max Grid Levels
input bool              CloseOnFriday      = true;        // Close All on Friday
input bool              CloseOnOpposite    = true;        // Close Opposite Signal
input int               Slippage           = 30;          // Slippage (points)

input string            S4                 = "===== DISPLAY =====";
input bool              ShowDashboard      = true;        // Show Dashboard
input bool              EnableAlerts       = true;        // Enable Alerts

//+------------------------------------------------------------------+
//| HARDCODED OPTIMIZED SETTINGS (tester CANNOT override these)       |
//+------------------------------------------------------------------+
string  EA_Comment          = "GoldStuff_TG";

//--- SL/TP: NOW IN PIPS (not raw points). Converted to points in OnInit().
int     StopLoss_pips        = 500;    // 500 pips
int     TakeProfit_pips      = 300;    // 300 pips

//--- Actual SL/TP in points (computed in OnInit based on pip size)
double  StopLoss_price       = 0;     // In price units
double  TakeProfit_price     = 0;     // In price units

//--- Lot limits
double  MinLot               = 0.01;
double  MaxLot               = 5.0;

//--- Trend indicator periods (optimized for XAUUSD M15)
int     FastEMA_Period       = 8;
int     SlowEMA_Period       = 21;
int     TrendEMA_Period      = 50;    // 0 = disabled
int     RSI_Period           = 10;
int     RSI_Overbought       = 75;
int     RSI_Oversold         = 25;
int     ADX_Period           = 10;
int     ADX_Threshold        = 15;

//--- Grid recovery - in ATR multiples (auto-scales to any symbol/price)
double  GridATR_Mult         = 1.2;    // Grid distance = ATR * this
double  GridMultiplier       = 1.4;    // Lot multiplier per level
double  GridTP_ATR_Mult      = 1.5;    // Grid TP = ATR * this
bool    GridBreakeven        = true;
int     ATR_Period           = 10;

//--- Exit management - in ATR multiples (auto-scales)
bool    EnableTrailingStop   = true;
double  TrailStart_ATR_Mult  = 1.0;   // Trailing starts at ATR * this
double  TrailStep_ATR_Mult    = 0.2;   // Trailing step = ATR * this
bool    EnableBreakeven       = true;
double  BreakevenStart_ATR    = 0.7;   // Breakeven starts at ATR * this
double  BreakevenProfit_ATR   = 0.1;   // Breakeven profit = ATR * this

//--- SL/TP in ATR multiples (auto-scales to any symbol)
double  SL_ATR_Mult          = 2.5;    // StopLoss = ATR * this
double  TP_ATR_Mult          = 1.5;    // TakeProfit = ATR * this

//--- Time & filters
bool    UseTimeFilter        = false;
int     StartHour            = 0;
int     EndHour              = 24;
double  MaxSpread_price      = 0;      // Auto-set in OnInit (0.5% of ATR)
int     MinBarsBetween       = 1;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
double g_Point;
int    g_Digits;
int    g_StopLevel;           // In points (from broker)
double g_StopLevel_price;     // In price units
double g_MinLot;
double g_MaxLot;
double g_LotStep;
double g_PipValue;            // Price value of 1 pip (auto-detected)
int    g_PipSize;             // Points per pip (auto-detected)
datetime g_LastBarTime = 0;
datetime g_LastTradeTime = 0;
double g_DailyStartEquity = 0;
double g_PeakEquity = 0;
int    g_GridBuyCount = 0;
int    g_GridSellCount = 0;
double g_ATR = 0;             // Current ATR value (price units)

// Diagnostic counters
int    g_TotalBars = 0;
int    g_SignalsGenerated = 0;
int    g_SpreadBlocks = 0;
bool   g_DiagPrinted = false;

// Trade object
CTrade trade;

// Indicator handles
int g_HandleFastEMA;
int g_HandleSlowEMA;
int g_HandleTrendEMA;
int g_HandleRSI;
int g_HandleADX;
int g_HandleATR;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Point = _Point;
   g_Digits = _Digits;
   g_StopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_MinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_MaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_LotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(g_MinLot == 0) g_MinLot = 0.01;
   if(g_LotStep == 0) g_LotStep = 0.01;
   
   //--- Auto-detect pip size based on symbol point/digits
   // For XAUUSD: Point=0.001, Digits=3 -> PipSize=10 ($0.01 per pip)
   // For XAUUSD: Point=0.01, Digits=2 -> PipSize=1 ($0.01 per pip)
   // For EURUSD: Point=0.00001, Digits=5 -> PipSize=10
   // For EURUSD: Point=0.0001, Digits=4 -> PipSize=1
   if(g_Digits == 5 || g_Digits == 3)
      g_PipSize = 10;     // 10 points per pip
   else if(g_Digits == 4 || g_Digits == 2)
      g_PipSize = 1;      // 1 point per pip
   else
      g_PipSize = 1;
   
   g_PipValue = g_Point * g_PipSize;  // Price value of 1 pip
   
   g_StopLevel_price = g_StopLevel * g_Point;
   
   //--- Setup trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   //--- Auto-detect best filling mode for this symbol
   ENUM_ORDER_TYPE_FILLING filling = GetBestFilling();
   trade.SetTypeFilling(filling);
   Print("Filling mode set to: ", EnumToString(filling));
   
   //--- Create indicator handles (using HARDCODED values)
   g_HandleFastEMA = iMA(_Symbol, PERIOD_CURRENT, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleSlowEMA = iMA(_Symbol, PERIOD_CURRENT, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(TrendEMA_Period > 0)
      g_HandleTrendEMA = iMA(_Symbol, PERIOD_CURRENT, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   else
      g_HandleTrendEMA = INVALID_HANDLE;
   
   g_HandleRSI = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   g_HandleADX = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   g_HandleATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(g_HandleFastEMA == INVALID_HANDLE || g_HandleSlowEMA == INVALID_HANDLE ||
      g_HandleRSI == INVALID_HANDLE || g_HandleADX == INVALID_HANDLE || g_HandleATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles!");
      return(INIT_FAILED);
   }
   
   //--- Get initial ATR to compute SL/TP/Trailing in price units
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(g_HandleATR, 0, 0, 1, atrArr) >= 1)
      g_ATR = atrArr[0];
   
   if(g_ATR <= 0) g_ATR = g_PipValue * 200; // Fallback: 200 pips
   
   //--- Compute SL/TP in price units from ATR
   StopLoss_price = g_ATR * SL_ATR_Mult;
   TakeProfit_price = g_ATR * TP_ATR_Mult;
   
   //--- Ensure SL/TP are above broker's minimum stop level
   double minSL = g_StopLevel_price * 2.0;  // At least 2x the stop level
   if(StopLoss_price < minSL)
   {
      StopLoss_price = minSL;
      Print("SL adjusted upward to meet stop level: ", StopLoss_price);
   }
   if(TakeProfit_price < minSL * 0.5)
   {
      TakeProfit_price = minSL * 0.5;
      Print("TP adjusted upward to meet stop level: ", TakeProfit_price);
   }
   
   //--- Auto-set spread filter: allow up to 50% of ATR (very generous)
   MaxSpread_price = g_ATR * 0.5;
   if(MaxSpread_price < g_StopLevel_price * 3)
      MaxSpread_price = g_StopLevel_price * 3;
   
   //--- Initialize daily equity tracking
   g_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_PeakEquity = g_DailyStartEquity;
   
   //--- Print active settings (these CANNOT be overridden by tester)
   Print("=== GOLDSTUFF EA v3.2 - PIP-ADAPTIVE + ATR-BASED ===");
   Print("Symbol: ", _Symbol, " | Point: ", _Point, " | Digits: ", _Digits);
   Print("PipSize: ", g_PipSize, " points | PipValue: ", g_PipValue, " (price units)");
   Print("FastEMA: ", FastEMA_Period, " | SlowEMA: ", SlowEMA_Period, " | TrendEMA: ", TrendEMA_Period);
   Print("RSI: ", RSI_Period, "(", RSI_Oversold, "-", RSI_Overbought, ") | ADX: ", ADX_Period, " | ADX_Thresh: ", ADX_Threshold);
   Print("ATR: ", DoubleToString(g_ATR, g_Digits), " (current price units)");
   Print("SL: ", DoubleToString(StopLoss_price, g_Digits), " | TP: ", DoubleToString(TakeProfit_price, g_Digits), " (ATR-based, price units)");
   Print("TrailStart: ATR*", TrailStart_ATR_Mult, " | TrailStep: ATR*", TrailStep_ATR_Mult);
   Print("GridDist: ATR*", GridATR_Mult, " | GridMult: ", GridMultiplier, " | GridTP: ATR*", GridTP_ATR_Mult);
   Print("MaxSpread: ", DoubleToString(MaxSpread_price, g_Digits), " (price units, ", DoubleToString(MaxSpread_price / g_Point, 0), " points)");
   Print("StopLevel: ", g_StopLevel, " pts = ", DoubleToString(g_StopLevel_price, g_Digits), " price");
   Print("TimeFilter: ", UseTimeFilter ? "ON" : "OFF", " | MinBars: ", MinBarsBetween);
   Print("SL_ATR_Mult: ", SL_ATR_Mult, " | TP_ATR_Mult: ", TP_ATR_Mult);
   Print("======================================================");
   
   //--- Force first trade based on trend direction
   g_LastTradeTime = 0; // Allow immediate first trade
   Print("EA ready. Pip-adaptive mode active. ATR=", DoubleToString(g_ATR, g_Digits));
   
   if(ShowDashboard)
      EventSetMillisecondTimer(500);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Print summary diagnostics
   Print("=== EA SUMMARY ===");
   Print("Total bars processed: ", g_TotalBars);
   Print("Signals generated: ", g_SignalsGenerated);
   Print("Spread blocks: ", g_SpreadBlocks);
   
   if(g_HandleFastEMA != INVALID_HANDLE)  IndicatorRelease(g_HandleFastEMA);
   if(g_HandleSlowEMA != INVALID_HANDLE)  IndicatorRelease(g_HandleSlowEMA);
   if(g_HandleTrendEMA != INVALID_HANDLE) IndicatorRelease(g_HandleTrendEMA);
   if(g_HandleRSI != INVALID_HANDLE)      IndicatorRelease(g_HandleRSI);
   if(g_HandleADX != INVALID_HANDLE)      IndicatorRelease(g_HandleADX);
   if(g_HandleATR != INVALID_HANDLE)     IndicatorRelease(g_HandleATR);
   
   if(ShowDashboard)
      EventKillTimer();
   
   ObjectsDeleteAll(0, "GS_Dashboard_");
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- FIRST-TICK DIAGNOSTICS (printed once)
   if(!g_DiagPrinted)
   {
      g_DiagPrinted = true;
      long spread_pts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      double spread_price = spread_pts * g_Point;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Check history depth
      int bars_available = Bars(_Symbol, PERIOD_CURRENT);
      datetime first_bar_time = iTime(_Symbol, PERIOD_CURRENT, bars_available - 1);
      
      Print("=== FIRST-TICK DIAGNOSTICS ===");
      Print("Current spread: ", spread_pts, " pts = ", DoubleToString(spread_price, g_Digits), " price units");
      Print("MaxSpread allowed: ", DoubleToString(MaxSpread_price, g_Digits), " price units (", DoubleToString(MaxSpread_price / g_Point, 0), " pts)");
      Print("Spread OK? ", (spread_price <= MaxSpread_price) ? "YES - PASS" : "NO - BLOCKED! Spread too wide!");
      Print("Bid: ", DoubleToString(bid, g_Digits), " | Ask: ", DoubleToString(ask, g_Digits));
      Print("StopLevel: ", g_StopLevel, " pts = ", DoubleToString(g_StopLevel_price, g_Digits));
      Print("SL distance: ", DoubleToString(StopLoss_price, g_Digits), " > StopLevel? ", (StopLoss_price > g_StopLevel_price) ? "YES" : "NO - TRADES WILL BE REJECTED!");
      Print("TP distance: ", DoubleToString(TakeProfit_price, g_Digits), " > StopLevel? ", (TakeProfit_price > g_StopLevel_price) ? "YES" : "NO!");
      Print("ATR: ", DoubleToString(g_ATR, g_Digits));
      Print("Bars available: ", bars_available, " | First bar: ", TimeToString(first_bar_time));
      Print("Pip value: ", g_PipValue, " | Pip size: ", g_PipSize, " points");
      
      // Check history continuity
      double testEMA[];
      ArraySetAsSeries(testEMA, true);
      int copied = CopyBuffer(g_HandleFastEMA, 0, 0, 5, testEMA);
      Print("EMA CopyBuffer test: copied ", copied, " bars (need >= 5)");
      if(copied < 5)
         Print("WARNING: Insufficient history data! EMA indicator cannot be computed!");
      else
         Print("EMA[0..4]: ", DoubleToString(testEMA[4], g_Digits), ", ", DoubleToString(testEMA[3], g_Digits),
               ", ", DoubleToString(testEMA[2], g_Digits), ", ", DoubleToString(testEMA[1], g_Digits),
               ", ", DoubleToString(testEMA[0], g_Digits));
      Print("=== END DIAGNOSTICS ===");
   }
   
   //--- Update ATR every tick
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(g_HandleATR, 0, 0, 1, atrArr) >= 1)
      g_ATR = atrArr[0];
   
   bool isNewBar = IsNewBar();
   
   if(!CheckDailyDrawdown())
      return;
   
   if(!CheckSpread())
      return;
   
   if(!CheckTimeFilter())
      return;
   
   if(isNewBar)
   {
      g_TotalBars++;
      
      int signal = GetTrendSignal();
      
      //--- FORCE FIRST TRADE if no trades are open (simple trend direction)
      if(signal == 0 && CountTrades(ORDER_TYPE_BUY) == 0 && CountTrades(ORDER_TYPE_SELL) == 0)
      {
         signal = GetForcedSignal();
         if(signal != 0)
            Print("FORCED ENTRY: ", (signal == 1 ? "BUY" : "SELL"), " (no trades, using simple trend direction)");
      }
      
      if(signal != 0)
      {
         g_SignalsGenerated++;
         Print(">>> SIGNAL #", g_SignalsGenerated, ": ", (signal == 1 ? "BUY" : "SELL"),
               " | ", _Symbol, " | ", TimeToString(TimeCurrent()),
               " | Price: ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
      }
      
      //--- Diagnostic: log signal conditions every 200 bars
      if(g_TotalBars % 200 == 0)
         PrintSignalDiagnostics();
      
      if(SignalMode == MODE_TREND_ONLY || SignalMode == MODE_TREND_GRID)
         ProcessTrendSignal(signal);
      else if(SignalMode == MODE_GRID_ONLY)
      {
         if(CountTrades(ORDER_TYPE_BUY) == 0 && CountTrades(ORDER_TYPE_SELL) == 0)
            ProcessTrendSignal(signal);
      }
   }
   
   if(EnableGrid && (SignalMode == MODE_TREND_GRID || SignalMode == MODE_GRID_ONLY))
      ManageGridRecovery();
   
   ManageExits();
   
   if(CloseOnFriday && IsFridayClose())
      CloseAllOrders();
   
   if(ShowDashboard)
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Print signal diagnostic details (for debugging zero-trade issues)|
//+------------------------------------------------------------------+
void PrintSignalDiagnostics()
{
   double fastEMA[], slowEMA[], rsi[], adxArr[];
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adxArr, true);
   
   if(CopyBuffer(g_HandleFastEMA, 0, 0, 5, fastEMA) < 5) { Print("DIAG: fastEMA copy failed"); return; }
   if(CopyBuffer(g_HandleSlowEMA, 0, 0, 5, slowEMA) < 5) { Print("DIAG: slowEMA copy failed"); return; }
   if(CopyBuffer(g_HandleRSI, 0, 0, 5, rsi) < 5) { Print("DIAG: RSI copy failed"); return; }
   if(CopyBuffer(g_HandleADX, 0, 0, 5, adxArr) < 5) { Print("DIAG: ADX copy failed"); return; }
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   Print("--- DIAG BAR #", g_TotalBars, " @ ", TimeToString(TimeCurrent()), " ---");
   Print("  Price: ", DoubleToString(price, g_Digits));
   Print("  FastEMA[1]: ", DoubleToString(fastEMA[1], g_Digits), " | SlowEMA[1]: ", DoubleToString(slowEMA[1], g_Digits));
   Print("  FastEMA[2]: ", DoubleToString(fastEMA[2], g_Digits), " | SlowEMA[2]: ", DoubleToString(slowEMA[2], g_Digits));
   Print("  EMA cross check: f[1]>s[1]=", (fastEMA[1] > slowEMA[1]), " f[2]<=s[2]=", (fastEMA[2] <= slowEMA[2]),
         " => BullCross=", (fastEMA[1] > slowEMA[1] && fastEMA[2] <= slowEMA[2]));
   Print("  EMA cross check: f[1]<s[1]=", (fastEMA[1] < slowEMA[1]), " f[2]>=s[2]=", (fastEMA[2] >= slowEMA[2]),
         " => BearCross=", (fastEMA[1] < slowEMA[1] && fastEMA[2] >= slowEMA[2]));
   Print("  EMA trend: emaUp=", (fastEMA[1] > slowEMA[1] && fastEMA[3] > slowEMA[3]),
         " emaDn=", (fastEMA[1] < slowEMA[1] && fastEMA[3] < slowEMA[3]));
   Print("  RSI[1]: ", DoubleToString(rsi[1], 2), " (", RSI_Oversold, "-", RSI_Overbought, ")");
   Print("  ADX[0]: ", DoubleToString(adxArr[0], 2), " (thresh: ", ADX_Threshold, ")");
   Print("  ATR: ", DoubleToString(g_ATR, g_Digits));
   Print("  SL_price: ", DoubleToString(StopLoss_price, g_Digits), " | TP_price: ", DoubleToString(TakeProfit_price, g_Digits));
   Print("  Spread: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), " pts | MaxSpread_price: ", DoubleToString(MaxSpread_price, g_Digits));
   Print("  Trades open: Buy=", CountTrades(ORDER_TYPE_BUY), " Sell=", CountTrades(ORDER_TYPE_SELL));
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(ShowDashboard)
      UpdateDashboard();
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(g_LastBarTime != t)
   {
      g_LastBarTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = 0;
   if(g_DailyStartEquity > 0)
      dd = ((g_DailyStartEquity - eq) / g_DailyStartEquity) * 100.0;
   if(eq > g_PeakEquity)
      g_PeakEquity = eq;
   if(dd >= MaxDailyDrawdown)
   {
      Print("CRITICAL DD: ", DoubleToString(dd, 2), "% - Closing all!");
      CloseAllOrders();
      return false;
   }
   static int lastDay = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day != lastDay)
   {
      lastDay = dt.day;
      if(dt.hour == 0)
         g_DailyStartEquity = eq;
   }
   return true;
}

//+------------------------------------------------------------------+
//| CheckSpread - NOW in price units, not raw points                  |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread_pts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spread_price = spread_pts * g_Point;
   
   // Also update ATR-adaptive max spread dynamically
   double current_max = g_ATR * 0.5;  // 50% of ATR
   if(current_max < g_StopLevel_price * 3)
      current_max = g_StopLevel_price * 3;
   if(current_max > MaxSpread_price)
      MaxSpread_price = current_max;  // Allow wider if ATR grows
   
   if(spread_price > MaxSpread_price)
   {
      g_SpreadBlocks++;
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
   if(!UseTimeFilter)
      return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0)
      return false;
   if(StartHour < EndHour)
      return (dt.hour >= StartHour && dt.hour < EndHour);
   return !(dt.hour >= EndHour && dt.hour < StartHour);
}

//+------------------------------------------------------------------+
bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= 20);
}

//+------------------------------------------------------------------+
//| Get trend signal (v3 - pip-adaptive)                              |
//+------------------------------------------------------------------+
int GetTrendSignal()
{
   double fastEMA[], slowEMA[], rsi[], adx[], atr[];
   
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(g_HandleFastEMA, 0, 0, 5, fastEMA) < 5) return 0;
   if(CopyBuffer(g_HandleSlowEMA, 0, 0, 5, slowEMA) < 5) return 0;
   if(CopyBuffer(g_HandleRSI, 0, 0, 5, rsi) < 5) return 0;
   if(CopyBuffer(g_HandleADX, 0, 0, 5, adx) < 5) return 0;
   if(CopyBuffer(g_HandleATR, 0, 0, 5, atr) < 5) return 0;
   
   double adxP[], adxM[];
   ArraySetAsSeries(adxP, true);
   ArraySetAsSeries(adxM, true);
   int hADX = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   CopyBuffer(hADX, 1, 0, 5, adxP);
   CopyBuffer(hADX, 2, 0, 5, adxM);
   IndicatorRelease(hADX);
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double adxMain = adx[0];
   
   double trendEMA[];
   bool hasTrend = false;
   bool aboveTrend = true;
   if(g_HandleTrendEMA != INVALID_HANDLE)
   {
      ArraySetAsSeries(trendEMA, true);
      if(CopyBuffer(g_HandleTrendEMA, 0, 0, 5, trendEMA) >= 5)
      {
         hasTrend = true;
         aboveTrend = (price > trendEMA[0]);
      }
   }
   
   //--- Detect patterns (using shift 1 = completed bar, shift 2 = previous completed bar)
   bool bullCross = (fastEMA[1] > slowEMA[1] && fastEMA[2] <= slowEMA[2]);
   bool bearCross = (fastEMA[1] < slowEMA[1] && fastEMA[2] >= slowEMA[2]);
   bool emaUp = (fastEMA[1] > slowEMA[1] && fastEMA[3] > slowEMA[3]);
   bool emaDn = (fastEMA[1] < slowEMA[1] && fastEMA[3] < slowEMA[3]);
   bool strong = (adxMain >= ADX_Threshold);
   bool diUp = (adxP[1] > adxM[1]);
   bool diDn = (adxM[1] > adxP[1]);
   bool rsiOk = (rsi[1] > RSI_Oversold && rsi[1] < RSI_Overbought);
   bool rsiOversoldBounce = (rsi[1] > RSI_Oversold && rsi[2] <= RSI_Oversold);
   bool rsiOverboughtDrop = (rsi[1] < RSI_Overbought && rsi[2] >= RSI_Overbought);
   
   //--- TREND_EMA_CROSS
   if(TrendMethod == TREND_EMA_CROSS)
   {
      if(bullCross && (!hasTrend || aboveTrend)) return 1;
      if(bearCross && (!hasTrend || !aboveTrend)) return -1;
      if(emaUp && diUp && rsiOk && CountTrades(ORDER_TYPE_BUY) == 0 && (!hasTrend || aboveTrend)) return 1;
      if(emaDn && diDn && rsiOk && CountTrades(ORDER_TYPE_SELL) == 0 && (!hasTrend || !aboveTrend)) return -1;
   }
   
   //--- TREND_RSI_EMA
   else if(TrendMethod == TREND_RSI_EMA)
   {
      if(bullCross && rsiOk && (!hasTrend || aboveTrend)) return 1;
      if(bearCross && rsiOk && (!hasTrend || !aboveTrend)) return -1;
      if(emaUp && rsiOversoldBounce && (!hasTrend || aboveTrend)) return 1;
      if(emaDn && rsiOverboughtDrop && (!hasTrend || !aboveTrend)) return -1;
   }
   
   //--- TREND_MULTI (Recommended)
   else if(TrendMethod == TREND_MULTI)
   {
      //--- STRONG: crossover + ADX + DI
      if(bullCross && strong && diUp && rsiOk && (!hasTrend || aboveTrend)) return 1;
      if(bearCross && strong && diDn && rsiOk && (!hasTrend || !aboveTrend)) return -1;
      
      //--- MODERATE: sustained trend + all confirm (only when no trades open)
      if(emaUp && diUp && rsiOk && strong && CountTrades(ORDER_TYPE_BUY) == 0 && (!hasTrend || aboveTrend)) return 1;
      if(emaDn && diDn && rsiOk && strong && CountTrades(ORDER_TYPE_SELL) == 0 && (!hasTrend || !aboveTrend)) return -1;
      
      //--- RSI bounce in confirmed trend
      if(emaUp && diUp && rsiOversoldBounce && (!hasTrend || aboveTrend)) return 1;
      if(emaDn && diDn && rsiOverboughtDrop && (!hasTrend || !aboveTrend)) return -1;
      
      //--- WEAK: crossover alone (always enter fresh cross)
      if(bullCross && (!hasTrend || aboveTrend)) return 1;
      if(bearCross && (!hasTrend || !aboveTrend)) return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Forced signal: simple trend direction when no trades open          |
//| v3.2: ALWAYS returns 1 or -1 (never 0 unless copy fails)        |
//+------------------------------------------------------------------+
int GetForcedSignal()
{
   double fastEMA[], slowEMA[];
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   
   if(CopyBuffer(g_HandleFastEMA, 0, 0, 3, fastEMA) < 3) return 0;
   if(CopyBuffer(g_HandleSlowEMA, 0, 0, 3, slowEMA) < 3) return 0;
   
   //--- Simple: if fast EMA > slow EMA, BUY; if fast < slow, SELL
   if(fastEMA[1] >= slowEMA[1])
      return 1;
   else
      return -1;
}

//+------------------------------------------------------------------+
//| Auto-detect best filling mode                                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetBestFilling()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
void ProcessTrendSignal(int signal)
{
   if(signal == 0) return;
   
   if((TimeCurrent() - g_LastTradeTime) < (MinBarsBetween * PeriodSeconds()))
      return;
   
   int buyCount = CountTrades(ORDER_TYPE_BUY);
   int sellCount = CountTrades(ORDER_TYPE_SELL);
   
   if(signal == 1)
   {
      if(CloseOnOpposite && sellCount > 0)
         CloseOrdersByType(ORDER_TYPE_SELL);
      if(buyCount < MaxOpenTrades)
      {
         double lot = CalculateLotSize();
         if(OpenTrade(ORDER_TYPE_BUY, lot, "Trend Buy"))
         {
            g_LastTradeTime = TimeCurrent();
            if(EnableAlerts)
               Alert("GoldStuff BUY on ", _Symbol, " @ ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
         }
      }
   }
   else if(signal == -1)
   {
      if(CloseOnOpposite && buyCount > 0)
         CloseOrdersByType(ORDER_TYPE_BUY);
      if(sellCount < MaxOpenTrades)
      {
         double lot = CalculateLotSize();
         if(OpenTrade(ORDER_TYPE_SELL, lot, "Trend Sell"))
         {
            g_LastTradeTime = TimeCurrent();
            if(EnableAlerts)
               Alert("GoldStuff SELL on ", _Symbol, " @ ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Grid Recovery - NOW ATR-adaptive                                  |
//+------------------------------------------------------------------+
void ManageGridRecovery()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist;
   
   if(GridStyle == GRID_FIXED)
      dist = g_ATR * GridATR_Mult;
   else if(GridStyle == GRID_ATR)
      dist = g_ATR * GridATR_Mult;
   else // FIBONACCI
      dist = g_ATR * 1.618;
   
   ManageBuyGrid(price, dist);
   ManageSellGrid(price, dist);
}

//+------------------------------------------------------------------+
void ManageBuyGrid(double price, double dist)
{
   int cnt = CountTrades(ORDER_TYPE_BUY);
   if(cnt == 0) { g_GridBuyCount = 0; return; }
   
   double avg = GetAverageEntryPrice(ORDER_TYPE_BUY);
   
   if(price < avg - dist * 0.3 && g_GridBuyCount < MaxGridLevels)
   {
      double next = avg - (dist * MathPow(GridMultiplier, g_GridBuyCount));
      if(price <= next)
      {
         double baseLot = AutoLot ? CalculateLotSize() : FixedLot;
         double lot = NormalizeLot(baseLot * MathPow(GridMultiplier, g_GridBuyCount));
         if(cnt + g_GridBuyCount < MaxOpenTrades)
         {
            if(OpenTrade(ORDER_TYPE_BUY, lot, "Grid Buy L" + IntegerToString(g_GridBuyCount + 1)))
            {
               g_GridBuyCount++;
               if(GridBreakeven)
                  SetGridTakeProfit(ORDER_TYPE_BUY, avg, dist);
            }
         }
      }
   }
   if(price > avg + dist * 0.5)
      g_GridBuyCount = 0;
}

//+------------------------------------------------------------------+
void ManageSellGrid(double price, double dist)
{
   int cnt = CountTrades(ORDER_TYPE_SELL);
   if(cnt == 0) { g_GridSellCount = 0; return; }
   
   double avg = GetAverageEntryPrice(ORDER_TYPE_SELL);
   
   if(price > avg + dist * 0.3 && g_GridSellCount < MaxGridLevels)
   {
      double next = avg + (dist * MathPow(GridMultiplier, g_GridSellCount));
      if(price >= next)
      {
         double baseLot = AutoLot ? CalculateLotSize() : FixedLot;
         double lot = NormalizeLot(baseLot * MathPow(GridMultiplier, g_GridSellCount));
         if(cnt + g_GridSellCount < MaxOpenTrades)
         {
            if(OpenTrade(ORDER_TYPE_SELL, lot, "Grid Sell L" + IntegerToString(g_GridSellCount + 1)))
            {
               g_GridSellCount++;
               if(GridBreakeven)
                  SetGridTakeProfit(ORDER_TYPE_SELL, avg, dist);
            }
         }
      }
   }
   if(price < avg - dist * 0.5)
      g_GridSellCount = 0;
}

//+------------------------------------------------------------------+
void SetGridTakeProfit(ENUM_ORDER_TYPE type, double avg, double dist)
{
   double tp = g_ATR * GridTP_ATR_Mult;
   
   if(type == ORDER_TYPE_BUY)
      tp = NormalizeDouble(avg + tp, g_Digits);
   else
      tp = NormalizeDouble(avg - tp, g_Digits);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == (type == ORDER_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
         {
            double sl = PositionGetDouble(POSITION_SL);
            double curTP = PositionGetDouble(POSITION_TP);
            if(MathAbs(curTP - tp) > g_Point)
               trade.PositionModify(ticket, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Exits - NOW ATR-adaptive trailing stop and breakeven        |
//+------------------------------------------------------------------+
void ManageExits()
{
   double trailStart = g_ATR * TrailStart_ATR_Mult;
   double trailStep  = g_ATR * TrailStep_ATR_Mult;
   double beStart    = g_ATR * BreakevenStart_ATR;
   double beProfit   = g_ATR * BreakevenProfit_ATR;
   
   // Ensure trailing step is at least 1 point
   if(trailStep < g_Point) trailStep = g_Point;
   // Ensure breakeven profit is at least 1 point
   if(beProfit < g_Point) beProfit = g_Point;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      if(EnableTrailingStop)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double profit = bid - open;
            if(profit >= trailStart)
            {
               double newSL = NormalizeDouble(bid - trailStep, g_Digits);
               if(newSL > sl || sl == 0)
                  trade.PositionModify(ticket, newSL, tp);
            }
         }
         else
         {
            double profit = open - ask;
            if(profit >= trailStart)
            {
               double newSL = NormalizeDouble(ask + trailStep, g_Digits);
               if(newSL < sl || sl == 0)
                  trade.PositionModify(ticket, newSL, tp);
            }
         }
      }
      
      if(EnableBreakeven)
      {
         if(type == POSITION_TYPE_BUY)
         {
            if((bid - open) >= beStart)
            {
               double beSL = NormalizeDouble(open + beProfit, g_Digits);
               if(sl < beSL)
                  trade.PositionModify(ticket, beSL, tp);
            }
         }
         else
         {
            if((open - ask) >= beStart)
            {
               double beSL = NormalizeDouble(open - beProfit, g_Digits);
               if(sl > beSL || sl == 0)
                  trade.PositionModify(ticket, beSL, tp);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CalculateLotSize - ATR-aware                                       |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(!AutoLot) return NormalizeLot(FixedLot);
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * (RiskPercent / 100.0);
   
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSz == 0 || tickVal == 0) return NormalizeLot(FixedLot);
   
   // Use ATR-based SL distance in price units
   double dist = StopLoss_price;
   if(dist <= 0) dist = g_ATR * SL_ATR_Mult;  // Fallback
   
   double lot = risk / (dist / tickSz * tickVal);
   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   lot = MathMax(MinLot, lot);
   lot = MathMin(MaxLot, lot);
   lot = MathMax(g_MinLot, lot);
   lot = MathMin(g_MaxLot, lot);
   if(g_LotStep > 0)
      lot = MathFloor(lot / g_LotStep) * g_LotStep;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
int CountTrades(ENUM_ORDER_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         long pt = PositionGetInteger(POSITION_TYPE);
         if((type == ORDER_TYPE_BUY && pt == POSITION_TYPE_BUY) ||
            (type == ORDER_TYPE_SELL && pt == POSITION_TYPE_SELL))
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
double GetAverageEntryPrice(ENUM_ORDER_TYPE type)
{
   double val = 0, lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         long pt = PositionGetInteger(POSITION_TYPE);
         if((type == ORDER_TYPE_BUY && pt == POSITION_TYPE_BUY) ||
            (type == ORDER_TYPE_SELL && pt == POSITION_TYPE_SELL))
         {
            val += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
            lots += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return (lots > 0) ? val / lots : 0;
}

//+------------------------------------------------------------------+
//| OpenTrade - ATR-adaptive SL/TP in PRICE UNITS                    |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double lot, string comment)
{
   lot = NormalizeLot(lot);
   if(lot <= 0) return false;
   
   double price, sl = 0, tp = 0;
   
   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(price - StopLoss_price, g_Digits);
      tp = NormalizeDouble(price + TakeProfit_price, g_Digits);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(price + StopLoss_price, g_Digits);
      tp = NormalizeDouble(price - TakeProfit_price, g_Digits);
   }
   
   //--- Ensure SL/TP are at least at broker's stop level distance
   if(g_StopLevel > 0)
   {
      if(type == ORDER_TYPE_BUY)
      {
         if((price - sl) < g_StopLevel_price)
            sl = NormalizeDouble(price - g_StopLevel_price - g_Point, g_Digits);
         if((tp - price) < g_StopLevel_price)
            tp = NormalizeDouble(price + g_StopLevel_price + g_Point, g_Digits);
      }
      else
      {
         if((sl - price) < g_StopLevel_price)
            sl = NormalizeDouble(price + g_StopLevel_price + g_Point, g_Digits);
         if((price - tp) < g_StopLevel_price)
            tp = NormalizeDouble(price - g_StopLevel_price - g_Point, g_Digits);
      }
   }
   
   //--- Normalize to prevent invalid stops
   if(type == ORDER_TYPE_BUY)
   {
      if(sl >= price) sl = 0;  // Invalid SL for buy, remove it
      if(tp <= price) tp = 0;  // Invalid TP for buy, remove it
   }
   else
   {
      if(sl <= price) sl = 0;  // Invalid SL for sell
      if(tp >= price) tp = 0;  // Invalid TP for sell
   }
   
   bool result;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lot, _Symbol, price, sl, tp, EA_Comment + "_" + comment);
   else
      result = trade.Sell(lot, _Symbol, price, sl, tp, EA_Comment + "_" + comment);
   
   if(result)
      Print(type == ORDER_TYPE_BUY ? "BUY" : "SELL", " opened: ", lot, " @ ", price,
            " SL=", DoubleToString(sl, g_Digits), " TP=", DoubleToString(tp, g_Digits),
            " (SL_dist=", DoubleToString(price - sl, g_Digits), " TP_dist=", DoubleToString(tp - price, g_Digits), ")");
   else
   {
      int err = GetLastError();
      Print("Trade FAILED: code=", err, " desc=", GetErrorDescription(err),
            " | price=", DoubleToString(price, g_Digits),
            " SL=", DoubleToString(sl, g_Digits), " TP=", DoubleToString(tp, g_Digits));
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Get error description                                             |
//+------------------------------------------------------------------+
string GetErrorDescription(int error)
{
   switch(error)
   {
      case 10004: return "Requote";
      case 10006: return "Request rejected";
      case 10007: return "Request canceled by trader";
      case 10008: return "Order placed";
      case 10009: return "Request executed";
      case 10010: return "Request partially executed";
      case 10011: return "Request processing error";
      case 10012: return "Request timed out";
      case 10013: return "Invalid request";
      case 10014: return "Invalid volume";
      case 10015: return "Invalid price";
      case 10016: return "Invalid stops";
      case 10017: return "Trade disabled";
      case 10018: return "Market closed";
      case 10019: return "Not enough money";
      case 10020: return "Prices changed";
      case 10021: return "No quotes to process request";
      case 10022: return "Invalid order expiration";
      case 10023: return "Order state changed";
      case 10024: return "Too many requests";
      case 10025: return "No changes in request";
      case 10026: return "Autotrading disabled by server";
      case 10027: return "Autotrading disabled by client terminal";
      case 10028: return "Request locked for processing";
      case 10029: return "Order or position frozen";
      case 10030: return "Invalid order filling type";
      case 10031: return "No connection with trade server";
      case 10032: return "Operation allowed only for live accounts";
      case 10033: return "Pending orders limit reached";
      case 10034: return "Volume limit for symbol reached";
      case 10035: return "Incorrect or prohibited order type";
      case 10036: return "Position with specified ID already closed";
      case 10038: return "Close volume exceeds current position volume";
      case 10039: return "Close order already exists";
      case 10040: return "Positions limit reached";
      case 10041: return "Pending order activation rejected";
      case 10042: return "Only long positions allowed";
      case 10043: return "Only short positions allowed";
      case 10044: return "Only position close allowed";
      case 10045: return "Position close order already exists";
      default: return "Unknown error " + IntegerToString(error);
   }
}

//+------------------------------------------------------------------+
void CloseAllOrders()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(ticket);
   }
   g_GridBuyCount = 0;
   g_GridSellCount = 0;
}

//+------------------------------------------------------------------+
void CloseOrdersByType(ENUM_ORDER_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         long pt = PositionGetInteger(POSITION_TYPE);
         if((type == ORDER_TYPE_BUY && pt == POSITION_TYPE_BUY) ||
            (type == ORDER_TYPE_SELL && pt == POSITION_TYPE_SELL))
            trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
double GetTotalProfit()
{
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return profit;
}

//+------------------------------------------------------------------+
double GetFloatingPips()
{
   double pips = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double vol = PositionGetDouble(POSITION_VOLUME);
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            pips += (cur - open) / g_Point * vol;
         else
            pips += (open - cur) / g_Point * vol;
      }
   }
   return pips;
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = 10, y = 30;
   string p = "GS_Dash_";
   
   CreateRect(p + "BG", x - 5, 20, 260, 370);
   
   CreateLabel(p + "T", x, y, "GOLDSTUFF TREND+GRID v3.2", clrGold, 9); y += 20;
   CreateLabel(p + "Bal", x, y, "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), clrWhite, 8); y += 15;
   CreateLabel(p + "Eq", x, y, "Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), clrWhite, 8); y += 15;
   
   double dd = (g_PeakEquity > 0) ? ((g_PeakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_PeakEquity) * 100 : 0;
   CreateLabel(p + "DD", x, y, "Drawdown: " + DoubleToString(dd, 2) + "%", dd > 3 ? clrRed : clrLime, 8); y += 20;
   
   CreateLabel(p + "Buy", x, y, "Buy: " + IntegerToString(CountTrades(ORDER_TYPE_BUY)), clrDodgerBlue, 8); y += 15;
   CreateLabel(p + "Sell", x, y, "Sell: " + IntegerToString(CountTrades(ORDER_TYPE_SELL)), clrTomato, 8); y += 15;
   CreateLabel(p + "GB", x, y, "Grid Buy Lvls: " + IntegerToString(g_GridBuyCount), clrDodgerBlue, 8); y += 15;
   CreateLabel(p + "GS", x, y, "Grid Sell Lvls: " + IntegerToString(g_GridSellCount), clrTomato, 8); y += 20;
   
   double profit = GetTotalProfit();
   CreateLabel(p + "PL", x, y, "Float P/L: $" + DoubleToString(profit, 2), profit >= 0 ? clrLime : clrRed, 9); y += 15;
   
   double fp = GetFloatingPips();
   CreateLabel(p + "Pips", x, y, "Float Pips: " + DoubleToString(fp, 1), fp >= 0 ? clrLime : clrRed, 8); y += 20;
   
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spread_price = sp * g_Point;
   CreateLabel(p + "Spd", x, y, "Spread: " + DoubleToString(spread_price, g_Digits) + " ($)", sp <= (long)(MaxSpread_price / g_Point) ? clrLime : clrRed, 8); y += 15;
   
   CreateLabel(p + "ATR", x, y, "ATR: " + DoubleToString(g_ATR, g_Digits) + " (SL: " + DoubleToString(StopLoss_price, g_Digits) + ")", clrYellow, 8); y += 15;
   
   CreateLabel(p + "Bars", x, y, "Bars: " + IntegerToString(g_TotalBars) + " | Sig: " + IntegerToString(g_SignalsGenerated), clrWhite, 8); y += 15;
   
   int sig = GetTrendSignal();
   string st = "Signal: " + (sig == 1 ? "BUY" : (sig == -1 ? "SELL" : "NEUTRAL"));
   CreateLabel(p + "Sig", x, y, st, sig == 1 ? clrDodgerBlue : (sig == -1 ? clrTomato : clrWhite), 8); y += 15;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   CreateLabel(p + "Time", x, y, "Server: " + IntegerToString(dt.hour) + ":" + IntegerToString(dt.min), clrWhite, 8);
   
   ChartRedraw(0);
}

void CreateLabel(string name, int x, int y, string text, color clr, int size)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void CreateRect(string name, int x, int y, int w, int h)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDarkSlateGray);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}
//+------------------------------------------------------------------+
