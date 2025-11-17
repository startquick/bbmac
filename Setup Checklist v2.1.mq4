//+------------------------------------------------------------------+
//|                                     TradingSetupChecklist v2.1.mq4|
//|  v2.1 - Enhanced with shared library, reset function, and         |
//|         progress tracking                                         |
//|                                                                    |
//|  New Features:                                                     |
//|  - Reset All function (hotkey 'R')                                |
//|  - Progress percentage display                                    |
//|  - Completion sound (optional)                                    |
//|  - Better file naming with chart ID                               |
//|  - Using BBMAC_Common.mqh for shared functions                    |
//+------------------------------------------------------------------+
#property copyright "calmo trader"
#property link      ""
#property version   "2.10"
#property strict
#property indicator_chart_window

//--- Include shared library
#include <BBMAC_Common.mqh>

//==================================================================
// TRADING SETUP Inputs
//==================================================================
input group "==== TRADING SETUP ===="
input string Item1  = "MDC Trend Confirmed";
input string Item2  = "MH4 Aligned with Trend";
input string Item3  = "Reentry Arrow Confirmed";
input string Item4  = "H1 Filter Passed";
input string Item5  = "Multi-TF Alignment OK";
input string Item6  = "Entry Zone Valid";
input string Item7  = "Stop Loss Calculated";
input string Item8  = "Risk 1-2% Max";
input string Item9  = "Take Profit Set";
input string Item10 = "No High Impact News";

//==================================================================
// TRADING MINDSET Inputs
//==================================================================
input group "==== TRADING MINDSET ===="
input string Mindset1  = "I trade my plan only";
input string Mindset2  = "I accept this risk";
input string Mindset3  = "I am patient for setup";
input string Mindset4  = "No revenge trading";
input string Mindset5  = "No FOMO - wait signal";
input string Mindset6  = "I follow my rules";
input string Mindset7  = "Loss is part of game";
input string Mindset8  = "I am disciplined";
input string Mindset9  = "Quality over quantity";
input string Mindset10 = "I trust my system";

//==================================================================
// UI SETTINGS
//==================================================================
input group "==== UI Settings ===="
input int   InputPanelOffsetX  = 10;      // Panel X Offset (10-500)
input int   InputPanelOffsetY  = 50;      // Panel Y Offset (10-500)
input int   InputFontSize      = 8;       // Font Size (6-14)
input int   SectionSpacing     = 15;      // Section Spacing (10-30)

//==================================================================
// SECTION ENABLE/DISABLE
//==================================================================
input group "==== Sections ===="
input bool  EnableTradeSetup   = true;    // Show TRADE SETUP section
input bool  EnableMindSetup    = true;    // Show MIND SETUP section

//==================================================================
// COLORS
//==================================================================
input group "==== Colors ===="
input color TextColor          = clrWhite;
input color ActionColor        = clrLimeGreen;
input color WaitColor          = clrGold;
input color CheckedBoxColor    = clrDarkGreen;
input color UncheckedBoxColor  = clrDimGray;
input color BorderColor        = C'60,60,60';
input color SectionTitleColor  = clrGold;

//==================================================================
// TOGGLE BUTTON
//==================================================================
input group "==== Toggle Button ===="
input int   ToggleOffsetX      = 25;      // Toggle X Offset (10-100)
input int   ToggleOffsetY      = 50;      // Toggle Y Offset (10-200)
input int   ToggleSize         = 15;      // Toggle Size (10-25)

//==================================================================
// ADVANCED FEATURES
//==================================================================
input group "==== Advanced ===="
input bool  Enable_Completion_Sound = true;  // Play Sound on Completion
input string Completion_Sound_File = "ok.wav"; // Completion Sound File
input bool  Show_Progress_Percentage = true;  // Show Progress %
input bool  Debug_Mode = false;               // Enable Debug Logging

//==================================================================
// GLOBALS
//==================================================================
string prefixName        = "TradingChecklist_";
string toggleName        = "TradingChecklist__TOGGLE";

string setupItems[10];
bool   setupStatus[10];

string mindsetItems[10];
bool   mindsetStatus[10];

int    activeSetupItems   = 0;
int    activeMindsetItems = 0;
int    lineHeight    = 0;
int    headerHeight  = 0;

int    rightPad      = 12;
int    checkboxRightPad = 25;

