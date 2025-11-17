//+------------------------------------------------------------------+
//|                           BBMAC_v2.1_Simplified_Conservative.mq4 |
//|                      With Optional H1 Confirmation Filter         |
//|                           Pure Reentry Detection on H4            |
//|                                                                    |
//|  Version 2.1 - Optimized with Shared Library                      |
//|  - Fixed UTF-16 encoding issue                                    |
//|  - Uses BBMAC_Common.mqh for shared functions                     |
//|  - Added input validation                                         |
//|  - Improved pending signals management                            |
//|  - Better memory management                                       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 8

//--- Include shared library
#include <BBMAC_Common.mqh>

//==================================================================
// CONSTANTS
//==================================================================
#define BB_PERIOD       20
#define BB_DEVIATION    2.0
#define ARROW_OFFSET_BUY    0.08
#define ARROW_OFFSET_SELL   0.20
#define MAX_PENDING_SIGNALS 100

//==================================================================
// INPUT PARAMETERS
//==================================================================

//--- Display Settings
input group "==== Display Settings ===="
color   Col_BB_UpperLower = C'50,50,50';
color   Col_BB_Middle     = C'81,0,81';
color   Col_MA_High       = C'98,0,0';
color   Col_MA_Low        = C'0,77,0';
color   Col_EMA50         = clrDimGray;
input int     Width_BB         = 2;        // BB Line Width (1-5)
input int     Width_MA5        = 2;        // LWMA5 Width (1-5)
input int     Width_MA10       = 1;        // LWMA10 Width (1-5)
input int     Width_EMA50      = 1;        // EMA50 Width (1-5)
input int     Offset_From_Right  = 25;     // Toggle Button X Offset
input int     Offset_From_Bottom = 25;     // Toggle Button Y Offset
input bool    Show_On_Load     = true;     // Show Indicator on Load
input int     Toggle_Size      = 15;       // Toggle Button Size

//--- Reentry Detection
input group "==== Reentry Detection ===="
input bool    Enable_Reentry_Detection = true;
input bool    Scan_History         = true;
input int     History_Bars_Input   = 100;       // History Bars to Scan (10-1000)
input double  Touch_Tolerance_Input = 2.0;      // Touch Tolerance in Pips (0-10)
input int     Arrow_Size_Input     = 1;         // Arrow Size (1-5)
input color   Arrow_Color_Buy      = clrLime;   // Buy Arrow Color
input color   Arrow_Color_Sell     = clrRed;    // Sell Arrow Color
input color   Arrow_Color_Pending  = clrDarkGray; // Pending Arrow Color

//--- Conservative Filter
input group "==== Conservative Filter ===="
input bool    Enable_Conservative_Filter = false;  // Enable Conservative H1 Filter
input int     H1_Confirmation_Candles = 9;         // H1 Candles for Confirmation (1-20)

//--- Advanced Settings
input group "==== Advanced ===="
input int     Pending_Signal_Expiry_Hours = 24;    // Pending Signal Expiry (1-72 hours)
input bool    Debug_Mode = false;                  // Enable Debug Logging

//==================================================================
// GLOBAL VARIABLES
//==================================================================

//--- Indicator Buffers
double bbUpper[], bbMiddle[], bbLower[];
double ma10High[], ma10Low[], ma5High[], ma5Low[], ema50[];

//--- Display State
bool   gShow = true;
string BTN_NAME;
bool   lastShowState = false;
bool   needsUpdate = false;
int    lastCalculatedBars = 0;

//--- Reentry Settings (validated)
int    History_Bars;
double Touch_Tolerance_Pips;
int    Arrow_Size;

//--- Mood State
string moodMH4 = "";
datetime lastH4Time = 0;

//--- History Scan
bool   historyScanned = false;
int    lastProcessedBarH4 = -1;

//--- Arrow Management
string arrowList[];
int    arrowCount = 0;

//--- Unique Prefix
string chartPrefix;

//--- Pending Signals Structure
struct PendingSignal {
   datetime h4Time;
   string signalType;
   double price;
   int h1CandlesChecked;
   datetime lastH1Checked;
   string arrowName;
   bool active;
};

PendingSignal pendingSignals[];
int pendingCount = 0;

//==================================================================
// ARROW MANAGEMENT
//==================================================================

