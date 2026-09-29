//+------------------------------------------------------------------+
//|                                            ZEC_SignalHub_EA.mq5  |
//|  Signal-only hub for the two strategies that passed testing:     |
//|    G4  index RSI(2) pullback   (D1, long only)                   |
//|    B1  trend momentum (TSMOM)  (D1, long only)                   |
//|  Reads genuine broker D1 bars, never places trades. Each entry / |
//|  exit is posted to the Signal Scanner app (-> Amplitude, Notion, |
//|  Telegram) and written to a CSV log in Common\Files.             |
//|                                                                  |
//|  Rules are the frozen ones from ZEC_Portfolio_EA (Notion):       |
//|   G4: close > SMA200 and RSI(2) < 5 -> buy next open;            |
//|       exit next open after RSI(2) > 70; fixed SL 3 x ATR20.       |
//|   B1: 63- and 126-day returns both turn positive -> buy next     |
//|       open; SL 3 x ATR20; chandelier = highest high since entry  |
//|       - 7 x ATR20, raised each close.                            |
//|  Prices here are reference levels at the signal close; the real  |
//|  fill is the next open, so stops differ slightly from the EA's.  |
//+------------------------------------------------------------------+
#property copyright   "Asnake Tekletsion"
#property version     "1.00"
#property description "Signal-only G4 + B1 hub: real D1 data -> Signal Scanner API -> Amplitude/Notion. Places no trades."

//--- inputs ----------------------------------------------------------
input string InpG4Symbols   = "US500z,USTECz,US2000z,JP225z,UK100z,FR40z,AUS200z";          // G4 symbols (comma separated, broker names)
input string InpB1Symbols   = "US500z,USTECz,US2000z,JP225z,UK100z,FR40z,AUS200z,XAUUSDz";  // B1 symbols (comma separated, broker names)
input string InpApiUrl      = "http://127.0.0.1:8000/api/signals";                          // Signal Scanner endpoint (add host to Allow WebRequest)
input bool   InpPostToApi   = true;     // Post signals to the app
input int    InpHistoryBars = 600;      // D1 bars replayed at start to rebuild open positions
input int    InpTimerSec    = 30;       // How often to check for a new D1 bar (seconds)
input bool   InpShowPanel   = true;     // Show status table on the chart
input string InpLogFile     = "ZEC_SignalHub_log.csv"; // CSV log (Common\Files)

//--- frozen strategy constants (do not tune) -------------------------
#define G4_SMA_PERIOD   200
#define G4_RSI_PERIOD   2
#define G4_RSI_BUY      5.0
#define G4_RSI_EXIT     70.0
#define ATR_PERIOD      20
#define G4_SL_ATR       3.0
#define B1_LOOKBACK_1   63
#define B1_LOOKBACK_2   126
#define B1_SL_ATR       3.0
#define B1_CHAN_ATR     7.0

#define KIND_G4 0
#define KIND_B1 1

#define ENGINE_VERSION  "SignalHub 1.00"
#define MAX_QUEUE       200

//--- one strategy on one symbol --------------------------------------
struct Sleeve
  {
   int      kind;
   string   sym;
   int      digits;
   int      hSma;        // G4 only
   int      hRsi;        // G4 only
   int      hAtr;
   bool     ready;       // state rebuilt from history
   datetime lastBar;     // last closed bar processed
   bool     inPos;
   double   entry;       // reference entry (signal close)
   double   stop;        // current stop level
   double   hh;          // B1: highest high since entry
   bool     prevBoth;    // B1: both returns positive on previous bar
   // last values, for the panel
   double   lastClose, lastRsi, lastSma, lastR1, lastR2;
  };