bool   isVisible     = true;
color  ToggleColorON  = clrDarkGreen;
color  ToggleColorOFF = C'60,60,60';

// Working variables (validated from inputs)
int PanelOffsetX;
int PanelOffsetY;
int FontSize;

// Performance optimization
bool needsFullRedraw = false;
bool needsToggleUpdate = false;

// Completion tracking
bool wasComplete = false;

//==================================================================
// STATE MANAGEMENT
//==================================================================

void SaveChecklistState() {
   SaveState("VISIBILITY", isVisible);
}

void LoadChecklistState() {
   // Validate inputs first
   PanelOffsetX = ValidateInt(InputPanelOffsetX, 10, 500, 10);
   PanelOffsetY = ValidateInt(InputPanelOffsetY, 10, 500, 50);
   FontSize = ValidateInt(InputFontSize, 6, 14, 8);

   // Load visibility
   isVisible = LoadState("VISIBILITY", true);
}

//==================================================================
// PROGRESS CALCULATION
//==================================================================

int CalculateProgress() {
   int total = activeSetupItems + activeMindsetItems;
   if(total == 0) return 0;

   int checked = 0;
   for(int i = 0; i < activeSetupItems; i++) {
      if(setupStatus[i]) checked++;
   }
   for(int i = 0; i < activeMindsetItems; i++) {
      if(mindsetStatus[i]) checked++;
   }

   return (checked * 100) / total;
}

void CheckCompletion() {
   bool isComplete = (CalculateProgress() == 100);

   if(isComplete && !wasComplete && Enable_Completion_Sound) {
      PlaySound(Completion_Sound_File);
      LogInfo("Checklist", "All items completed!");
   }

   wasComplete = isComplete;
}

//==================================================================
// RESET FUNCTION
//==================================================================

void ResetAllCheckboxes() {
   for(int i = 0; i < 10; i++) {
      setupStatus[i] = false;
      mindsetStatus[i] = false;
   }

   wasComplete = false;
   SaveChecklistStatus();
   UpdatePanel();

   LogInfo("Checklist", "All checkboxes reset");
}

//==================================================================
// OBJECT MANAGEMENT
//==================================================================

void DeleteObject(string name) {
   SafeObjectDelete(name);
}

void CleanupAllObjects() {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefixName) == 0) {
         ObjectDelete(0, name);
      }
   }
}

void DeleteContentObjects() {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefixName) == 0 && name != toggleName) {
         ObjectDelete(0, name);
      }
   }
}

//==================================================================
// UI DRAWING
//==================================================================

bool UpdateObjectIfNeeded(string name, int objType) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, objType, 0, 0, 0);
      return true;
   }
   return false;
}

void CreateSquareTR(string name, int xFromRight, int yFromTop, int size, color fill, color border) {
   bool isNew = UpdateObjectIfNeeded(name, OBJ_RECTANGLE_LABEL);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelOffsetX + xFromRight);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelOffsetY + yFromTop);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateLabelTR(string name, string text, int fontSize, color textColor,
                   int xFromRight, int yFromTop, bool bold=false) {
   bool isNew = UpdateObjectIfNeeded(name, OBJ_LABEL);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelOffsetX + xFromRight);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelOffsetY + yFromTop);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateOrUpdateToggle() {
   bool isNew = UpdateObjectIfNeeded(toggleName, OBJ_RECTANGLE_LABEL);

   ObjectSetInteger(0, toggleName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, toggleName, OBJPROP_XDISTANCE, ToggleOffsetX);
   ObjectSetInteger(0, toggleName, OBJPROP_YDISTANCE, ToggleOffsetY);
   ObjectSetInteger(0, toggleName, OBJPROP_XSIZE, ToggleSize);
   ObjectSetInteger(0, toggleName, OBJPROP_YSIZE, ToggleSize);

   color fill = isVisible ? ToggleColorON : ToggleColorOFF;
   ObjectSetInteger(0, toggleName, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, toggleName, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, toggleName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, toggleName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, toggleName, OBJPROP_BACK, true);
   ObjectSetInteger(0, toggleName, OBJPROP_HIDDEN, false);

   string tooltip = isVisible ? "Checklist: ON (T)" : "Checklist: OFF (T)";
   ObjectSetString(0, toggleName, OBJPROP_TOOLTIP, tooltip);

   needsToggleUpdate = false;
}