void DeleteAllArrows() {
   for(int i = 0; i < arrowCount; i++) {
      SafeObjectDelete(arrowList[i]);
   }
   ArrayResize(arrowList, 0);
   arrowCount = 0;
   LogDebug("ArrowManager", "All arrows deleted", Debug_Mode);
}

bool AddArrow(string name) {
   if(arrowCount >= MAX_OBJECTS) {
      LogError("AddArrow", "Max arrows reached: " + IntegerToString(MAX_OBJECTS));
      return false;
   }

   ArrayResize(arrowList, arrowCount + 1);
   arrowList[arrowCount] = name;
   arrowCount++;
   return true;
}

void DrawArrow(int bar, string type, double price, datetime barTime, bool isPending = false) {
   if(arrowCount >= MAX_OBJECTS) return;

   string objName = chartPrefix + "AR_" + type + "_" + TimeToString(barTime, TIME_DATE|TIME_MINUTES);

   // Update existing arrow if needed
   if(ObjectFind(objName) >= 0) {
      color dotColor = isPending ? Arrow_Color_Pending :
                      (type == "BUY" ? Arrow_Color_Buy : Arrow_Color_Sell);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, gShow ? dotColor : clrNONE);
      return;
   }

   // Determine color
   color dotColor = isPending ? Arrow_Color_Pending :
                   (type == "BUY" ? Arrow_Color_Buy : Arrow_Color_Sell);

   // Calculate arrow position offset
   double avgRange = 0;
   int count = 0;
   for(int i = bar; i < bar + 5 && i < Bars; i++) {
      avgRange += (High[i] - Low[i]);
      count++;
   }
   if(count > 0) avgRange /= count;
   else return;

   double offset = (type == "BUY") ?
                   -avgRange * ARROW_OFFSET_BUY : avgRange * ARROW_OFFSET_SELL;
   double dotPrice = price + offset;

   // Create arrow object
   if(!ObjectCreate(objName, OBJ_ARROW, 0, barTime, dotPrice)) {
      LogError("DrawArrow", "Failed to create: " + objName, GetLastError());
      return;
   }

   ObjectSet(objName, OBJPROP_ARROWCODE, 159);
   ObjectSet(objName, OBJPROP_WIDTH, Arrow_Size);
   ObjectSet(objName, OBJPROP_BACK, false);
   ObjectSet(objName, OBJPROP_SELECTABLE, false);
   ObjectSet(objName, OBJPROP_HIDDEN, true);
   ObjectSet(objName, OBJPROP_COLOR, gShow ? dotColor : clrNONE);

   string tooltip = type + " Reentry [H4]";
   if(isPending) tooltip += " - Waiting H1 Confirmation";
   ObjectSetString(0, objName, OBJPROP_TOOLTIP, tooltip);

   AddArrow(objName);
}

void UpdateArrowVisibility() {
   for(int i = 0; i < arrowCount; i++) {
      if(ObjectFind(arrowList[i]) < 0) continue;

      color c = clrNONE;
      if(gShow) {
         color currentColor = (color)ObjectGetInteger(0, arrowList[i], OBJPROP_COLOR);
         if(currentColor == Arrow_Color_Pending) {
            c = Arrow_Color_Pending;
         } else {
            c = (StringFind(arrowList[i], "_BUY_") != -1) ? Arrow_Color_Buy : Arrow_Color_Sell;
         }
      }
      ObjectSetInteger(0, arrowList[i], OBJPROP_COLOR, c);
   }
}

//==================================================================
// REENTRY PATTERN DETECTION
//==================================================================

bool CheckReentryPattern(int bar, string mood, string &signalType) {
   if(mood == "") return false;

   MoodData data = GetMoodData(0, bar);
   if(!data.valid) return false;

   double cHigh = High[bar];
   double cLow = Low[bar];
   double cClose = Close[bar];
   double tol = Point * Touch_Tolerance_Pips;

   if(mood == "BUY") {
      bool touch = (cLow <= (data.lwma5Low + tol)) ||
                   (cLow <= (data.lwma10Low + tol));
      bool valid = (cClose >= (data.lwma10Low - tol));

      if(touch && valid) {
         signalType = "BUY";
         return true;
      }
   }

   if(mood == "SELL") {
      bool touch = (cHigh >= (data.lwma5High - tol)) ||
                   (cHigh >= (data.lwma10High - tol));
      bool valid = (cClose <= (data.lwma10High + tol));

      if(touch && valid) {
         signalType = "SELL";
         return true;
      }
   }

   return false;
}

