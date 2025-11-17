//+------------------------------------------------------------------+
//|                                              MoodPanel v3.1.mq4  |
//|                      Hanya Menampilkan Panel Mood                 |
//|                Dipisah dari BBMAC_v2 (Coding Partner)             |
//|                                                                    |
//|  Version 3.1 - Optimized with Shared Library                      |
//|  - Uses BBMAC_Common.mqh for shared functions                     |
//|  - Added input validation                                         |
//|  - Enhanced tooltips with trend strength                          |
//|  - Customizable box size                                          |
//|  - Better update trigger (works on all timeframes)                |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 0

//--- Include shared library
#include <BBMAC_Common.mqh>

//==================================================================
// INPUT PARAMETERS
//==================================================================

//--- Display Settings
input group "==== Display Settings ===="
input bool   Show_Mood_Panel    = true;    // Show/Hide Mood Panel
input int    MoodPanel_X_Offset = 110;     // Panel X Offset (10-500)
input int    MoodPanel_Y_Offset = 15;      // Panel Y Offset (10-500)
input int    Box_Size           = 15;      // Mood Box Size (10-30)
input int    Box_Spacing        = 5;       // Box Spacing (2-20)
input int    Gap_After_MD1      = 15;      // Gap After MD1 (5-30)
input ENUM_BASE_CORNER Panel_Corner = CORNER_RIGHT_UPPER; // Panel Position

//--- Mood Timeframes
input group "==== Mood Timeframes ===="
input bool   Enable_MDC  = true;           // Show MDC (Daily Candle)
input bool   Enable_MH4  = true;           // Show MH4 (H4 LWMA)
input bool   Enable_MH1  = true;           // Show MH1 (H1 LWMA)
input bool   Enable_MD1  = true;           // Show MD1 (Daily LWMA)
input bool   Enable_MW   = true;           // Show MW (Weekly LWMA)
input bool   Enable_MMN  = true;           // Show MMN (Monthly LWMA)

//--- Colors
input group "==== Colors ===="
input color  Color_Buy     = clrDarkGreen;  // BUY Color
input color  Color_Sell    = clrMaroon;     // SELL Color
input color  Color_Neutral = C'40,40,40';   // Neutral Color

//--- Advanced
input group "==== Advanced ===="
input bool   Show_Detailed_Tooltip = true; // Show Detailed Tooltip
input bool   Debug_Mode = false;           // Enable Debug Logging

//==================================================================
// GLOBAL VARIABLES
//==================================================================

//--- Mood States
string moodMDC = "", moodMH4 = "", moodMH1 = "";
string moodMD1 = "", moodMW = "", moodMMN = "";
string prevMDC = "", prevMH4 = "", prevMH1 = "";
string prevMD1 = "", prevMW = "", prevMMN = "";

//--- Last Update Times
datetime lastH4Time = 0, lastH1Time = 0, lastDCTime = 0;
datetime lastD1Time = 0, lastW1Time = 0, lastMNTime = 0;

//--- Unique Prefixes
string chartPrefix;
string moodPrefix;

//--- Last bar check untuk update trigger
datetime lastBarTime = 0;

//==================================================================
// MOOD CALCULATION
//==================================================================

string CalculateMDC() {
   if(!Enable_MDC) return "";

   datetime currentDC = iTime(NULL, PERIOD_D1, 1);
   if(currentDC == lastDCTime && moodMDC != "") return moodMDC;

   lastDCTime = currentDC;
   return CalculateCloseMood(PERIOD_D1);
}

//==================================================================
// PANEL DISPLAY
//==================================================================

void DeleteMoodPanel() {
   string names[6] = {"MOOD_MH1", "MOOD_MH4", "MOOD_MDC", "MOOD_MD1", "MOOD_MW", "MOOD_MMN"};
   for(int i = 0; i < 6; i++) {
      string objName = moodPrefix + names[i];
      SafeObjectDelete(objName);
   }
}

double CalculateTrendStrength(MoodData &data) {
   if(!data.valid) return 0;

   double range = data.lwma10High - data.lwma10Low;
   if(range <= 0) return 0;

   double position = (data.close - data.lwma10Low) / range;
   return MathAbs(position - 0.5) * 200; // 0% at middle, 100% at extremes
}

string CreateDetailedTooltip(string label, string mood, datetime lastUpdate, int timeframe) {
   string tooltip = label + ": " + mood;

   if(Show_Detailed_Tooltip && lastUpdate > 0) {
      tooltip += "\nLast Update: " + FormatDateTime(lastUpdate);

      // Add trend strength for LWMA-based moods (not MDC)
      if(label != "MDC" && timeframe > 0) {
         MoodData data = GetMoodData(timeframe, 1);
         if(data.valid) {
            double strength = CalculateTrendStrength(data);
            tooltip += "\nStrength: " + DoubleToString(strength, 1) + "%";
         }
      }
   }

   return tooltip;
}