Sleeve  g_sl[];
string  g_queue[];       // unsent JSON bodies, retried on each timer
bool    g_webWarned = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayResize(g_sl, 0);
   AddSleeves(InpG4Symbols, KIND_G4);
   AddSleeves(InpB1Symbols, KIND_B1);
   if(ArraySize(g_sl) == 0)
     {
      Print("SignalHub: no usable symbols. Check the symbol names in the inputs.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpHistoryBars < B1_LOOKBACK_2 + 30)
     {
      Print("SignalHub: InpHistoryBars must be at least ", B1_LOOKBACK_2 + 30);
      return(INIT_PARAMETERS_INCORRECT);
     }
   // first pass runs from the timer (WebRequest is not used inside OnInit)
   EventSetTimer(3);
   Print("SignalHub ", ENGINE_VERSION, ": ", ArraySize(g_sl),
         " sleeves loaded. Signal-only: this EA places no trades.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(g_sl); i++)
     {
      if(g_sl[i].hSma != INVALID_HANDLE) IndicatorRelease(g_sl[i].hSma);
      if(g_sl[i].hRsi != INVALID_HANDLE) IndicatorRelease(g_sl[i].hRsi);
      if(g_sl[i].hAtr != INVALID_HANDLE) IndicatorRelease(g_sl[i].hAtr);
     }
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick() { }        // all work runs on the timer

//+------------------------------------------------------------------+
void OnTimer()
  {
   static bool first = true;
   if(first) { EventKillTimer(); EventSetTimer(MathMax(5, InpTimerSec)); first = false; }
   FlushQueue();
   for(int i = 0; i < ArraySize(g_sl); i++)
      ProcessSleeve(g_sl[i]);
   if(InpShowPanel) DrawPanel();
  }

//+------------------------------------------------------------------+
//| Parse a comma list and create sleeves for symbols that exist.    |
//+------------------------------------------------------------------+
void AddSleeves(const string list, const int kind)
  {
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "") continue;
      if(!SymbolSelect(sym, true))
        {
         Print("SignalHub: symbol '", sym, "' not found at this broker - skipped (", KindName(kind), ").");
         continue;
        }
      Sleeve s;
      s.kind     = kind;
      s.sym      = sym;
      s.digits   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      s.hSma     = INVALID_HANDLE;
      s.hRsi     = INVALID_HANDLE;
      s.hAtr     = iATR(sym, PERIOD_D1, ATR_PERIOD);
      if(kind == KIND_G4)
        {
         s.hSma = iMA(sym, PERIOD_D1, G4_SMA_PERIOD, 0, MODE_SMA, PRICE_CLOSE);
         s.hRsi = iRSI(sym, PERIOD_D1, G4_RSI_PERIOD, PRICE_CLOSE);
        }
      if(s.hAtr == INVALID_HANDLE || (kind == KIND_G4 && (s.hSma == INVALID_HANDLE || s.hRsi == INVALID_HANDLE)))
        {
         Print("SignalHub: could not create indicators for ", sym, " - skipped.");
         if(s.hSma != INVALID_HANDLE) IndicatorRelease(s.hSma);
         if(s.hRsi != INVALID_HANDLE) IndicatorRelease(s.hRsi);
         if(s.hAtr != INVALID_HANDLE) IndicatorRelease(s.hAtr);
         continue;
        }
      s.ready = false;   s.lastBar = 0;     s.inPos = false;
      s.entry = 0;       s.stop = 0;        s.hh = 0;       s.prevBoth = false;
      s.lastClose = 0;   s.lastRsi = 0;     s.lastSma = 0;  s.lastR1 = 0; s.lastR2 = 0;
      int k = ArraySize(g_sl);
      ArrayResize(g_sl, k + 1);
      g_sl[k] = s;
     }
  }

//+------------------------------------------------------------------+
//| Load the last N closed D1 bars and run every unprocessed bar     |
//| through the strategy. First call replays silently to rebuild     |
//| state; bars after the last posted one are posted.                |
//+------------------------------------------------------------------+
void ProcessSleeve(Sleeve &s)
  {
   datetime lastClosed = iTime(s.sym, PERIOD_D1, 1);
   if(lastClosed == 0) return;                          // history not loaded yet
   if(s.ready && lastClosed <= s.lastBar) return;       // nothing new

   int n = InpHistoryBars;
   if(BarsCalculated(s.hAtr) < n + 1) return;
   if(s.kind == KIND_G4 && (BarsCalculated(s.hSma) < n + 1 || BarsCalculated(s.hRsi) < n + 1)) return;

   MqlRates r[];
   double atr[], sma[], rsi[];
   ArraySetAsSeries(r, false);
   ArraySetAsSeries(atr, false);
   ArraySetAsSeries(sma, false);
   ArraySetAsSeries(rsi, false);
   // start at shift 1 = last CLOSED bar; arrays run oldest -> newest
   if(CopyRates(s.sym, PERIOD_D1, 1, n, r) != n) return;
   if(CopyBuffer(s.hAtr, 0, 1, n, atr) != n) return;
   if(s.kind == KIND_G4)
     {
      if(CopyBuffer(s.hSma, 0, 1, n, sma) != n) return;
      if(CopyBuffer(s.hRsi, 0, 1, n, rsi) != n) return;
     }

   datetime lastPosted = LastPosted(s);
   int start = B1_LOOKBACK_2;                           // enough lookback for the 126-day return
   for(int k = start; k < n; k++)
     {
      if(s.ready && r[k].time <= s.lastBar) continue;   // already processed
      // on the very first pass everything up to the last posted bar is replayed silently;
      // with no posting history, the whole window is silent except the newest closed bar
      bool silent = !s.ready && (r[k].time <= lastPosted || (lastPosted == 0 && k < n - 1));
      bool late   = (k < n - 1);                        // bar older than the newest closed bar
      if(s.kind == KIND_G4) StepG4(s, r, atr, sma, rsi, k, silent, late);
      else                  StepB1(s, r, atr, k, silent, late);
      s.lastBar = r[k].time;
     }
   s.ready = true;
  }

//+------------------------------------------------------------------+
//| G4 index RSI(2) pullback, one closed bar                         |
//+------------------------------------------------------------------+
void StepG4(Sleeve &s, const MqlRates &r[], const double &atr[], const double &sma[],
            const double &rsi[], const int k, const bool silent, const bool late)
  {
   double c = r[k].close;
   s.lastClose = c; s.lastRsi = rsi[k]; s.lastSma = sma[k];
   if(!Valid(atr[k]) || !Valid(sma[k]) || !IsNum(rsi[k])) return;   // RSI can legitimately be 0

   if(s.inPos)
     {
      if(r[k].low <= s.stop)
        {
         Emit(s, r[k], "exit", "stop 3xATR20 hit", s.stop, s.stop, silent, late, atr[k], sma[k], rsi[k], 0, 0);
         s.inPos = false;
         return;                                       // no re-entry on the exit bar
        }
      if(rsi[k] > G4_RSI_EXIT)
        {
         Emit(s, r[k], "exit", "RSI(2) > 70 - exit next open", c, s.stop, silent, late, atr[k], sma[k], rsi[k], 0, 0);
         s.inPos = false;
        }
      return;
     }

   if(c > sma[k] && rsi[k] < G4_RSI_BUY)
     {
      s.inPos = true;
      s.entry = c;
      s.stop  = c - G4_SL_ATR * atr[k];
      Emit(s, r[k], "entry", "close > SMA200 and RSI(2) < 5 - buy next open", c, s.stop, silent, late, atr[k], sma[k], rsi[k], 0, 0);
     }
  }

//+------------------------------------------------------------------+
//| B1 trend momentum, one closed bar                                |
//+------------------------------------------------------------------+
void StepB1(Sleeve &s, const MqlRates &r[], const double &atr[], const int k,
            const bool silent, const bool late)
  {
   double c  = r[k].close;
   double c1 = r[k - B1_LOOKBACK_1].close;
   double c2 = r[k - B1_LOOKBACK_2].close;
   if(c1 <= 0 || c2 <= 0 || !Valid(atr[k])) return;
   double r1 = c / c1 - 1.0;
   double r2 = c / c2 - 1.0;
   bool both = (r1 > 0 && r2 > 0);
   s.lastClose = c; s.lastR1 = r1; s.lastR2 = r2;

   if(s.inPos)
     {
      if(r[k].low <= s.stop)                            // stop in force during this bar
        {
         Emit(s, r[k], "exit", "stop / chandelier 7xATR20 hit", s.stop, s.stop, silent, late, atr[k], 0, 0, r1, r2);
         s.inPos    = false;
         s.prevBoth = both;
         return;
        }
      s.hh   = MathMax(s.hh, r[k].high);                // raise the chandelier at the close
      s.stop = MathMax(s.stop, s.hh - B1_CHAN_ATR * atr[k]);
      s.prevBoth = both;
      return;
     }

   if(both && !s.prevBoth)
     {
      s.inPos = true;
      s.entry = c;
      s.hh    = c;                                      // entry is next open; highs counted from then
      s.stop  = c - B1_SL_ATR * atr[k];
      Emit(s, r[k], "entry", "63- and 126-day returns both turned positive - buy next open", c, s.stop, silent, late, atr[k], 0, 0, r1, r2);
     }
   s.prevBoth = both;
  }

//+------------------------------------------------------------------+
//| Log + post one signal (silent = replay only, no output)          |
//+------------------------------------------------------------------+
void Emit(Sleeve &s, const MqlRates &bar, const string action, const string reason,
          const double price, const double stop, const bool silent, const bool late,
          const double atr, const double sma, const double rsi, const double r1, const double r2)
  {
   if(silent) return;

   string day   = TimeToString(bar.time, TIME_DATE);    // e.g. 2026.09.29 (broker time)
   string dayId = day;
   StringReplace(dayId, ".", "");
   string id    = KindName(s.kind) + "-" + s.sym + "-" + dayId + "-" + action;
   string now   = IsoGmt(TimeGMT());
   int    d     = s.digits;

   string json = "{";
   json += "\"signal_id\":\"" + id + "\",";
   json += "\"engine\":\"ZEC_" + KindName(s.kind) + "\",";
   json += "\"engine_version\":\"" + ENGINE_VERSION + "\",";
   json += "\"pair\":\"" + s.sym + "\",";
   json += "\"timeframe\":\"D1\",";
   json += "\"timestamp\":\"" + now + "\",";
   json += "\"sent_at\":\"" + now + "\",";
   json += "\"direction\":\"long\",";
   json += "\"confidence\":0.5,";
   json += "\"execution_price\":" + DoubleToString(price, d) + ",";
   json += "\"execution_status\":\"signal_only\",";
   json += "\"sl\":" + DoubleToString(stop, d) + ",";
   json += "\"tp\":0,";
   json += "\"explanation\":{\"rule\":\"" + reason + "\",\"note\":\"confidence is fixed at 0.5, not a probability; prices are signal-close references\"},";
   json += "\"payload\":{";
   json += "\"action\":\"" + action + "\",";
   json += "\"strategy\":\"" + KindName(s.kind) + "\",";
   json += "\"reason\":\"" + reason + "\",";
   json += "\"bar_date\":\"" + day + "\",";
   json += "\"late\":" + (late ? "true" : "false") + ",";
   json += "\"snapshot\":{\"price\":" + DoubleToString(bar.close, d) + "},";
   json += "\"close\":" + DoubleToString(bar.close, d) + ",";
   json += "\"high\":" + DoubleToString(bar.high, d) + ",";
   json += "\"low\":" + DoubleToString(bar.low, d) + ",";
   json += "\"atr20\":" + DoubleToString(atr, d);
   if(s.kind == KIND_G4)
      json += ",\"sma200\":" + DoubleToString(sma, d) + ",\"rsi2\":" + DoubleToString(rsi, 2);
   else
      json += ",\"ret63\":" + DoubleToString(r1, 5) + ",\"ret126\":" + DoubleToString(r2, 5);
   json += "}}";

   WriteLog(now, id, s, action, reason, day, price, stop, late);
   PrintFormat("SignalHub %s %s %s %s @ %s  stop %s%s", KindName(s.kind), s.sym, action, day,
               DoubleToString(price, d), DoubleToString(stop, d), late ? "  (late)" : "");
   if(action == "entry" || action == "exit")
      SaveLastPosted(s, bar.time);
   if(InpPostToApi && !MQLInfoInteger(MQL_TESTER))
     {
      if(!Post(json)) Enqueue(json);
     }
  }

//+------------------------------------------------------------------+
//| HTTP                                                             |
//+------------------------------------------------------------------+
bool Post(const string json)
  {
   char body[], result[];
   string resHeaders;
   int len = StringToCharArray(json, body, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0) ArrayResize(body, len - 1);            // drop the trailing zero
   ResetLastError();
   int code = WebRequest("POST", InpApiUrl, "Content-Type: application/json\r\n", 5000, body, result, resHeaders);
   if(code == -1)
     {
      int err = GetLastError();
      if(!g_webWarned)
        {
         if(err == 4014)
            Print("SignalHub: WebRequest not allowed. Add ", InpApiUrl, " host under Tools > Options > Expert Advisors > Allow WebRequest.");
         else
            Print("SignalHub: POST failed, error ", err, ". Is the Signal Scanner app running? Signals are queued and retried.");
         g_webWarned = true;
        }
      return(false);
     }
   if(code != 200)
     {
      Print("SignalHub: app answered HTTP ", code, ": ", CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8));
      return(code >= 400 && code < 500);                // 4xx = bad payload, retrying will not help
     }
   g_webWarned = false;
   return(true);
  }