//==================================================================
// H1 CONFIRMATION FILTER
//==================================================================

bool CheckH1Break(string signalType, datetime startTime, int maxCandles, int &candlesChecked) {
   datetime h4CloseTime = startTime + (PERIOD_H4 * 60);
   datetime h1FirstTime = h4CloseTime - (PERIOD_H1 * 60);

   int h1FirstBar = iBarShift(NULL, PERIOD_H1, h1FirstTime, false);
   if(h1FirstBar < 0) {
      LogDebug("CheckH1Break", "Cannot find H1 bar at " + TimeToString(h1FirstTime), Debug_Mode);
      return false;
   }

   LogDebug("CheckH1Break",
            StringFormat("H4 reentry: %s to %s, H1 first candle: %s (bar %d)",
                        TimeToString(startTime), TimeToString(h4CloseTime),
                        TimeToString(h1FirstTime), h1FirstBar),
            Debug_Mode);

   int endBar = MathMax(0, h1FirstBar - (maxCandles - 1));

   for(int i = h1FirstBar; i >= endBar; i--) {
      datetime h1Time = iTime(NULL, PERIOD_H1, i);
      datetime h1CloseTime = h1Time + (PERIOD_H1 * 60);

      // Skip current unclosed candle
      if(i == 0 && TimeCurrent() < h1CloseTime) {
         LogDebug("CheckH1Break", StringFormat("H1 bar 0 (%s) not closed yet, skip", TimeToString(h1Time)), Debug_Mode);
         continue;
      }

      candlesChecked++;

      double h1Close = iClose(NULL, PERIOD_H1, i);
      double lwma5High = iMA(NULL, PERIOD_H1, 5, 0, MODE_LWMA, PRICE_HIGH, i);
      double lwma5Low = iMA(NULL, PERIOD_H1, 5, 0, MODE_LWMA, PRICE_LOW, i);
      double lwma10High = iMA(NULL, PERIOD_H1, 10, 0, MODE_LWMA, PRICE_HIGH, i);
      double lwma10Low = iMA(NULL, PERIOD_H1, 10, 0, MODE_LWMA, PRICE_LOW, i);

      if(lwma5High <= 0 || lwma5Low <= 0 || lwma10High <= 0 || lwma10Low <= 0 || h1Close <= 0) {
         LogDebug("CheckH1Break", StringFormat("Invalid data at H1 bar %d, skip", i), Debug_Mode);
         continue;
      }

      if(signalType == "BUY") {
         LogDebug("CheckH1Break",
                  StringFormat("H1[%d] bar %d (%s): close=%.5f vs lwma5High=%.5f, lwma10High=%.5f",
                              candlesChecked, i, TimeToString(h1Time), h1Close, lwma5High, lwma10High),
                  Debug_Mode);

         if(h1Close > lwma5High && h1Close > lwma10High) {
            LogDebug("CheckH1Break", StringFormat(">>> H1 Break BUY confirmed at bar %d (%s)", i, TimeToString(h1Time)), Debug_Mode);
            return true;
         }
      } else if(signalType == "SELL") {
         LogDebug("CheckH1Break",
                  StringFormat("H1[%d] bar %d (%s): close=%.5f vs lwma5Low=%.5f, lwma10Low=%.5f",
                              candlesChecked, i, TimeToString(h1Time), h1Close, lwma5Low, lwma10Low),
                  Debug_Mode);

         if(h1Close < lwma5Low && h1Close < lwma10Low) {
            LogDebug("CheckH1Break", StringFormat(">>> H1 Break SELL confirmed at bar %d (%s)", i, TimeToString(h1Time)), Debug_Mode);
            return true;
         }
      }
   }

   LogDebug("CheckH1Break", StringFormat(">>> No H1 break found after checking %d candles", candlesChecked), Debug_Mode);
   return false;
}

//==================================================================
// PENDING SIGNALS MANAGEMENT
//==================================================================

