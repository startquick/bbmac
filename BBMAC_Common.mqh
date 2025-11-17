//+------------------------------------------------------------------+
//|                                              BBMAC_Common.mqh    |
//|                   Shared Functions for BBMAC Trading System       |
//|                                   Version 2.0 - Optimized         |
//+------------------------------------------------------------------+
#property copyright "BBMAC System"
#property version   "2.00"
#property strict

//==================================================================
// CONSTANTS
//==================================================================
#define BBMAC_VERSION "2.0"
#define INIT_LOOKBACK 50
#define MAX_OBJECTS 500

//==================================================================
// STRUCTS
//==================================================================

// Mood data structure untuk semua timeframe
struct MoodData {
   double lwma5High;
   double lwma5Low;
   double lwma10High;
   double lwma10Low;
   double close;
   bool valid;
   datetime time;
};

//==================================================================
// CHART & OBJECT MANAGEMENT
//==================================================================

// Generate unique chart prefix untuk object naming
string GetChartPrefix() {
   return StringFormat("%I64d_", ChartID());
}

// Safe object deletion dengan error handling
bool SafeObjectDelete(string name) {
   if(ObjectFind(0, name) >= 0) {
      return ObjectDelete(0, name);
   }
   return true;
}

// Cleanup semua objects dengan prefix tertentu
void CleanupObjectsByPrefix(string prefix) {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0) {
         ObjectDelete(0, name);
      }
   }
}

//==================================================================
// STATE MANAGEMENT - GlobalVariables
//==================================================================

// Generate state key yang unik per symbol/period/chart
string GetStateKey(string name) {
   return StringFormat("BBMAC_%s_%s_%d_%I64d",
                       name, Symbol(), Period(), ChartID());
}

// Save boolean state
void SaveState(string key, bool value) {
   GlobalVariableSet(GetStateKey(key), value ? 1.0 : 0.0);
}

// Load boolean state dengan default value
bool LoadState(string key, bool defaultValue = true) {
   string fullKey = GetStateKey(key);
   if(GlobalVariableCheck(fullKey)) {
      return GlobalVariableGet(fullKey) != 0.0;
   }
   return defaultValue;
}

// Save integer state
void SaveStateInt(string key, int value) {
   GlobalVariableSet(GetStateKey(key), (double)value);
}

// Load integer state
int LoadStateInt(string key, int defaultValue = 0) {
   string fullKey = GetStateKey(key);
   if(GlobalVariableCheck(fullKey)) {
      return (int)GlobalVariableGet(fullKey);
   }
   return defaultValue;
}

// Cleanup specific state
void CleanupState(string key) {
   string fullKey = GetStateKey(key);
   if(GlobalVariableCheck(fullKey)) {
      GlobalVariableDel(fullKey);
   }
}

// Cleanup all BBMAC global variables
void CleanupAllGlobalVariables() {
   string prefix = "BBMAC_";
   int total = GlobalVariablesTotal();

   for(int i = total - 1; i >= 0; i--) {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0) {
         GlobalVariableDel(name);
      }
   }
}

//==================================================================
// MOOD CALCULATION - Core Logic
//==================================================================

// Get mood data dari timeframe tertentu
MoodData GetMoodData(int timeframe, int bar) {
   MoodData data;
   data.valid = false;
   data.time = iTime(NULL, timeframe, bar);

   // Calculate LWMA 5 High
   data.lwma5High = iMA(NULL, timeframe, 5, 0, MODE_LWMA, PRICE_HIGH, bar);
   if(data.lwma5High <= 0) return data;

   // Calculate LWMA 5 Low
   data.lwma5Low = iMA(NULL, timeframe, 5, 0, MODE_LWMA, PRICE_LOW, bar);
   if(data.lwma5Low <= 0) return data;

   // Calculate LWMA 10 High
   data.lwma10High = iMA(NULL, timeframe, 10, 0, MODE_LWMA, PRICE_HIGH, bar);
   if(data.lwma10High <= 0) return data;

   // Calculate LWMA 10 Low
   data.lwma10Low = iMA(NULL, timeframe, 10, 0, MODE_LWMA, PRICE_LOW, bar);
   if(data.lwma10Low <= 0) return data;

   // Get close price
   data.close = iClose(NULL, timeframe, bar);
   if(data.close <= 0) return data;

   // Check for errors
   int err = GetLastError();
   if(err != 0) {
      Print("[BBMAC_Common] GetMoodData error: ", err);
      return data;
   }

   data.valid = true;
   return data;
}

// Calculate mood dari MoodData
string CalculateMood(MoodData &data, string currentMood) {
   if(!data.valid) return currentMood;

   // BUY: Close above both LWMA5 High and LWMA10 High
   if(data.close > data.lwma5High && data.close > data.lwma10High) {
      return "BUY";
   }

   // SELL: Close below both LWMA5 Low and LWMA10 Low
   if(data.close < data.lwma5Low && data.close < data.lwma10Low) {
      return "SELL";
   }

   // Maintain current mood if no clear signal
   return currentMood;
}

