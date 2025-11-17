//+------------------------------------------------------------------+
//|                             MoodPanel.mq4                        |
//|                    Hanya Menampilkan Panel Mood                  |
//|               Dipisah dari BBMAC_v2 (Coding Partner)             |
//|                      V3 - Added MMC & MWC                        |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 0

#define INIT_LOOKBACK 50

//--- Input dari BBMAC_v2 yang berhubungan dengan Mood Panel
input bool   Show_Mood_Panel    = true; // Tampilkan/Sembunyikan Panel Mood
input bool   Enable_MDC         = true; // Aktifkan Mood Daily Candle (MDC)
input bool   Enable_MH4         = true; // Aktifkan Mood H4 LWMA (MH4)
input bool   Enable_MH1         = true; // Aktifkan Mood H1 LWMA (MH1)
input bool   Enable_MD1         = true; // Aktifkan Mood Daily LWMA (MD1)
input bool   Enable_MW          = true; // Aktifkan Mood Weekly LWMA (MW)
input bool   Enable_MMN         = true; // Aktifkan Mood Monthly LWMA (MMN)
input int    MoodPanel_X_Offset = 110;  // Jarak Panel dari Sumbu X
input int    MoodPanel_Y_Offset = 15;   // Jarak Panel dari Sumbu Y
input ENUM_BASE_CORNER Panel_Corner = CORNER_RIGHT_UPPER; // Posisi Panel

input color  Color_Buy          = clrDarkGreen;  // Warna Box BUY
input color  Color_Sell         = clrMaroon;    // Warna Box SELL
input color  Color_Neutral      = C'40,40,40';  // Warna Box Neutral

input bool   Debug_Mode         = false; // Aktifkan Debug Mode

//--- Variabel Global
string moodMDC = "", moodMH4 = "", moodMH1 = "";
string moodMD1 = "", moodMW = "", moodMMN = "";
string prevMDC = "", prevMH4 = "", prevMH1 = "";
string prevMD1 = "", prevMW = "", prevMMN = "";
datetime lastH4Time = 0, lastH1Time = 0, lastDCTime = 0, lastD1Time = 0, lastW1Time = 0, lastMNTime = 0;

string chartPrefix;
string moodPrefix;