void AddPendingSignal(datetime h4Time, string signalType, double price) {
   if(pendingCount >= MAX_PENDING_SIGNALS) return;

   // Skip current H4 candle (bar 0)
   int h4Bar = iBarShift(NULL, PERIOD_H4, h4Time, false);
   if(h4Bar == 0) {
      LogDebug("PendingSignals", "Skipping pending signal for current H4 candle (bar 0)", Debug_Mode);
      return;
   }

   // Check if signal already exists
   for(int i = 0; i < pendingCount; i++) {
      if(pendingSignals[i].h4Time == h4Time && pendingSignals[i].active) {
         LogDebug("PendingSignals", "Signal already exists for H4 time " + TimeToString(h4Time), Debug_Mode);
         return;
      }
   }

   ArrayResize(pendingSignals, pendingCount + 1);
   pendingSignals[pendingCount].h4Time = h4Time;
   pendingSignals[pendingCount].signalType = signalType;
   pendingSignals[pendingCount].price = price;
   pendingSignals[pendingCount].h1CandlesChecked = 0;
   pendingSignals[pendingCount].lastH1Checked = 0;
   pendingSignals[pendingCount].active = true;
   pendingSignals[pendingCount].arrowName = chartPrefix + "AR_" + signalType + "_" +
                                            TimeToString(h4Time, TIME_DATE|TIME_MINUTES);

   pendingCount++;

   LogDebug("PendingSignals",
            StringFormat("Added pending %s signal at %s, total pending: %d",
                        signalType, TimeToString(h4Time), pendingCount),
            Debug_Mode);
}

void UpdatePendingSignals() {
   if(!Enable_Conservative_Filter) return;
   if(pendingCount == 0) return;

   for(int i = 0; i < pendingCount; i++) {
      if(!pendingSignals[i].active) continue;

      // Check expiry
      datetime h4CloseTime = pendingSignals[i].h4Time + (PERIOD_H4 * 60);
      datetime maxWaitTime = h4CloseTime + (H1_Confirmation_Candles * PERIOD_H1 * 60) + 3600;

      if(TimeCurrent() > maxWaitTime) {
         LogDebug("PendingSignals",
                  StringFormat("Signal expired (too old): %s at %s",
                              pendingSignals[i].signalType, TimeToString(pendingSignals[i].h4Time)),
                  Debug_Mode);

         SafeObjectDelete(pendingSignals[i].arrowName);
         pendingSignals[i].active = false;
         continue;
      }

      int candlesChecked = 0;
      bool breakConfirmed = CheckH1Break(pendingSignals[i].signalType,
                                         pendingSignals[i].h4Time,
                                         H1_Confirmation_Candles,
                                         candlesChecked);

      pendingSignals[i].h1CandlesChecked += candlesChecked;

      if(breakConfirmed) {
         LogDebug("PendingSignals",
                  StringFormat(">>> Signal confirmed! Updating arrow to final color: %s at %s",
                              pendingSignals[i].signalType, TimeToString(pendingSignals[i].h4Time)),
                  Debug_Mode);

         int h4Bar = iBarShift(NULL, PERIOD_H4, pendingSignals[i].h4Time, false);
         if(h4Bar >= 0) {
            DrawArrow(h4Bar, pendingSignals[i].signalType, pendingSignals[i].price,
                     pendingSignals[i].h4Time, false);
         }

         pendingSignals[i].active = false;
      } else if(pendingSignals[i].h1CandlesChecked >= H1_Confirmation_Candles) {
         LogDebug("PendingSignals",
                  StringFormat(">>> Signal rejected after %d H1 candles. Removing arrow at %s",
                              pendingSignals[i].h1CandlesChecked, TimeToString(pendingSignals[i].h4Time)),
                  Debug_Mode);

         SafeObjectDelete(pendingSignals[i].arrowName);
         pendingSignals[i].active = false;
      }
   }

   // Cleanup inactive signals
   int activeCount = 0;
   for(int i = 0; i < pendingCount; i++) {
      if(pendingSignals[i].active) {
         if(i != activeCount) {
            pendingSignals[activeCount] = pendingSignals[i];
         }
         activeCount++;
      }
   }

   if(activeCount != pendingCount) {
      LogDebug("PendingSignals",
               StringFormat("Cleaned up pending signals: %d -> %d active", pendingCount, activeCount),
               Debug_Mode);
   }

   ArrayResize(pendingSignals, activeCount);
   pendingCount = activeCount;
}