//==================================================================
// PANEL UPDATE
//==================================================================

void UpdatePanel() {
   if(!isVisible) {
      DeleteContentObjects();
      return;
   }

   // Recompute layout
   lineHeight   = MathMax(FontSize * 2 + 4, 26);
   headerHeight = MathMax(FontSize + 18, 28);

   int baselineTweak = (FontSize >= 12 ? 2 : 1);
   int checkBoxSize = MathMin(FontSize + 6, lineHeight - 6);

   int currentY = 0;

   // ========== TRADING SETUP SECTION ==========
   if(EnableTradeSetup && activeSetupItems > 0) {
      // Determine status
      bool allSetupChecked = true;
      for(int i = 0; i < activeSetupItems; i++) {
         if(!setupStatus[i]) {
            allSetupChecked = false;
            break;
         }
      }

      string statusText = allSetupChecked ? "ACTION" : "WAIT";
      color  statusClr  = allSetupChecked ? ActionColor : WaitColor;

      // Status label
      int statusX = rightPad;
      int statusY = currentY + (headerHeight - (FontSize + 2)) / 2 - baselineTweak;
      DeleteObject(prefixName + "Status");
      CreateLabelTR(prefixName + "Status", statusText, FontSize + 2, statusClr, statusX, statusY, true);

      // Title
      int statusW = EstimateTextWidth(statusText, FontSize + 2);
      int gapAfterStatus = MathMax(18, FontSize * 2);
      int titleX = rightPad + statusW + gapAfterStatus;
      int titleY = currentY + (headerHeight - (FontSize + 1)) / 2 - baselineTweak;
      DeleteObject(prefixName + "Title");
      CreateLabelTR(prefixName + "Title", "TRADE SETUP", FontSize + 1, TextColor, titleX, titleY, true);

      // Progress percentage
      if(Show_Progress_Percentage) {
         int progress = CalculateProgress();
         string progressText = IntegerToString(progress) + "%";
         int progressX = titleX + EstimateTextWidth("TRADE SETUP", FontSize + 1) + 15;
         DeleteObject(prefixName + "Progress");
         CreateLabelTR(prefixName + "Progress", progressText, FontSize, statusClr, progressX, titleY, false);
      } else {
         DeleteObject(prefixName + "Progress");
      }

      // Setup items
      for(int i = 0; i < activeSetupItems; i++) {
         int yTop = currentY + headerHeight + i * lineHeight;

         // Checkbox
         string boxName = prefixName + "SetupCheckbox_" + IntegerToString(i);
         DeleteObject(boxName);
         color fill = setupStatus[i] ? CheckedBoxColor : UncheckedBoxColor;
         int boxX = checkboxRightPad;
         int boxY = yTop + (lineHeight - checkBoxSize) / 2 + 2;
         CreateSquareTR(boxName, boxX, boxY, checkBoxSize, fill, BorderColor);

         // Item text
         string itemName = prefixName + "SetupItem_" + IntegerToString(i);
         DeleteObject(itemName);
         color itemClr = setupStatus[i] ? TextColor : C'150,150,150';
         int textRightX = checkboxRightPad + checkBoxSize + 5;
         int textY = yTop + (lineHeight - FontSize) / 2 - baselineTweak;
         CreateLabelTR(itemName, setupItems[i], FontSize, itemClr, textRightX, textY, false);
      }

      currentY += headerHeight + activeSetupItems * lineHeight;
   } else {
      // Cleanup
      DeleteObject(prefixName + "Status");
      DeleteObject(prefixName + "Title");
      DeleteObject(prefixName + "Progress");
      for(int i = 0; i < 10; i++) {
         DeleteObject(prefixName + "SetupCheckbox_" + IntegerToString(i));
         DeleteObject(prefixName + "SetupItem_" + IntegerToString(i));
      }
   }

   // ========== TRADING MINDSET SECTION ==========
   if(EnableMindSetup && activeMindsetItems > 0) {
      // Add spacing
      if(EnableTradeSetup && activeSetupItems > 0) {
         currentY += SectionSpacing;
      }

      // Title
      DeleteObject(prefixName + "MindsetTitle");
      int mindsetTitleY = currentY + (headerHeight - (FontSize + 1)) / 2 - baselineTweak;
      CreateLabelTR(prefixName + "MindsetTitle", "MIND SETUP", FontSize + 1, clrWhite, rightPad, mindsetTitleY, true);

      // Mindset items
      for(int i = 0; i < activeMindsetItems; i++) {
         int yTop = currentY + headerHeight + i * lineHeight;

         // Checkbox
         string boxName = prefixName + "MindsetCheckbox_" + IntegerToString(i);
         DeleteObject(boxName);
         color fill = mindsetStatus[i] ? CheckedBoxColor : UncheckedBoxColor;
         int boxX = checkboxRightPad;
         int boxY = yTop + (lineHeight - checkBoxSize) / 2 + 2;
         CreateSquareTR(boxName, boxX, boxY, checkBoxSize, fill, BorderColor);

         // Item text
         string itemName = prefixName + "MindsetItem_" + IntegerToString(i);
         DeleteObject(itemName);
         color itemClr = mindsetStatus[i] ? TextColor : C'150,150,150';
         int textRightX = checkboxRightPad + checkBoxSize + 5;
         int textY = yTop + (lineHeight - FontSize) / 2 - baselineTweak;
         CreateLabelTR(itemName, mindsetItems[i], FontSize, itemClr, textRightX, textY, false);
      }
   } else {
      // Cleanup
      DeleteObject(prefixName + "MindsetTitle");
      for(int i = 0; i < 10; i++) {
         DeleteObject(prefixName + "MindsetCheckbox_" + IntegerToString(i));
         DeleteObject(prefixName + "MindsetItem_" + IntegerToString(i));
      }
   }

   CreateOrUpdateToggle();

   if(needsFullRedraw) {
      ChartRedraw();
      needsFullRedraw = false;
   }
}

