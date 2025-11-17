//+------------------------------------------------------------------+
//|                                        TradingSetupChecklist.mq4 |
//|  v2.0 - Technical Optimizations: Better performance, state       |
//|         management, error handling, and memory optimization      |
//+------------------------------------------------------------------+
#property copyright "calmo trader"
#property link      ""
#property version   "2.00"
#property strict
#property indicator_chart_window

// =================== TRADING SETUP Inputs ==============================
input string Item1  = "MDC Direction Confirmed";
input string Item2  = "MH4 Aligned with MDC";
input string Item3  = "Reentry Signal Present";
input string Item4  = "MH1 Aligned (All Green)";
input string Item5  = "Entry Zone Identified";
input string Item6  = "Stop Loss Calculated";
input string Item7  = "Risk 5-10% Max";
input string Item8  = "Take Profit Planned";
input string Item9  = "";
input string Item10 = "";

// =================== TRADING MINDSET Inputs ============================
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

// Panel position (top-right corner, transparent; no background box)
input int   InputPanelOffsetX  = 10;   // pixels from RIGHT
input int   InputPanelOffsetY  = 30;   // pixels from TOP
input int   InputFontSize      = 8;    // UI scales with this
input int   SectionSpacing     = 15;   // spacing between SETUP and MINDSET sections

// Section Enable/Disable
input bool  EnableTradeSetup   = true;  // Show TRADE SETUP section
input bool  EnableMindSetup    = true;  // Show MIND SETUP section

// Working variables (can be modified at runtime)
int PanelOffsetX;
int PanelOffsetY;
int FontSize;

// Colors
input color TextColor          = clrWhite;
input color ActionColor        = clrLimeGreen;
input color WaitColor          = clrGold;
input color CheckedBoxColor    = clrDarkGreen;
input color UncheckedBoxColor  = clrDimGray;
input color BorderColor        = C'60,60,60';
input color SectionTitleColor  = clrGold;

// Toggle (bottom-right corner, BBMA-style)
input int   ToggleOffsetX      = 25;   // pixels from RIGHT
input int   ToggleOffsetY      = 25;   // pixels from BOTTOM
input int   ToggleSize         = 15;   // 15 px square

// ======================= Globals ==================================
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

// State persistence keys (GlobalVariables)
string GV_VISIBILITY;
// Note: FontSize and Offsets are NOT persisted
// They always use input parameters for easy repositioning

// Performance optimization: track what needs updating
bool needsFullRedraw = false;
bool needsToggleUpdate = false;

// Error handling
int lastFileError = 0;
string lastErrorMessage = "";

// ======================= State Management ==================================
// Build unique keys for GlobalVariables (per symbol)
void InitializeGlobalVariableKeys()
{
   string symbolKey = Symbol();
   GV_VISIBILITY = prefixName + "VIS_" + symbolKey;
   // GV_FONTSIZE, GV_OFFSET_X, GV_OFFSET_Y not needed anymore
   // Position and size always use input parameters
}

// Save all persistent state
void SaveState()
{
   // Only save visibility state
   // Offsets and FontSize always come from input parameters
   GlobalVariableSet(GV_VISIBILITY, isVisible ? 1.0 : 0.0);
}

// Load all persistent state
void LoadState()
{
   // Initialize from inputs first
   PanelOffsetX = InputPanelOffsetX;
   PanelOffsetY = InputPanelOffsetY;
   FontSize = InputFontSize;
   
   // Load visibility
   if(GlobalVariableCheck(GV_VISIBILITY))
      isVisible = (GlobalVariableGet(GV_VISIBILITY) >= 0.5);
   else
   {
      isVisible = true;
      GlobalVariableSet(GV_VISIBILITY, 1.0);
   }
   
   // NOTE: Offsets and FontSize are NOT restored from GlobalVariables
   // They always use the current input parameters
   // This allows users to reposition the panel by changing inputs
}

// ======================= Error Handling ==================================
void LogError(string context, int errorCode)
{
   lastFileError = errorCode;
   lastErrorMessage = context + " - Error: " + IntegerToString(errorCode);
   Print(lastErrorMessage);
}

bool ValidateFileOperation(int handle, string operation)
{
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      LogError(operation, err);
      return false;
   }
   return true;
}

// ======================= Memory Management ==================================
void DeleteObject(string name)
{
   if(ObjectFind(0, name) >= 0) 
   {
      ObjectDelete(0, name);
   }
}

void CleanupAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefixName) == 0)
         ObjectDelete(0, name);
   }
}

void DeleteContentObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefixName) == 0 && name != toggleName)
         ObjectDelete(0, name);
   }
}

// ======================= Optimized Drawing ==================================
// Only update if object doesn't exist or properties changed
bool UpdateObjectIfNeeded(string name, int objType)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, objType, 0, 0, 0);
      return true; // New object created
   }
   return false; // Object already exists
}

void CreateSquareTR(string name, int xFromRight, int yFromTop, int size, color fill, color border)
{
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
                   int xFromRight, int yFromTop, bool bold=false)
{
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

void CreateOrUpdateToggle()
{
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

int EstimateTextWidth(string s, int fs)
{
   double w = 0.0;
   int len = StringLen(s);
   
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch >= 'A' && ch <= 'Z')       w += 0.78;
      else if(ch >= 'a' && ch <= 'z')  w += 0.63;
      else if(ch >= '0' && ch <= '9')  w += 0.62;
      else if(ch == ' ')               w += 0.38;
      else                             w += 0.55;
   }
   
   return (int)(w * fs * 1.30);
}

// ===================== Core =======================================
int OnInit()
{
   IndicatorShortName("Trading Checklist v2.0 (Optimized | Toggle: T)");
   
   // Initialize state management
   InitializeGlobalVariableKeys();
   LoadState();

   // Load SETUP items
   setupItems[0]=Item1; setupItems[1]=Item2; setupItems[2]=Item3; setupItems[3]=Item4;
   setupItems[4]=Item5; setupItems[5]=Item6; setupItems[6]=Item7; setupItems[7]=Item8;
   setupItems[8]=Item9; setupItems[9]=Item10;

   // Load MINDSET items
   mindsetItems[0]=Mindset1; mindsetItems[1]=Mindset2; mindsetItems[2]=Mindset3; mindsetItems[3]=Mindset4;
   mindsetItems[4]=Mindset5; mindsetItems[5]=Mindset6; mindsetItems[6]=Mindset7; mindsetItems[7]=Mindset8;
   mindsetItems[8]=Mindset9; mindsetItems[9]=Mindset10;

   // Count active items
   activeSetupItems = 0;
   if(EnableTradeSetup)
   {
      for(int i = 0; i < 10; i++) 
      { 
         if(setupItems[i] == "") break; 
         activeSetupItems++; 
      }
   }
   
   activeMindsetItems = 0;
   if(EnableMindSetup)
   {
      for(int i = 0; i < 10; i++) 
      { 
         if(mindsetItems[i] == "") break; 
         activeMindsetItems++; 
      }
   }

   // Dynamic heights
   lineHeight   = MathMax(FontSize * 2 + 4, 26);
   headerHeight = MathMax(FontSize + 18, 28);

   // Load saved checkbox states with error handling
   if(!LoadChecklistStatus())
      Print("Warning: Could not load checklist status. Starting with empty checklist.");

   CreateOrUpdateToggle();

   if(isVisible) 
   {
      needsFullRedraw = true;
      UpdatePanel();
   }
   else 
   {
      DeleteContentObjects();
   }
   
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   SaveState();
   
   if(!SaveChecklistStatus())
      Print("Warning: Could not save checklist status on exit.");

   CleanupAllObjects();
   ChartRedraw();
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{ 
   return(rates_total); 
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Mouse click on toggle button
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == toggleName)
   {
      ToggleVisibility();
      return;
   }

   // Hotkey 'T' toggles checklist visibility
   if(id == CHARTEVENT_KEYDOWN && lparam == 84)
   {
      ToggleVisibility();
      return;
   }

   // Checkbox clicks (only when visible)
   if(id == CHARTEVENT_OBJECT_CLICK && isVisible)
   {
      // SETUP Checkbox clicked
      if(EnableTradeSetup)
      {
         for(int i = 0; i < activeSetupItems; i++)
         {
            string checkboxName = prefixName + "SetupCheckbox_" + IntegerToString(i);
            if(sparam == checkboxName)
            {
               setupStatus[i] = !setupStatus[i];
               UpdatePanel(); // Optimized: only updates changed elements
               SaveChecklistStatus();
               return;
            }
         }
      }
      
      // MINDSET Checkbox clicked
      if(EnableMindSetup)
      {
         for(int i = 0; i < activeMindsetItems; i++)
         {
            string checkboxName = prefixName + "MindsetCheckbox_" + IntegerToString(i);
            if(sparam == checkboxName)
            {
               mindsetStatus[i] = !mindsetStatus[i];
               UpdatePanel();
               SaveChecklistStatus();
               return;
            }
         }
      }
   }

   // Reposition on chart changes
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      needsToggleUpdate = true;
      needsFullRedraw = true;
      CreateOrUpdateToggle();
      if(isVisible) UpdatePanel();
      ChartRedraw();
   }
}

