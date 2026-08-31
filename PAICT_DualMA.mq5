//+------------------------------------------------------------------+
//|                                                 PAICT_DualMA.mq5 |
//|                        Chart Markup Key — companion indicator    |
//|                                                                  |
//|  Renders the fast (yellow) and slow (violet) moving averages    |
//|  used by the PAICT_ChartMarkup EA. The EA attaches this          |
//|  indicator automatically to every covered chart via             |
//|  ChartIndicatorAdd(), which lets the MAs render natively with    |
//|  their colors baked in instead of being hand-drawn as hundreds   |
//|  of trend-line segments.                                        |
//|                                                                  |
//|  You normally never attach this manually — compiling it into    |
//|  MQL5\Indicators\ is enough for the EA to find it.               |
//+------------------------------------------------------------------+
#property copyright "Chart Markup Key"
#property link      ""
#property version   "1.00"
#property description "Dual MA overlay for the Chart Markup Key suite: fast MA in yellow, slow MA in violet."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot 0 : fast MA -------------------------------------------------
#property indicator_label1  "MA Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot 1 : slow MA -------------------------------------------------
#property indicator_label2  "MA Slow"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrMediumOrchid
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- inputs
input group "Moving Averages"
input int                InpFastPeriod = 5;         // Fast MA period
input int                InpSlowPeriod = 15;        // Slow MA period
input ENUM_MA_METHOD     InpMethod     = MODE_EMA;  // MA method
input ENUM_APPLIED_PRICE InpPriceMode  = PRICE_CLOSE; // Applied price (CLOSE is assumed internally)

//--- buffers
double FastBuf[];
double SlowBuf[];
double WorkPrice[]; // applied-price source resolved at runtime

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSlowPeriod <= InpFastPeriod)
      Print("PAICT_DualMA: slow period (", InpSlowPeriod,
            ") should exceed fast period (", InpFastPeriod, ")");

   SetIndexBuffer(0, FastBuf, INDICATOR_DATA);
   SetIndexBuffer(1, SlowBuf, INDICATOR_DATA);
   ArraySetAsSeries(FastBuf, false);
   ArraySetAsSeries(SlowBuf, false);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, MathMax(1, InpFastPeriod));
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, MathMax(1, InpSlowPeriod));
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME, "PAICT DualMA");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int maxPeriod = InpSlowPeriod;
   if(InpFastPeriod > maxPeriod)
      maxPeriod = InpFastPeriod;
   if(rates_total < maxPeriod + 2)
      return(0);

   // Resolve applied price once per call into WorkPrice.
   ArraySetAsSeries(close, false);
   ArrayResize(WorkPrice, rates_total);
   for(int b = 0; b < rates_total; b++)
      WorkPrice[b] = close[b]; // CLOSE-mode resolution (kept explicit for clarity)

   int start = prev_calculated > 0 ? prev_calculated - 1 : 0;
   if(start < 0)
      start = 0;

   for(int i = start; i < rates_total; i++)
     {
      FastBuf[i] = CalcMA(i, InpFastPeriod);
      SlowBuf[i] = CalcMA(i, InpSlowPeriod);
     }
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| One-bar MA value (SMA / EMA / SMMA / LWMA)                       |
//+------------------------------------------------------------------+
double CalcMA(const int i, const int period)
  {
   if(period < 1 || i < period - 1 || i >= ArraySize(WorkPrice))
      return(EMPTY_VALUE);

   double k     = 0.0;
   double seed  = 0.0;
   double sum   = 0.0;
   double wsum  = 0.0;
   double vsum  = 0.0;
   double prev  = 0.0;
   bool   chain = false;

   switch(InpMethod)
     {
      case MODE_EMA:
         k     = 2.0 / (period + 1.0);
         seed  = SeedAverage(i, period);
         prev  = (i == period - 1) ? seed : ((period == InpFastPeriod) ? FastBuf[i - 1] : SlowBuf[i - 1]);
         chain = (prev != EMPTY_VALUE && prev != 0.0);
         return(chain ? WorkPrice[i] * k + prev * (1.0 - k) : seed);

      case MODE_SMMA:
         k     = 1.0 / (double)period;
         seed  = SeedAverage(i, period);
         prev  = (i == period - 1) ? seed : ((period == InpFastPeriod) ? FastBuf[i - 1] : SlowBuf[i - 1]);
         chain = (prev != EMPTY_VALUE && prev != 0.0);
         return(chain ? WorkPrice[i] * k + prev * (1.0 - k) : seed);

      case MODE_LWMA:
         wsum  = 0.0;
         vsum  = 0.0;
         for(int l = 0; l < period; l++)
           {
            double w = (double)(l + 1);
            vsum += WorkPrice[i - period + 1 + l] * w;
            wsum += w;
           }
         return(wsum != 0.0 ? vsum / wsum : EMPTY_VALUE);

      case MODE_SMA:
      default:
         sum = 0.0;
         for(int s = 0; s < period; s++)
            sum += WorkPrice[i - s];
         return(sum / period);
     }
  }

//+------------------------------------------------------------------+
//| SMA seed for the first smoothed bar                              |
//+------------------------------------------------------------------+
double SeedAverage(const int i, const int period)
  {
   if(i < period - 1)
      return(EMPTY_VALUE);
   double sum = 0.0;
   for(int j = i - period + 1; j <= i; j++)
      sum += WorkPrice[j];
   return(sum / period);
  }
//+------------------------------------------------------------------+