//==================================================================
// FILE OPERATIONS
//==================================================================

bool SaveChecklistStatus() {
   string file = StringFormat("TradingChecklist_%s_%I64d.txt", Symbol(), ChartID());
   int handle = SafeFileOpen(file, FILE_WRITE | FILE_TXT, "SaveChecklistStatus");

   if(handle == INVALID_HANDLE) return false;

   string data = "";

   // Save SETUP status
   for(int i = 0; i < 10; i++) {
      data += (setupStatus[i] ? "1" : "0");
      if(i < 9) data += ",";
   }
   data += "\n";

   // Save MINDSET status
   for(int i = 0; i < 10; i++) {
      data += (mindsetStatus[i] ? "1" : "0");
      if(i < 9) data += ",";
   }

   bool result = SafeFileWrite(handle, data, "SaveChecklistStatus");
   FileClose(handle);

   return result;
}

bool LoadChecklistStatus() {
   // Initialize to false
   for(int i = 0; i < 10; i++) {
      setupStatus[i] = false;
      mindsetStatus[i] = false;
   }

   string file = StringFormat("TradingChecklist_%s_%I64d.txt", Symbol(), ChartID());

   // Check if file exists
   if(!FileIsExist(file)) {
      LogInfo("Checklist", "No saved checklist found. Starting fresh.");
      return true;
   }

   int handle = SafeFileOpen(file, FILE_READ | FILE_TXT, "LoadChecklistStatus");
   if(handle == INVALID_HANDLE) return false;

   // Read SETUP line
   if(!FileIsEnding(handle)) {
      string line1 = FileReadString(handle);
      if(StringLen(line1) > 0) {
         string parts1[];
         int n1 = StringSplit(line1, ',', parts1);
         for(int i = 0; i < n1 && i < 10; i++)
            setupStatus[i] = (StringToInteger(parts1[i]) == 1);
      }
   }

   // Read MINDSET line
   if(!FileIsEnding(handle)) {
      string line2 = FileReadString(handle);
      if(StringLen(line2) > 0) {
         string parts2[];
         int n2 = StringSplit(line2, ',', parts2);
         for(int i = 0; i < n2 && i < 10; i++)
            mindsetStatus[i] = (StringToInteger(parts2[i]) == 1);
      }
   }

   FileClose(handle);
   return true;
}

//==================================================================
// VISIBILITY TOGGLE
//==================================================================

void ToggleVisibility() {
   isVisible = !isVisible;
   SaveChecklistState();
   needsToggleUpdate = true;
   CreateOrUpdateToggle();

   if(isVisible) {
      needsFullRedraw = true;
      UpdatePanel();
   } else {
      DeleteContentObjects();
      ChartRedraw();
   }
}