//--- Struct Data Mood
struct MoodData {
   double lwma5High;
   double lwma5Low;
   double lwma10High;
   double lwma10Low;
   double close;
   bool valid;
};
//+------------------------------------------------------------------+
//| FUNGSI LOGGING                                                    |
//+------------------------------------------------------------------+
void DebugLog(string msg) {
   if(Debug_Mode) Print("[MoodPanel] ", msg);
}
//+------------------------------------------------------------------+
void LogError(string ctx, int code) {
   if(code != 0) Print("[MoodPanel ERROR] ", ctx, " - Code: ", code);
}
//+------------------------------------------------------------------+
//| FUNGSI LOGIKA MOOD                                                |
//+------------------------------------------------------------------+
MoodData GetMoodData(int tf, int bar) {
   MoodData data;
   data.valid = false;
   data.lwma5High = iMA(NULL, tf, 5, 0, MODE_LWMA, PRICE_HIGH, bar);
   if(data.lwma5High <= 0) return data;
   data.lwma5Low = iMA(NULL, tf, 5, 0, MODE_LWMA, PRICE_LOW, bar);
   if(data.lwma5Low <= 0) return data;
   data.lwma10High = iMA(NULL, tf, 10, 0, MODE_LWMA, PRICE_HIGH, bar);
   if(data.lwma10High <= 0) return data;
   data.lwma10Low = iMA(NULL, tf, 10, 0, MODE_LWMA, PRICE_LOW, bar);
   if(data.lwma10Low <= 0) return data;
   
   data.close = iClose(NULL, tf, bar);
   if(data.close <= 0) return data;
   
   int err = GetLastError();
   if(err != 0) {
      LogError("GetMoodData", err);
      return data;
   }
   
   data.valid = true;
   return data;
}
//+------------------------------------------------------------------+
string CalculateLWMAMood(MoodData &data, string currentMood) {
   if(!data.valid) return currentMood;
   if(data.close > data.lwma5High && data.close > data.lwma10High) 
      return "BUY";
   if(data.close < data.lwma5Low && data.close < data.lwma10Low) 
      return "SELL";
   
   return currentMood;
}
//+------------------------------------------------------------------+
string CalculateCloseMood(int period, string name) {
   double cOpen = iOpen(NULL, period, 1);
   double cClose = iClose(NULL, period, 1);
   
   int err = GetLastError();
   if(err != 0) {
      LogError("Calculate" + name, err);
      return "";
   }
   
   if(cOpen == 0 || cClose == 0) {
      DebugLog(name + ": Invalid data (zero values)");
      return "";
   }
   
   if(cClose > cOpen) return "BUY";
   if(cClose < cOpen) return "SELL";
   
   return "";
}
//+------------------------------------------------------------------+
string CalculateMDC() {
   if(!Enable_MDC) return "";
   
   datetime currentDC = iTime(NULL, PERIOD_D1, 1);
   if(currentDC == lastDCTime && moodMDC != "") return moodMDC;
   lastDCTime = currentDC;
   
   return CalculateCloseMood(PERIOD_D1, "MDC");
}
//+------------------------------------------------------------------+
string InitializeMood(int tf, int startBar) {
   int maxCheck = MathMin(INIT_LOOKBACK, iBars(NULL, tf));
   if(maxCheck <= 0) return "";
   for(int i = startBar; i < maxCheck; i++) {
      MoodData data = GetMoodData(tf, i);
      if(!data.valid) continue;
      
      string mood = CalculateLWMAMood(data, "");
      if(mood != "") {
         DebugLog(StringFormat("InitMood TF:%d = %s at bar %d", tf, mood, i));
         return mood;
      }
   }
   
   MoodData data = GetMoodData(tf, startBar);
   if(!data.valid) return "";
   double mid = (data.lwma5High + data.lwma5Low) / 2.0;
   return (data.close > mid) ? "BUY" : "SELL";
}
//+------------------------------------------------------------------+
//| FUNGSI TAMPILAN PANEL                                             |
//+------------------------------------------------------------------+
void DeleteMoodPanel() {
   string names[6] = {"MOOD_MH1", "MOOD_MH4", "MOOD_MDC", "MOOD_MD1", "MOOD_MW", "MOOD_MMN"};
   for(int i = 0; i < 6; i++) {
      string objName = moodPrefix + names[i];
      if(ObjectFind(objName) >= 0) ObjectDelete(objName);
   }
}
//+------------------------------------------------------------------+
void UpdateMoodPanel() {
   if(!Show_Mood_Panel) { 
      DeleteMoodPanel(); 
      return;
   }
   
   bool changed = (moodMDC != prevMDC || moodMH4 != prevMH4 || moodMH1 != prevMH1 ||
                   moodMD1 != prevMD1 || moodMW != prevMW || moodMMN != prevMMN);
   if(!changed && ObjectFind(moodPrefix + "MOOD_MH1") >= 0) return;
   
   int boxSize = 15;
   int boxSpacing = 5;
   int gapAfterMDC = 15; // Gap after MD1 (before MDC)
   int xPos = MoodPanel_X_Offset;
   
   struct MoodBox {
      string name;
      string mood;
      string label;
      bool enabled;
   };
   
   // Layout: MMN MW MD1 | MDC MH4 MH1 (dari kanan ke kiri)
   MoodBox boxes[6];
   boxes[0].name = "MOOD_MMN"; boxes[0].mood = moodMMN; boxes[0].label = "MMN"; boxes[0].enabled = Enable_MMN;
   boxes[1].name = "MOOD_MW";  boxes[1].mood = moodMW;  boxes[1].label = "MW";  boxes[1].enabled = Enable_MW;
   boxes[2].name = "MOOD_MD1"; boxes[2].mood = moodMD1; boxes[2].label = "MD1"; boxes[2].enabled = Enable_MD1;
   boxes[3].name = "MOOD_MDC"; boxes[3].mood = moodMDC; boxes[3].label = "MDC"; boxes[3].enabled = Enable_MDC;
   boxes[4].name = "MOOD_MH4"; boxes[4].mood = moodMH4; boxes[4].label = "MH4"; boxes[4].enabled = Enable_MH4;
   boxes[5].name = "MOOD_MH1"; boxes[5].mood = moodMH1; boxes[5].label = "MH1"; boxes[5].enabled = Enable_MH1;
   
   for(int i = 0; i < 6; i++) {
      string objName = moodPrefix + boxes[i].name;
      if(!boxes[i].enabled) {
         if(ObjectFind(objName) >= 0) ObjectDelete(objName);
         continue;
      }
      
      color boxColor = Color_Neutral;
      if(boxes[i].mood == "BUY") { boxColor = Color_Buy; }
      else if(boxes[i].mood == "SELL") { boxColor = Color_Sell; }
      
      if(ObjectFind(objName) < 0) {
         if(!ObjectCreate(objName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            LogError("CreateMoodBox: " + objName, GetLastError());
            continue;
         }
         ObjectSet(objName, OBJPROP_CORNER, Panel_Corner);
         ObjectSet(objName, OBJPROP_SELECTABLE, false);
         ObjectSet(objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSet(objName, OBJPROP_WIDTH, 1);
         ObjectSet(objName, OBJPROP_BACK, true);
      }
      
      ObjectSet(objName, OBJPROP_XDISTANCE, xPos);
      ObjectSet(objName, OBJPROP_YDISTANCE, MoodPanel_Y_Offset);
      ObjectSet(objName, OBJPROP_XSIZE, boxSize);
      ObjectSet(objName, OBJPROP_YSIZE, boxSize);
      ObjectSet(objName, OBJPROP_BGCOLOR, boxColor);
      ObjectSet(objName, OBJPROP_COLOR, boxColor);
      ObjectSetString(0, objName, OBJPROP_TOOLTIP, boxes[i].label);
      
      // Gunakan gap lebih besar setelah MD1 (index 2)
      if(i == 2) {
         xPos += boxSize + gapAfterMDC;
      } else {
         xPos += boxSize + boxSpacing;
      }
   }
   
   prevMDC = moodMDC;
   prevMH4 = moodMH4;
   prevMH1 = moodMH1;
   prevMD1 = moodMD1;
   prevMW = moodMW;
   prevMMN = moodMMN;
}
//+------------------------------------------------------------------+
//| FUNGSI UTAMA INDIKATOR                                            |
//+------------------------------------------------------------------+
int OnInit() {
   IndicatorShortName("Mood Panel V3");
   
   chartPrefix = StringFormat("%I64d_", ChartID());
   moodPrefix = chartPrefix;

   //--- Inisialisasi semua mood saat start
   moodMDC = CalculateMDC();
   
   if(Enable_MH4) moodMH4 = InitializeMood(PERIOD_H4, 1);
   if(Enable_MH1) moodMH1 = InitializeMood(PERIOD_H1, 1);
   if(Enable_MD1) moodMD1 = InitializeMood(PERIOD_D1, 1);
   if(Enable_MW) moodMW = InitializeMood(PERIOD_W1, 1);
   if(Enable_MMN) moodMMN = InitializeMood(PERIOD_MN1, 1);
   
   prevMDC = moodMDC;
   prevMH4 = moodMH4;
   prevMH1 = moodMH1;
   prevMD1 = moodMD1;
   prevMW = moodMW;
   prevMMN = moodMMN;
   
   UpdateMoodPanel();
   
   DebugLog("Mood Panel V3 Initialization complete");
   
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   //--- Hapus objek dari chart
   DeleteMoodPanel();
   
   DebugLog("Mood Panel V3 Deinitialization complete");
}
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   //--- Redraw panel jika chart berubah
   if(id == CHARTEVENT_CHART_CHANGE) {
      UpdateMoodPanel();
      ChartRedraw();
   }
}
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
                const int &spread[]) {
   
   //--- Guard: Hanya proses saat bar H1 baru terbentuk
   static datetime lastH1Bar = 0;
   datetime currentH1Bar = iTime(NULL, PERIOD_H1, 0);
   
   if(currentH1Bar == lastH1Bar) return rates_total;
   lastH1Bar = currentH1Bar;
   
   //--- Ada bar H1 baru, update semua mood
   DebugLog("New H1 bar detected - updating moods");
   
   if(Enable_MDC) {
      string newMDC = CalculateMDC();
      if(newMDC != "" && newMDC != moodMDC) {
         DebugLog("MDC changed: " + moodMDC + " -> " + newMDC);
         moodMDC = newMDC;
      }
   }
   
   if(Enable_MH4) {
      datetime currentH4 = iTime(NULL, PERIOD_H4, 1);
      if(currentH4 != lastH4Time) {
         MoodData data = GetMoodData(PERIOD_H4, 1);
         if(data.valid) {
            string newMH4 = CalculateLWMAMood(data, moodMH4);
            if(newMH4 != moodMH4) {
               DebugLog("MH4 changed: " + moodMH4 + " -> " + newMH4);
               moodMH4 = newMH4;
            }
         }
         lastH4Time = currentH4;
      }
   }
   
   if(Enable_MH1) {
      datetime currentH1 = iTime(NULL, PERIOD_H1, 1);
      if(currentH1 != lastH1Time) {
         MoodData data = GetMoodData(PERIOD_H1, 1);
         if(data.valid) {
            string newMH1 = CalculateLWMAMood(data, moodMH1);
            if(newMH1 != moodMH1) {
               DebugLog("MH1 changed: " + moodMH1 + " -> " + newMH1);
               moodMH1 = newMH1;
            }
         }
         lastH1Time = currentH1;
      }
   }
   
   if(Enable_MD1) {
      datetime currentD1 = iTime(NULL, PERIOD_D1, 1);
      if(currentD1 != lastD1Time) {
         MoodData data = GetMoodData(PERIOD_D1, 1);
         if(data.valid) {
            string newMD1 = CalculateLWMAMood(data, moodMD1);
            if(newMD1 != moodMD1) {
               DebugLog("MD1 changed: " + moodMD1 + " -> " + newMD1);
               moodMD1 = newMD1;
            }
         }
         lastD1Time = currentD1;
      }
   }
   
   if(Enable_MW) {
      datetime currentW1 = iTime(NULL, PERIOD_W1, 1);
      if(currentW1 != lastW1Time) {
         MoodData data = GetMoodData(PERIOD_W1, 1);
         if(data.valid) {
            string newMW = CalculateLWMAMood(data, moodMW);
            if(newMW != moodMW) {
               DebugLog("MW changed: " + moodMW + " -> " + newMW);
               moodMW = newMW;
            }
         }
         lastW1Time = currentW1;
      }
   }
   
   if(Enable_MMN) {
      datetime currentMN = iTime(NULL, PERIOD_MN1, 1);
      if(currentMN != lastMNTime) {
         MoodData data = GetMoodData(PERIOD_MN1, 1);
         if(data.valid) {
            string newMMN = CalculateLWMAMood(data, moodMMN);
            if(newMMN != moodMMN) {
               DebugLog("MMN changed: " + moodMMN + " -> " + newMMN);
               moodMMN = newMMN;
            }
         }
         lastMNTime = currentMN;
      }
   }
   
   //--- Update panel jika ada perubahan
   UpdateMoodPanel();
   
   return rates_total;
}
//+------------------------------------------------------------------+