void ToggleVisibility()
{
   isVisible = !isVisible;
   SaveState();
   needsToggleUpdate = true;
   CreateOrUpdateToggle();

   if(isVisible) 
   {
      needsFullRedraw = true;
      UpdatePanel();
   }
   else 
   {
      DeleteContentObjects();
      ChartRedraw(); // Single redraw after deletion
   }
}

// -------------------- UI (Optimized Rendering) ----------
void UpdatePanel()
{
   if(!isVisible) 
   { 
      DeleteContentObjects(); 
      return; 
   }

   // Recompute layout
   lineHeight   = MathMax(FontSize * 2 + 4, 26);
   headerHeight = MathMax(FontSize + 18, 28);

   int baselineTweak = (FontSize >= 12 ? 2 : 1);
   int checkBoxSize = MathMin(FontSize + 6, lineHeight - 6);
   
   int currentY = 0; // Track vertical position

   // ========== TRADING SETUP SECTION ==========
   if(EnableTradeSetup && activeSetupItems > 0)
   {
      // Determine SETUP status
      bool allSetupChecked = true;
      for(int i = 0; i < activeSetupItems; i++) 
      {
         if(!setupStatus[i]) 
         { 
            allSetupChecked = false; 
            break; 
         }
      }
      
      string statusText = allSetupChecked ? "ACTION" : "WAIT";
      color  statusClr  = allSetupChecked ? ActionColor : WaitColor;

      int statusX = rightPad;
      int statusY = currentY + (headerHeight - (FontSize + 2)) / 2 - baselineTweak;
      DeleteObject(prefixName + "Status");
      CreateLabelTR(prefixName + "Status", statusText, FontSize + 2, statusClr, statusX, statusY, true);

      int statusW = EstimateTextWidth(statusText, FontSize + 2);
      int gapAfterStatus = MathMax(18, FontSize * 2);
      int titleX = rightPad + statusW + gapAfterStatus;
      int titleY = currentY + (headerHeight - (FontSize + 1)) / 2 - baselineTweak;
      DeleteObject(prefixName + "Title");
      CreateLabelTR(prefixName + "Title", "TRADE SETUP", FontSize + 1, TextColor, titleX, titleY, true);

      // SETUP Items
      for(int i = 0; i < activeSetupItems; i++)
      {
         int yTop = currentY + headerHeight + i * lineHeight;

         string boxName = prefixName + "SetupCheckbox_" + IntegerToString(i);
         DeleteObject(boxName);
         color fill = setupStatus[i] ? CheckedBoxColor : UncheckedBoxColor;
         int boxX = checkboxRightPad;
         int boxY = yTop + (lineHeight - checkBoxSize) / 2 + 2;
         CreateSquareTR(boxName, boxX, boxY, checkBoxSize, fill, BorderColor);

         string itemName = prefixName + "SetupItem_" + IntegerToString(i);
         DeleteObject(itemName);
         color itemClr = setupStatus[i] ? TextColor : C'150,150,150';
         int textRightX = checkboxRightPad + checkBoxSize + 5;
         int textY = yTop + (lineHeight - FontSize) / 2 - baselineTweak;
         CreateLabelTR(itemName, setupItems[i], FontSize, itemClr, textRightX, textY, false);
      }
      
      currentY += headerHeight + activeSetupItems * lineHeight;
   }
   else
   {
      // Clean up TRADE SETUP objects if disabled
      DeleteObject(prefixName + "Status");
      DeleteObject(prefixName + "Title");
      for(int i = 0; i < 10; i++)
      {
         DeleteObject(prefixName + "SetupCheckbox_" + IntegerToString(i));
         DeleteObject(prefixName + "SetupItem_" + IntegerToString(i));
      }
   }

   // ========== TRADING MINDSET SECTION ==========
   if(EnableMindSetup && activeMindsetItems > 0)
   {
      // Add spacing if TRADE SETUP is also visible
      if(EnableTradeSetup && activeSetupItems > 0)
         currentY += SectionSpacing;
      
      DeleteObject(prefixName + "MindsetTitle");
      int mindsetTitleY = currentY + (headerHeight - (FontSize + 1)) / 2 - baselineTweak;
      CreateLabelTR(prefixName + "MindsetTitle", "MIND SETUP", FontSize + 1, clrWhite, rightPad, mindsetTitleY, true);

      for(int i = 0; i < activeMindsetItems; i++)
      {
         int yTop = currentY + headerHeight + i * lineHeight;

         string boxName = prefixName + "MindsetCheckbox_" + IntegerToString(i);
         DeleteObject(boxName);
         color fill = mindsetStatus[i] ? CheckedBoxColor : UncheckedBoxColor;
         int boxX = checkboxRightPad;
         int boxY = yTop + (lineHeight - checkBoxSize) / 2 + 2;
         CreateSquareTR(boxName, boxX, boxY, checkBoxSize, fill, BorderColor);

         string itemName = prefixName + "MindsetItem_" + IntegerToString(i);
         DeleteObject(itemName);
         color itemClr = mindsetStatus[i] ? TextColor : C'150,150,150';
         int textRightX = checkboxRightPad + checkBoxSize + 5;
         int textY = yTop + (lineHeight - FontSize) / 2 - baselineTweak;
         CreateLabelTR(itemName, mindsetItems[i], FontSize, itemClr, textRightX, textY, false);
      }
   }
   else
   {
      // Clean up MIND SETUP objects if disabled
      DeleteObject(prefixName + "MindsetTitle");
      for(int i = 0; i < 10; i++)
      {
         DeleteObject(prefixName + "MindsetCheckbox_" + IntegerToString(i));
         DeleteObject(prefixName + "MindsetItem_" + IntegerToString(i));
      }
   }

   CreateOrUpdateToggle();
   
   // Single redraw after all updates
   if(needsFullRedraw)
   {
      ChartRedraw();
      needsFullRedraw = false;
   }
}