void ProcessReentrySignal(int bar, string signalType, double price, datetime barTime) {
   // Skip current H4 candle (bar 0)
   if(bar == 0) {
      LogDebug("ReentryDetection", "Skipping reentry signal for current H4 candle (bar 0)", Debug_Mode);
      return;
   }

   if(!Enable_Conservative_Filter) {
      // Normal mode: show arrow immediately
      DrawArrow(bar, signalType, price, barTime, false);
      LogDebug("ReentryDetection", StringFormat("New %s signal at bar %d (no filter)", signalType, bar), Debug_Mode);
   } else {
      // Conservative mode
      if(bar >= 2) {
         // Historical data: check H1 immediately
         int candlesChecked = 0;
         bool breakConfirmed = CheckH1Break(signalType, barTime, H1_Confirmation_Candles, candlesChecked);

         if(breakConfirmed) {
            DrawArrow(bar, signalType, price, barTime, false);
            LogDebug("ReentryDetection",
                     StringFormat(">>> Historical %s signal CONFIRMED at bar %d (checked %d H1 candles)",
                                 signalType, bar, candlesChecked),
                     Debug_Mode);
         } else {
            LogDebug("ReentryDetection",
                     StringFormat(">>> Historical %s signal REJECTED at bar %d (no break in %d H1 candles)",
                                 signalType, bar, candlesChecked),
                     Debug_Mode);
         }
      } else {
         // Recent data: use pending signal
         DrawArrow(bar, signalType, price, barTime, true);
         AddPendingSignal(barTime, signalType, price);
         LogDebug("ReentryDetection",
                  StringFormat("New PENDING %s signal at bar %d (waiting H1 confirmation)",
                              signalType, bar),
                  Debug_Mode);
      }
   }
}

//==================================================================
// HISTORY SCAN & REENTRY DETECTION
//==================================================================

void ScanHistory(string &currentMood, int &lastProcessed) {
   if(!Enable_Reentry_Detection || !Scan_History) return;
   if(Period() != PERIOD_H4) return;

   int barsToScan = MathMin(History_Bars, Bars);
   if(barsToScan <= 2) return;

   LogDebug("HistoryScan", StringFormat("Starting history scan: %d bars", barsToScan), Debug_Mode);

   if(currentMood == "") {
      currentMood = InitializeMood(PERIOD_H4, 1);
      LogDebug("HistoryScan", "Initial MH4: " + currentMood, Debug_Mode);
   }

   string mood = currentMood;

   for(int i = barsToScan - 1; i >= 2; i--) {
      MoodData data = GetMoodData(PERIOD_H4, i);
      if(data.valid) {
         mood = CalculateMood(data, mood);

         string sig = "";
         if(CheckReentryPattern(i, mood, sig)) {
            double p = (sig == "BUY") ? Low[i] : High[i];
            ProcessReentrySignal(i, sig, p, Time[i]);
         }
      }
   }

   currentMood = mood;
   lastProcessed = Bars - 2;
   LogDebug("HistoryScan", StringFormat("History scan complete. Final MH4: %s", currentMood), Debug_Mode);
}

void DetectReentry(string &mood, int &lastProcessed) {
   if(!Enable_Reentry_Detection) return;
   if(Period() != PERIOD_H4) return;

   int checkBar = 1;
   if(Bars < 20) return;
   if(lastProcessed == Bars - checkBar) return;

   lastProcessed = Bars - checkBar;
   MoodData data = GetMoodData(PERIOD_H4, checkBar);
   if(data.valid) {
      mood = CalculateMood(data, mood);

      string sig = "";
      if(CheckReentryPattern(checkBar, mood, sig)) {
         double p = (sig == "BUY") ? Low[checkBar] : High[checkBar];
         ProcessReentrySignal(checkBar, sig, p, Time[checkBar]);
      }
   }
}

//==================================================================
// TOGGLE BUTTON MANAGEMENT
//==================================================================

string MakeButtonName() {
   return StringFormat("BBMA_BTN_%s_%d_%I64d", Symbol(), Period(), ChartID());
}