void UpdateMoodPanel() {
   if(!Show_Mood_Panel) {
      DeleteMoodPanel();
      return;
   }

   // Check if anything changed
   bool changed = (moodMDC != prevMDC || moodMH4 != prevMH4 || moodMH1 != prevMH1 ||
                   moodMD1 != prevMD1 || moodMW != prevMW || moodMMN != prevMMN);

   if(!changed && ObjectFind(moodPrefix + "MOOD_MH1") >= 0) return;

   int xPos = MoodPanel_X_Offset;

   // Mood boxes structure
   struct MoodBox {
      string name;
      string mood;
      string label;
      bool enabled;
      int timeframe;
      datetime lastUpdate;
   };

   // Layout: MMN MW MD1 | MDC MH4 MH1 (right to left)
   MoodBox boxes[6];
   boxes[0].name = "MOOD_MMN"; boxes[0].mood = moodMMN; boxes[0].label = "MMN";
   boxes[0].enabled = Enable_MMN; boxes[0].timeframe = PERIOD_MN1; boxes[0].lastUpdate = lastMNTime;

   boxes[1].name = "MOOD_MW";  boxes[1].mood = moodMW;  boxes[1].label = "MW";
   boxes[1].enabled = Enable_MW; boxes[1].timeframe = PERIOD_W1; boxes[1].lastUpdate = lastW1Time;

   boxes[2].name = "MOOD_MD1"; boxes[2].mood = moodMD1; boxes[2].label = "MD1";
   boxes[2].enabled = Enable_MD1; boxes[2].timeframe = PERIOD_D1; boxes[2].lastUpdate = lastD1Time;

   boxes[3].name = "MOOD_MDC"; boxes[3].mood = moodMDC; boxes[3].label = "MDC";
   boxes[3].enabled = Enable_MDC; boxes[3].timeframe = 0; boxes[3].lastUpdate = lastDCTime;

   boxes[4].name = "MOOD_MH4"; boxes[4].mood = moodMH4; boxes[4].label = "MH4";
   boxes[4].enabled = Enable_MH4; boxes[4].timeframe = PERIOD_H4; boxes[4].lastUpdate = lastH4Time;

   boxes[5].name = "MOOD_MH1"; boxes[5].mood = moodMH1; boxes[5].label = "MH1";
   boxes[5].enabled = Enable_MH1; boxes[5].timeframe = PERIOD_H1; boxes[5].lastUpdate = lastH1Time;

   // Draw boxes
   for(int i = 0; i < 6; i++) {
      string objName = moodPrefix + boxes[i].name;

      if(!boxes[i].enabled) {
         SafeObjectDelete(objName);
         continue;
      }

      color boxColor = GetMoodColor(boxes[i].mood, Color_Buy, Color_Sell, Color_Neutral);

      // Create or update object
      if(ObjectFind(objName) < 0) {
         if(!ObjectCreate(objName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            LogError("UpdateMoodPanel", "Failed to create: " + objName, GetLastError());
            continue;
         }
         ObjectSet(objName, OBJPROP_CORNER, Panel_Corner);
         ObjectSet(objName, OBJPROP_SELECTABLE, false);
         ObjectSet(objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSet(objName, OBJPROP_WIDTH, 1);
         ObjectSet(objName, OBJPROP_BACK, true);
      }

      // Set properties
      ObjectSet(objName, OBJPROP_XDISTANCE, xPos);
      ObjectSet(objName, OBJPROP_YDISTANCE, MoodPanel_Y_Offset);
      ObjectSet(objName, OBJPROP_XSIZE, Box_Size);
      ObjectSet(objName, OBJPROP_YSIZE, Box_Size);
      ObjectSet(objName, OBJPROP_BGCOLOR, boxColor);
      ObjectSet(objName, OBJPROP_COLOR, boxColor);

      // Set detailed tooltip
      string tooltip = CreateDetailedTooltip(boxes[i].label, boxes[i].mood,
                                             boxes[i].lastUpdate, boxes[i].timeframe);
      ObjectSetString(0, objName, OBJPROP_TOOLTIP, tooltip);

      // Use larger gap after MD1 (index 2)
      if(i == 2) {
         xPos += Box_Size + Gap_After_MD1;
      } else {
         xPos += Box_Size + Box_Spacing;
      }
   }

   // Update previous moods
   prevMDC = moodMDC;
   prevMH4 = moodMH4;
   prevMH1 = moodMH1;
   prevMD1 = moodMD1;
   prevMW = moodMW;
   prevMMN = moodMMN;
}

//==================================================================
// INDICATOR LIFECYCLE
//==================================================================

int OnInit() {
   IndicatorShortName("Mood Panel v3.1");

   // Validate inputs
   int validatedXOffset = ValidateInt(MoodPanel_X_Offset, 10, 500, 110);
   int validatedYOffset = ValidateInt(MoodPanel_Y_Offset, 10, 500, 15);
   int validatedBoxSize = ValidateInt(Box_Size, 10, 30, 15);
   int validatedSpacing = ValidateInt(Box_Spacing, 2, 20, 5);
   int validatedGap = ValidateInt(Gap_After_MD1, 5, 30, 15);

   // Apply validated values
   MoodPanel_X_Offset = validatedXOffset;
   MoodPanel_Y_Offset = validatedYOffset;
   Box_Size = validatedBoxSize;
   Box_Spacing = validatedSpacing;
   Gap_After_MD1 = validatedGap;

   // Setup prefixes
   chartPrefix = GetChartPrefix();
   moodPrefix = chartPrefix;

   // Initialize all moods at start
   moodMDC = CalculateMDC();

   if(Enable_MH4) moodMH4 = InitializeMood(PERIOD_H4, 1);
   if(Enable_MH1) moodMH1 = InitializeMood(PERIOD_H1, 1);
   if(Enable_MD1) moodMD1 = InitializeMood(PERIOD_D1, 1);
   if(Enable_MW)  moodMW  = InitializeMood(PERIOD_W1, 1);
   if(Enable_MMN) moodMMN = InitializeMood(PERIOD_MN1, 1);

   prevMDC = moodMDC;
   prevMH4 = moodMH4;
   prevMH1 = moodMH1;
   prevMD1 = moodMD1;
   prevMW = moodMW;
   prevMMN = moodMMN;

   UpdateMoodPanel();

   PrintBBMACHeader("Mood Panel v3.1");
   LogDebug("OnInit", "Initialization complete", Debug_Mode);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   DeleteMoodPanel();
   LogDebug("OnDeinit", "Deinitialization complete", Debug_Mode);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   // Redraw panel on chart change
   if(id == CHARTEVENT_CHART_CHANGE) {
      UpdateMoodPanel();
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

   // Check for new bar on current timeframe (works for all timeframes now)
   datetime currentBar = iTime(NULL, 0, 0);
   if(currentBar == lastBarTime) return rates_total;
   lastBarTime = currentBar;

   // New bar detected - update all moods
   LogDebug("OnCalculate", "New bar detected on " + GetTimeframeString(Period()) + " - updating moods", Debug_Mode);

   // Update MDC (Daily Candle)
   if(Enable_MDC) {
      string newMDC = CalculateMDC();
      if(newMDC != "" && newMDC != moodMDC) {
         LogDebug("MDC", "Changed: " + moodMDC + " -> " + newMDC, Debug_Mode);
         moodMDC = newMDC;
      }
   }

   // Update MH4
   if(Enable_MH4) {
      datetime currentH4 = iTime(NULL, PERIOD_H4, 1);
      if(currentH4 != lastH4Time) {
         MoodData data = GetMoodData(PERIOD_H4, 1);
         if(data.valid) {
            string newMH4 = CalculateMood(data, moodMH4);
            if(newMH4 != moodMH4) {
               LogDebug("MH4", "Changed: " + moodMH4 + " -> " + newMH4, Debug_Mode);
               moodMH4 = newMH4;
            }
         }
         lastH4Time = currentH4;
      }
   }

   // Update MH1
   if(Enable_MH1) {
      datetime currentH1 = iTime(NULL, PERIOD_H1, 1);
      if(currentH1 != lastH1Time) {
         MoodData data = GetMoodData(PERIOD_H1, 1);
         if(data.valid) {
            string newMH1 = CalculateMood(data, moodMH1);
            if(newMH1 != moodMH1) {
               LogDebug("MH1", "Changed: " + moodMH1 + " -> " + newMH1, Debug_Mode);
               moodMH1 = newMH1;
            }
         }
         lastH1Time = currentH1;
      }
   }

   // Update MD1
   if(Enable_MD1) {
      datetime currentD1 = iTime(NULL, PERIOD_D1, 1);
      if(currentD1 != lastD1Time) {
         MoodData data = GetMoodData(PERIOD_D1, 1);
         if(data.valid) {
            string newMD1 = CalculateMood(data, moodMD1);
            if(newMD1 != moodMD1) {
               LogDebug("MD1", "Changed: " + moodMD1 + " -> " + newMD1, Debug_Mode);
               moodMD1 = newMD1;
            }
         }
         lastD1Time = currentD1;
      }
   }

   // Update MW
   if(Enable_MW) {
      datetime currentW1 = iTime(NULL, PERIOD_W1, 1);
      if(currentW1 != lastW1Time) {
         MoodData data = GetMoodData(PERIOD_W1, 1);
         if(data.valid) {
            string newMW = CalculateMood(data, moodMW);
            if(newMW != moodMW) {
               LogDebug("MW", "Changed: " + moodMW + " -> " + newMW, Debug_Mode);
               moodMW = newMW;
            }
         }
         lastW1Time = currentW1;
      }
   }

   // Update MMN
   if(Enable_MMN) {
      datetime currentMN = iTime(NULL, PERIOD_MN1, 1);
      if(currentMN != lastMNTime) {
         MoodData data = GetMoodData(PERIOD_MN1, 1);
         if(data.valid) {
            string newMMN = CalculateMood(data, moodMMN);
            if(newMMN != moodMMN) {
               LogDebug("MMN", "Changed: " + moodMMN + " -> " + newMMN, Debug_Mode);
               moodMMN = newMMN;
            }
         }
         lastMNTime = currentMN;
      }
   }

   // Update panel if any mood changed
   UpdateMoodPanel();

   return rates_total;
}
//+------------------------------------------------------------------+