// Initialize mood dengan scan historical bars
string InitializeMood(int timeframe, int startBar = 1) {
   int maxCheck = MathMin(INIT_LOOKBACK, iBars(NULL, timeframe));
   if(maxCheck <= 0) return "";

   // Scan historical bars untuk find clear mood
   for(int i = startBar; i < maxCheck; i++) {
      MoodData data = GetMoodData(timeframe, i);
      if(!data.valid) continue;

      string mood = CalculateMood(data, "");
      if(mood != "") {
         return mood;
      }
   }

   // Fallback: use midpoint logic
   MoodData data = GetMoodData(timeframe, startBar);
   if(!data.valid) return "";

   double mid = (data.lwma5High + data.lwma5Low) / 2.0;
   return (data.close > mid) ? "BUY" : "SELL";
}

// Calculate mood dari candle close (untuk Daily Candle)
string CalculateCloseMood(int period) {
   double cOpen = iOpen(NULL, period, 1);
   double cClose = iClose(NULL, period, 1);

   int err = GetLastError();
   if(err != 0) {
      Print("[BBMAC_Common] CalculateCloseMood error: ", err);
      return "";
   }

   if(cOpen == 0 || cClose == 0) {
      return "";
   }

   if(cClose > cOpen) return "BUY";
   if(cClose < cOpen) return "SELL";

   return "";
}

//==================================================================
// INPUT VALIDATION
//==================================================================

// Validate integer input dengan min/max bounds
int ValidateInt(int value, int minValue, int maxValue, int defaultValue) {
   if(value < minValue || value > maxValue) {
      Print("[BBMAC_Common] Invalid int value: ", value,
            " (min:", minValue, " max:", maxValue, ") - using default: ", defaultValue);
      return defaultValue;
   }
   return value;
}

// Validate double input dengan min/max bounds
double ValidateDouble(double value, double minValue, double maxValue, double defaultValue) {
   if(value < minValue || value > maxValue) {
      Print("[BBMAC_Common] Invalid double value: ", value,
            " (min:", minValue, " max:", maxValue, ") - using default: ", defaultValue);
      return defaultValue;
   }
   return value;
}

// Validate color input (check if valid color)
color ValidateColor(color value, color defaultValue) {
   // MQL4 color validation - check if it's a valid color value
   if(value == clrNONE && defaultValue != clrNONE) {
      return defaultValue;
   }
   return value;
}

//==================================================================
// ERROR HANDLING & LOGGING
//==================================================================

// Log informational message
void LogInfo(string source, string message) {
   Print("[BBMAC:", source, "] ", message);
}

// Log error dengan error code
void LogError(string source, string context, int errorCode = 0) {
   if(errorCode == 0) errorCode = GetLastError();
   if(errorCode != 0) {
      Print("[BBMAC ERROR:", source, "] ", context, " - Code: ", errorCode);
   }
}

// Log debug message (hanya jika debug mode aktif)
void LogDebug(string source, string message, bool debugMode) {
   if(debugMode) {
      Print("[BBMAC DEBUG:", source, "] ", message);
   }
}

//==================================================================
// GLOBAL COMMUNICATION - Inter-Indicator Communication
//==================================================================

// Set mood untuk timeframe tertentu (dapat dibaca oleh indikator lain)
void SetGlobalMood(string timeframe, string mood) {
   string key = StringFormat("BBMAC_MOOD_%s_%s", Symbol(), timeframe);

   if(mood == "BUY") {
      GlobalVariableSet(key, 1.0);
   } else if(mood == "SELL") {
      GlobalVariableSet(key, -1.0);
   } else {
      GlobalVariableSet(key, 0.0);
   }
}

// Get mood dari timeframe tertentu
string GetGlobalMood(string timeframe) {
   string key = StringFormat("BBMAC_MOOD_%s_%s", Symbol(), timeframe);

   if(!GlobalVariableCheck(key)) return "";

   double val = GlobalVariableGet(key);
   if(val > 0.5) return "BUY";
   if(val < -0.5) return "SELL";

   return "";
}

// Set latest reentry signal
void SetGlobalSignal(datetime signalTime, string signalType) {
   string key = StringFormat("BBMAC_SIGNAL_%s", Symbol());

   double val = 0.0;
   if(signalType == "BUY") val = 1.0;
   else if(signalType == "SELL") val = -1.0;

   GlobalVariableSet(key, val);
   GlobalVariableSet(key + "_TIME", (double)signalTime);
}

// Get latest reentry signal
bool GetGlobalSignal(datetime &signalTime, string &signalType) {
   string key = StringFormat("BBMAC_SIGNAL_%s", Symbol());

   if(!GlobalVariableCheck(key)) return false;

   double val = GlobalVariableGet(key);
   signalTime = (datetime)GlobalVariableGet(key + "_TIME");

   if(val > 0.5) {
      signalType = "BUY";
      return true;
   }

   if(val < -0.5) {
      signalType = "SELL";
      return true;
   }

   return false;
}

