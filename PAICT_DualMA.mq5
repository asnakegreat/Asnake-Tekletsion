//+------------------------------------------------------------------+
//|                                                 PAICT_DualMA.mq5 |
//|      Companion indicator for PAICT_ChartMarkup — fast/slow SMA   |
//|                                                                  |
//|  Plots two simple moving averages (yellow fast / violet slow) in |
//|  the main chart window. PAICT_ChartMarkup.mq5 attaches this to   |
//|  every chart it covers via                                       |
//|    iCustom(symbol, tf, "PAICT_DualMA", InpFastMAPeriod, InpSlowMAPeriod) |
//|  purely as a visual reference layer — the EA never reads its     |
//|  buffers back, and already degrades gracefully (one journal      |
//|  line, markup keeps drawing) if this indicator is missing or     |
//|  fails to attach. Deliberately a plain SMA, computed directly    |
//|  from closed-bar closes with no external handle, to match the    |
//|  rest of the kit's "deliberately simplified, non-repainting"     |
//|  philosophy and avoid iMA/CopyBuffer series-order pitfalls.       |
//+------------------------------------------------------------------+
#property copyright "Chart Markup Key"
#property link      ""
#property version   "1.00"
#property description "Fast/slow SMA companion for PAICT_ChartMarkup."

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "PAICT Fast MA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "PAICT Slow MA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrViolet
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

input int InpFastPeriod = 5;   // Fast MA period
input int InpSlowPeriod = 15;  // Slow MA period

double FastBuffer[];
double SlowBuffer[];

int OnInit()
  {
   SetIndexBuffer(0, FastBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SlowBuffer, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "PAICT DualMA");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Plain SMA over closed-bar closes — no iMA handle, no CopyBuffer.   |
//| Only recomputes from the first bar affected by the new/forming    |
//| bar onward, same incremental pattern every stock indicator uses.  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[])
  {
   const int fastP = MathMax(1, InpFastPeriod);
   const int slowP = MathMax(2, InpSlowPeriod);

   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;
   for(int i = start; i < rates_total; i++)
     {
      if(i >= fastP - 1)
        {
         double sum = 0.0;
         for(int k = 0; k < fastP; k++)
            sum += close[i - k];
         FastBuffer[i] = sum / fastP;
        }
      else
         FastBuffer[i] = EMPTY_VALUE;

      if(i >= slowP - 1)
        {
         double sum = 0.0;
         for(int k = 0; k < slowP; k++)
            sum += close[i - k];
         SlowBuffer[i] = sum / slowP;
        }
      else
         SlowBuffer[i] = EMPTY_VALUE;
     }
   return(rates_total);
  }