//==================================================================
// INDICATOR LIFECYCLE
//==================================================================

int OnInit() {
   IndicatorShortName("Trading Checklist v2.1 (T=Toggle | R=Reset)");

   // Load and validate state
   LoadChecklistState();

   // Load items
   setupItems[0]=Item1; setupItems[1]=Item2; setupItems[2]=Item3; setupItems[3]=Item4;
   setupItems[4]=Item5; setupItems[5]=Item6; setupItems[6]=Item7; setupItems[7]=Item8;
   setupItems[8]=Item9; setupItems[9]=Item10;

   mindsetItems[0]=Mindset1; mindsetItems[1]=Mindset2; mindsetItems[2]=Mindset3; mindsetItems[3]=Mindset4;
   mindsetItems[4]=Mindset5; mindsetItems[5]=Mindset6; mindsetItems[6]=Mindset7; mindsetItems[7]=Mindset8;
   mindsetItems[8]=Mindset9; mindsetItems[9]=Mindset10;

   // Count active items
   activeSetupItems = 0;
   if(EnableTradeSetup) {
      for(int i = 0; i < 10; i++) {
         if(setupItems[i] == "") break;
         activeSetupItems++;
      }
   }

   activeMindsetItems = 0;
   if(EnableMindSetup) {
      for(int i = 0; i < 10; i++) {
         if(mindsetItems[i] == "") break;
         activeMindsetItems++;
      }
   }

   // Dynamic heights
   lineHeight   = MathMax(FontSize * 2 + 4, 26);
   headerHeight = MathMax(FontSize + 18, 28);

   // Load saved status
   if(!LoadChecklistStatus()) {
      LogInfo("Checklist", "Warning: Could not load checklist status. Starting empty.");
   }

   CreateOrUpdateToggle();

   if(isVisible) {
      needsFullRedraw = true;
      UpdatePanel();
   } else {
      DeleteContentObjects();
   }

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   PrintBBMACHeader("Setup Checklist v2.1");
   LogDebug("OnInit", "Initialization complete", Debug_Mode);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   SaveChecklistState();

   if(!SaveChecklistStatus()) {
      LogInfo("Checklist", "Warning: Could not save checklist status on exit.");
   }

   CleanupAllObjects();
   ChartRedraw();

   LogDebug("OnDeinit", "Deinitialization complete", Debug_Mode);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[]) {
   return rates_total;
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   // Toggle button click
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == toggleName) {
      ToggleVisibility();
      return;
   }

   // Hotkey 'T' (84) - Toggle visibility
   if(id == CHARTEVENT_KEYDOWN && lparam == 84) {
      ToggleVisibility();
      return;
   }

   // Hotkey 'R' (82) - Reset all
   if(id == CHARTEVENT_KEYDOWN && lparam == 82) {
      if(MessageBox("Reset all checkboxes?", "Confirm Reset", MB_YESNO) == IDYES) {
         ResetAllCheckboxes();
      }
      return;
   }

   // Checkbox clicks
   if(id == CHARTEVENT_OBJECT_CLICK && isVisible) {
      // SETUP Checkbox
      if(EnableTradeSetup) {
         for(int i = 0; i < activeSetupItems; i++) {
            string checkboxName = prefixName + "SetupCheckbox_" + IntegerToString(i);
            if(sparam == checkboxName) {
               setupStatus[i] = !setupStatus[i];
               UpdatePanel();
               SaveChecklistStatus();
               CheckCompletion();
               return;
            }
         }
      }

      // MINDSET Checkbox
      if(EnableMindSetup) {
         for(int i = 0; i < activeMindsetItems; i++) {
            string checkboxName = prefixName + "MindsetCheckbox_" + IntegerToString(i);
            if(sparam == checkboxName) {
               mindsetStatus[i] = !mindsetStatus[i];
               UpdatePanel();
               SaveChecklistStatus();
               CheckCompletion();
               return;
            }
         }
      }
   }

   // Chart change
   if(id == CHARTEVENT_CHART_CHANGE) {
      needsToggleUpdate = true;
      needsFullRedraw = true;
      CreateOrUpdateToggle();
      if(isVisible) UpdatePanel();
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