//==================================================================
// UI HELPERS
//==================================================================

// Get color based on mood
color GetMoodColor(string mood, color buyColor, color sellColor, color neutralColor) {
   if(mood == "BUY") return buyColor;
   if(mood == "SELL") return sellColor;
   return neutralColor;
}

// Get symbol/character untuk mood
string GetMoodSymbol(string mood) {
   if(mood == "BUY") return "▲";
   if(mood == "SELL") return "▼";
   return "■";
}

// Get timeframe string dari period constant
string GetTimeframeString(int period) {
   switch(period) {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "UNKNOWN";
   }
}

// Get period constant dari timeframe label
int GetPeriodFromLabel(string label) {
   if(label == "MH1") return PERIOD_H1;
   if(label == "MH4") return PERIOD_H4;
   if(label == "MDC" || label == "MD1") return PERIOD_D1;
   if(label == "MW") return PERIOD_W1;
   if(label == "MMN") return PERIOD_MN1;
   return 0;
}

//==================================================================
// VERSION INFO
//==================================================================

// Get BBMAC system version
string GetBBMACVersion() {
   return BBMAC_VERSION;
}

// Print header untuk initialization
void PrintBBMACHeader(string indicatorName) {
   Print("=======================================");
   Print("BBMAC System v", BBMAC_VERSION);
   Print("Indicator: ", indicatorName);
   Print("Symbol: ", Symbol(), " | Period: ", GetTimeframeString(Period()));
   Print("Chart ID: ", ChartID());
   Print("=======================================");
}

//==================================================================
// MEMORY & PERFORMANCE OPTIMIZATION
//==================================================================

// Estimate text width untuk UI layout (approximation)
int EstimateTextWidth(string text, int fontSize) {
   double width = 0.0;
   int len = StringLen(text);

   for(int i = 0; i < len; i++) {
      ushort ch = StringGetCharacter(text, i);

      // Character width estimation
      if(ch >= 'A' && ch <= 'Z')       width += 0.78;
      else if(ch >= 'a' && ch <= 'z')  width += 0.63;
      else if(ch >= '0' && ch <= '9')  width += 0.62;
      else if(ch == ' ')               width += 0.38;
      else if(ch == ':')               width += 0.30;
      else                             width += 0.55;
   }

   return (int)(width * fontSize * 1.30);
}

// Safe array resize dengan boundary check
bool SafeArrayResize(double &array[], int newSize, int maxSize = 10000) {
   if(newSize < 0 || newSize > maxSize) {
      LogError("SafeArrayResize", "Invalid size: " + IntegerToString(newSize));
      return false;
   }

   return (ArrayResize(array, newSize) == newSize);
}

// Get pips value untuk current symbol
double GetPipValue() {
   double point = Point;
   int digits = Digits;

   // For 3/5 digit brokers
   if(digits == 3 || digits == 5) {
      return point * 10;
   }

   return point;
}

//==================================================================
// FILE OPERATIONS (untuk Setup Checklist)
//==================================================================

// Safe file open dengan error handling
int SafeFileOpen(string filename, int mode, string context = "") {
   int handle = FileOpen(filename, mode);

   if(handle == INVALID_HANDLE) {
      int err = GetLastError();
      LogError("FileOpen", context + " - File: " + filename, err);
   }

   return handle;
}

// Safe file write dengan error checking
bool SafeFileWrite(int handle, string data, string context = "") {
   if(handle == INVALID_HANDLE) return false;

   uint written = FileWriteString(handle, data);

   if(written == 0) {
      LogError("FileWrite", context, GetLastError());
      return false;
   }

   return true;
}

//==================================================================
// UTILITY FUNCTIONS
//==================================================================

// Check if current bar is new
bool IsNewBar(datetime &lastBarTime, int timeframe = 0) {
   datetime currentBarTime = iTime(NULL, timeframe, 0);

   if(currentBarTime != lastBarTime) {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

// Get bar shift safely dengan error handling
int SafeBarShift(int timeframe, datetime time, bool exact = false) {
   int shift = iBarShift(NULL, timeframe, time, exact);

   if(shift < 0) {
      LogError("SafeBarShift", "Cannot find bar at " + TimeToString(time));
      return -1;
   }

   return shift;
}

// Format datetime untuk display
string FormatDateTime(datetime time, bool includeSeconds = false) {
   if(includeSeconds) {
      return TimeToString(time, TIME_DATE | TIME_MINUTES | TIME_SECONDS);
   }
   return TimeToString(time, TIME_DATE | TIME_MINUTES);
}

//+------------------------------------------------------------------+
//| END OF BBMAC_Common.mqh                                          |
//+------------------------------------------------------------------+