void UpdateButton() {
   if(ObjectFind(0, BTN_NAME) < 0) return;
   if(!needsUpdate && lastShowState == gShow) return;

   ObjectSetInteger(0, BTN_NAME, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_XDISTANCE, Offset_From_Right);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_YDISTANCE, Offset_From_Bottom);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_XSIZE, Toggle_Size);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_YSIZE, Toggle_Size);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_FONTSIZE, 1);
   ObjectSetString(0, BTN_NAME, OBJPROP_TEXT, "");
   ObjectSetInteger(0, BTN_NAME, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_BACK, true);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_HIDDEN, false);

   color btnColor = gShow ? clrDarkGreen : C'60,60,60';
   ObjectSetInteger(0, BTN_NAME, OBJPROP_BGCOLOR, btnColor);
   ObjectSetInteger(0, BTN_NAME, OBJPROP_COLOR, btnColor);
   ObjectSetString(0, BTN_NAME, OBJPROP_TOOLTIP, gShow ? "ON (B)" : "OFF (B)");

   needsUpdate = false;
}

void CreateToggleButton() {
   BTN_NAME = MakeButtonName();

   if(ObjectFind(0, BTN_NAME) >= 0) {
      ObjectDelete(0, BTN_NAME);
   }

   if(!ObjectCreate(0, BTN_NAME, OBJ_BUTTON, 0, 0, 0)) {
      LogError("CreateButton", "Failed to create toggle button", GetLastError());
      return;
   }

   needsUpdate = true;
   UpdateButton();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
}

void ApplyStyles() {
   color u = gShow ? Col_BB_UpperLower : clrNONE;
   color m = gShow ? Col_BB_Middle : clrNONE;
   color r = gShow ? Col_MA_High : clrNONE;
   color g = gShow ? Col_MA_Low : clrNONE;
   color e = gShow ? Col_EMA50 : clrNONE;

   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, Width_BB, u);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, Width_BB, m);
   SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, Width_BB, u);
   SetIndexStyle(3, DRAW_LINE, STYLE_DOT, Width_MA10, r);
   SetIndexStyle(4, DRAW_LINE, STYLE_DOT, Width_MA10, g);
   SetIndexStyle(5, DRAW_LINE, STYLE_SOLID, Width_MA5, r);
   SetIndexStyle(6, DRAW_LINE, STYLE_SOLID, Width_MA5, g);
   SetIndexStyle(7, DRAW_LINE, STYLE_DOT, Width_EMA50, e);

   lastShowState = gShow;
   needsUpdate = true;
   UpdateButton();
}

void Toggle() {
   gShow = !gShow;
   SaveState("SHOW", gShow);
   ApplyStyles();
   UpdateArrowVisibility();
   ChartRedraw();
}

//==================================================================
// INDICATOR LIFECYCLE
//==================================================================