void Enqueue(const string json)
  {
   int n = ArraySize(g_queue);
   if(n >= MAX_QUEUE)
     {
      for(int i = 1; i < n; i++) g_queue[i - 1] = g_queue[i];  // drop the oldest
      n--;
      ArrayResize(g_queue, n);
     }
   ArrayResize(g_queue, n + 1);
   g_queue[n] = json;
  }

void FlushQueue()
  {
   int n = ArraySize(g_queue);
   if(n == 0 || !InpPostToApi || MQLInfoInteger(MQL_TESTER)) return;
   int sent = 0;
   while(sent < n && Post(g_queue[sent])) sent++;
   if(sent == 0) return;
   for(int i = sent; i < n; i++) g_queue[i - sent] = g_queue[i];
   ArrayResize(g_queue, n - sent);
   if(ArraySize(g_queue) == 0) Print("SignalHub: queued signals delivered.");
  }

//+------------------------------------------------------------------+
//| CSV log in Common\Files                                          |
//+------------------------------------------------------------------+
void WriteLog(const string when, const string id, const Sleeve &s, const string action,
              const string reason, const string day, const double price, const double stop, const bool late)
  {
   int h = FileOpen(InpLogFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) { Print("SignalHub: cannot open log ", InpLogFile, ", error ", GetLastError()); return; }
   if(FileSize(h) == 0)
      FileWrite(h, "sent_utc", "signal_id", "strategy", "symbol", "action", "bar_date", "price", "stop", "late", "reason");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, when, id, KindName(s.kind), s.sym, action, day,
             DoubleToString(price, s.digits), DoubleToString(stop, s.digits), late ? "yes" : "no", reason);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Last posted bar per sleeve (survives restarts)                   |