// -------------------- Persistent Storage (Enhanced Error Handling) ----------
bool SaveChecklistStatus()
{
   string file = "TradingChecklist_" + Symbol() + ".txt";
   int handle = FileOpen(file, FILE_WRITE | FILE_TXT);
   
   if(!ValidateFileOperation(handle, "SaveChecklistStatus - FileOpen"))
      return false;

   string data = "";
   
   // Save SETUP status
   for(int i = 0; i < 10; i++) 
   { 
      data += (setupStatus[i] ? "1" : "0"); 
      if(i < 9) data += ","; 
   }
   data += "\n";
   
   // Save MINDSET status
   for(int i = 0; i < 10; i++) 
   { 
      data += (mindsetStatus[i] ? "1" : "0"); 
      if(i < 9) data += ","; 
   }
   
   uint written = FileWriteString(handle, data);
   FileClose(handle);
   
   if(written == 0)
   {
      LogError("SaveChecklistStatus - FileWriteString returned 0", GetLastError());
      return false;
   }
   
   return true;
}

bool LoadChecklistStatus()
{
   // Initialize to false
   for(int i = 0; i < 10; i++) 
   { 
      setupStatus[i] = false; 
      mindsetStatus[i] = false; 
   }

   string file = "TradingChecklist_" + Symbol() + ".txt";
   
   // Check if file exists
   if(!FileIsExist(file))
   {
      Print("Info: No saved checklist found. Starting fresh.");
      return true; // Not an error, just no saved data
   }
   
   int handle = FileOpen(file, FILE_READ | FILE_TXT);
   
   if(!ValidateFileOperation(handle, "LoadChecklistStatus - FileOpen"))
      return false;

   // Read SETUP line
   if(!FileIsEnding(handle))
   {
      string line1 = FileReadString(handle);
      if(StringLen(line1) > 0)
      {
         string parts1[];
         int n1 = StringSplit(line1, ',', parts1);
         for(int i = 0; i < n1 && i < 10; i++) 
            setupStatus[i] = (StringToInteger(parts1[i]) == 1);
      }
   }
   
   // Read MINDSET line
   if(!FileIsEnding(handle))
   {
      string line2 = FileReadString(handle);
      if(StringLen(line2) > 0)
      {
         string parts2[];
         int n2 = StringSplit(line2, ',', parts2);
         for(int i = 0; i < n2 && i < 10; i++) 
            mindsetStatus[i] = (StringToInteger(parts2[i]) == 1);
      }
   }
   
   FileClose(handle);
   return true;
}
//+------------------------------------------------------------------+