int OnInit() {
   IndicatorShortName("BBMAC v2.1 - Conservative Filter (B=Toggle)");

   // Setup buffers
   SetIndexBuffer(0, bbUpper);    SetIndexLabel(0, "BB Upper");
   SetIndexBuffer(1, bbMiddle);   SetIndexLabel(1, "BB Middle");
   SetIndexBuffer(2, bbLower);    SetIndexLabel(2, "BB Lower");
   SetIndexBuffer(3, ma10High);   SetIndexLabel(3, "LWMA10 High");
   SetIndexBuffer(4, ma10Low);    SetIndexLabel(4, "LWMA10 Low");
   SetIndexBuffer(5, ma5High);    SetIndexLabel(5, "LWMA5 High");
   SetIndexBuffer(6, ma5Low);     SetIndexLabel(6, "LWMA5 Low");
   SetIndexBuffer(7, ema50);      SetIndexLabel(7, "EMA50");

   for(int i = 0; i < 8; i++) {
      SetIndexEmptyValue(i, EMPTY_VALUE);
   }

   // Validate inputs
   Touch_Tolerance_Pips = ValidateDouble(Touch_Tolerance_Input, 0, 10, 2.0);
   History_Bars = ValidateInt(History_Bars_Input, 10, 1000, 100);
   Arrow_Size = ValidateInt(Arrow_Size_Input, 1, 5, 1);

   // Chart prefix
   chartPrefix = GetChartPrefix();

   // Check minimum bars
   if(iBars(NULL, 0) < BB_PERIOD) {
      LogError("OnInit", "Insufficient bars. Need at least " + IntegerToString(BB_PERIOD));
      return INIT_FAILED;
   }

   // Load state
   gShow = LoadState("SHOW", Show_On_Load);
   lastShowState = gShow;

   // Create toggle button
   CreateToggleButton();

   // Initialize reentry detection
   if(Enable_Reentry_Detection) {
      if(Period() == PERIOD_H4 && !historyScanned) {
         ScanHistory(moodMH4, lastProcessedBarH4);
         historyScanned = true;
      } else {
         moodMH4 = InitializeMood(PERIOD_H4, 1);
      }
   }

   ApplyStyles();
   UpdateArrowVisibility();

   // Print initialization info
   PrintBBMACHeader("BBMAC Advance v2.1");
   Print("Conservative Filter: ", Enable_Conservative_Filter ? "ACTIVE" : "INACTIVE");
   Print("H1 Confirmation Candles: ", H1_Confirmation_Candles);
   Print("Hotkey: B = Toggle Display");
   Print("=======================================");

   LogDebug("OnInit", "Initialization complete", Debug_Mode);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   SaveState("SHOW", gShow);

   SafeObjectDelete(BTN_NAME);
   DeleteAllArrows();

   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE) {
      CleanupState("SHOW");
   }

   LogDebug("OnDeinit", "Deinitialization complete", Debug_Mode);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   // Button click
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_NAME) {
      Toggle();
      return;
   }

   // Hotkey 'B' (66)
   if(id == CHARTEVENT_KEYDOWN && lparam == 66) {
      Toggle();
      return;
   }

   // Chart change
   if(id == CHARTEVENT_CHART_CHANGE) {
      needsUpdate = true;
      UpdateButton();
      ChartRedraw();
   }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {

   if(rates_total < BB_PERIOD) return 0;

   // Calculate indicators
   int limit = (prev_calculated == 0) ? MathMin(rates_total - BB_PERIOD, 1000) : 1;

   for(int i = limit; i >= 0; i--) {
      // Bollinger Bands
      double sma = iMA(NULL, 0, BB_PERIOD, 0, MODE_SMA, PRICE_CLOSE, i);
      double sdev = iStdDev(NULL, 0, BB_PERIOD, 0, MODE_SMA, PRICE_CLOSE, i);

      if(sma > 0 && sdev >= 0) {
         bbMiddle[i] = sma;
         bbUpper[i] = sma + BB_DEVIATION * sdev;
         bbLower[i] = sma - BB_DEVIATION * sdev;
      } else {
         bbMiddle[i] = EMPTY_VALUE;
         bbUpper[i] = EMPTY_VALUE;
         bbLower[i] = EMPTY_VALUE;
      }

      // LWMA
      ma10High[i] = iMA(NULL, 0, 10, 0, MODE_LWMA, PRICE_HIGH, i);
      ma10Low[i] = iMA(NULL, 0, 10, 0, MODE_LWMA, PRICE_LOW, i);
      ma5High[i] = iMA(NULL, 0, 5, 0, MODE_LWMA, PRICE_HIGH, i);
      ma5Low[i] = iMA(NULL, 0, 5, 0, MODE_LWMA, PRICE_LOW, i);

      // EMA 50
      ema50[i] = iMA(NULL, 0, 50, 0, MODE_EMA, PRICE_CLOSE, i);

      // Validate values
      if(ma10High[i] <= 0) ma10High[i] = EMPTY_VALUE;
      if(ma10Low[i] <= 0) ma10Low[i] = EMPTY_VALUE;
      if(ma5High[i] <= 0) ma5High[i] = EMPTY_VALUE;
      if(ma5Low[i] <= 0) ma5Low[i] = EMPTY_VALUE;
      if(ema50[i] <= 0) ema50[i] = EMPTY_VALUE;
   }

   // Update pending signals
   if(Enable_Conservative_Filter) {
      UpdatePendingSignals();
   }

   // Detect new reentry signals
   if(rates_total != lastCalculatedBars) {
      if(Enable_Reentry_Detection && Period() == PERIOD_H4) {
         datetime currentH4 = iTime(NULL, PERIOD_H4, 1);
         if(currentH4 != lastH4Time) {
            MoodData data = GetMoodData(PERIOD_H4, 1);
            if(data.valid) {
               string newMH4 = CalculateMood(data, moodMH4);
               if(newMH4 != moodMH4) {
                  LogDebug("OnCalculate", "MH4 changed: " + moodMH4 + " -> " + newMH4, Debug_Mode);
                  moodMH4 = newMH4;
               }
            }
            lastH4Time = currentH4;
            DetectReentry(moodMH4, lastProcessedBarH4);
         }
      }

      lastCalculatedBars = rates_total;
   }

   return rates_total;
}
//+------------------------------------------------------------------+