//+------------------------------------------------------------------+
string GvName(const Sleeve &s) { return("ZECSH_" + KindName(s.kind) + "_" + s.sym); }

datetime LastPosted(const Sleeve &s)
  {
   string name = GvName(s);
   if(!GlobalVariableCheck(name)) return(0);
   return((datetime)GlobalVariableGet(name));
  }

void SaveLastPosted(const Sleeve &s, const datetime t)
  {
   GlobalVariableSet(GvName(s), (double)t);
  }

//+------------------------------------------------------------------+
//| Chart panel                                                      |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   string txt = "ZEC SignalHub " + ENGINE_VERSION + "  |  signal-only, no trades\n";
   txt += "API: " + (InpPostToApi ? InpApiUrl : "off") + "   queued: " + IntegerToString(ArraySize(g_queue)) + "\n";
   txt += "--------------------------------------------------------------\n";
   for(int i = 0; i < ArraySize(g_sl); i++)
     {
      Sleeve s = g_sl[i];
      string line = StringFormat("%-3s %-9s ", KindName(s.kind), s.sym);
      if(!s.ready) { txt += line + "loading history...\n"; continue; }
      line += (s.inPos ? "IN   stop " + DoubleToString(s.stop, s.digits) : "FLAT");
      if(s.kind == KIND_G4)
         line += StringFormat("   RSI2 %.1f   %s SMA200", s.lastRsi, s.lastClose > s.lastSma ? "above" : "below");
      else
         line += StringFormat("   63d %+.1f%%   126d %+.1f%%", s.lastR1 * 100.0, s.lastR2 * 100.0);
      txt += line + "\n";
     }
   Comment(txt);
  }

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
string KindName(const int kind) { return(kind == KIND_G4 ? "G4" : "B1"); }

bool Valid(const double v) { return(IsNum(v) && v > 0.0); }          // prices, SMA, ATR

bool IsNum(const double v) { return(v != EMPTY_VALUE && MathIsValidNumber(v)); }

string IsoGmt(const datetime t)
  {
   string s = TimeToString(t, TIME_DATE | TIME_SECONDS);   // 2026.09.29 09:15:02
   StringReplace(s, ".", "-");
   StringReplace(s, " ", "T");
   return(s + "Z");
  }
//+------------------------------------------------------------------+
