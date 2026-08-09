//+------------------------------------------------------------------+
//|                   Panchjanya  DwarkaDhish                      |
//|      🌙☾~🌸~☽🌙                           DwarkaDhish           |
//+------------------------------------------------------------------+
#property copyright "R1 Shunya Trading System"
#property version "1.00"
#property strict
//+------------------------------------------------------------------+
input group "=== Core ==="
input ulong Magic = 1;
input bool ResetState = false;
input bool TestMode = false;

//+------------------------------------------------------------------+
input group "=== ZigZag ==="
input double ZZ_Dev = 0.1;
input int ZZ_Depth = 1;
input int ZZ_Lookback = 200;

//+------------------------------------------------------------------+
input group "=== Trade ==="
input double TP_Pips = 20.0;
input double SL_Pips = 15.0;
input double MaxSpread = 30.0;

//+------------------------------------------------------------------+
input group "=== Safe Net (The Runner Logic) ==="
input double BE_Trigger = 11.0; // Move SL/TP at 11 pips
input double BE_Profit = 5.0; // Lock in 5 pips profit
input double Trail_Trigger = 20.0;// Move SL/TP again at 20 pips
input double Trail_Dist = 10.0; // Trail by 10 pips

//+------------------------------------------------------------------+
input group "=== Momentum ==="
input bool EnableChain = true;
input int Mom_Candles = 5;

//+------------------------------------------------------------------+
double pip_size;
ENUM_ORDER_TYPE_FILLING order_fill = ORDER_FILLING_IOC;
double v_balance = 20.0; int c_level = 1; double l_profit = 0.0; bool in_recovery = false;

bool in_stepdown = false;
int stepdown_level = 0;
int wins_needed = 0;

struct Pivot { datetime time; double price; int type; };
Pivot pivots[];
int pivot_count = 0;
datetime last_pivot_time = 0;

datetime last_bar = 0; 
double safe_phase = 0; 
bool mom_active = false; 
int chain_count = 0; 
bool skip_next = false;

//+------------------------------------------------------------------+
double lots[31] = {0, 0.03,0.04,0.05,0.07,0.09,0.11,0.14,0.19,0.24,0.32,0.41,0.54,0.70,0.91,1.18,1.54,2.00,2.60,3.38,4.39,5.71,7.42,9.65,12.54,16.30,21.19,27.55,35.82,46.56,60.53};
double goals[31] = {0, 6,7.8,10.14,13.18,17.14,22.28,28.96,37.65,48.94,63.63,82.72,107.53,139.79,181.73,236.25,307.12,399.26,519.04,674.75,877.18,1140.33,1482.43,1927.16,2505.31,3256.90,4233.97,5504.16,7155.41,9302.03,12092.64};
double levels_total[31] = {0, 20, 26, 33.8, 43.94, 57.12, 74.26, 96.54, 125.5, 163.15, 212.09, 275.72, 358.44, 465.97, 605.76, 787.49, 1023.74, 1330.86, 1730.12, 2249.16, 2923.91, 3801.09, 4941.42, 6423.85, 8351.01, 10856.32, 14113.22, 18347.19, 23851.35, 31006.76, 40308.79};
int log_h = -1;
int log_trades = -1;
int log_signals = -1;
int log_state = -1;

bool SendOrder(MqlTradeRequest &req, MqlTradeResult &res) {
 if(OrderSend(req, res)) {
 if(res.retcode == TRADE_RETCODE_DONE) return true;
 if(res.retcode == TRADE_RETCODE_INVALID_FILL) {
 if(req.type_filling == ORDER_FILLING_FOK) req.type_filling = ORDER_FILLING_IOC;
 else if(req.type_filling == ORDER_FILLING_IOC) req.type_filling = ORDER_FILLING_RETURN;
 else req.type_filling = ORDER_FILLING_FOK;
 if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE) return true;
 }
 }
 return false;
}


//+------------------------------------------------------------------+
int OnInit() {
 pip_size = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
 long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
 if((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) order_fill = ORDER_FILLING_FOK;
 else if((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) order_fill = ORDER_FILLING_IOC;
 else order_fill = ORDER_FILLING_RETURN;

 if(ResetState) {
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_VB");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_Lvl");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_LP");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_SD");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_SD_Lvl");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_SD_Wins");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_LPT");
   GlobalVariableDel("R6_" + IntegerToString(Magic) + "_LB");
 v_balance = 20.0; c_level = 1; l_profit = 0.0; in_recovery = false;
 in_stepdown = false; stepdown_level = 0; wins_needed = 0;
 } else { LoadState(); }

 ArrayResize(pivots, 0);
 log_h = FileOpen("5janyaLog.csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
 if(log_h != INVALID_HANDLE && FileSize(log_h) == 0) FileWrite(log_h, "Time","Dir","Entry","Exit","Pips","USD","Level","Reason");
 log_trades = FileOpen("5janyatrade.csv", FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
 if(log_trades != INVALID_HANDLE && FileSize(log_trades) == 0) FileWrite(log_trades, "Time","Dir","Entry","Exit","Pips","USD","Level","Reason");
 log_signals = FileOpen("5janyasignals.csv", FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
 if(log_signals != INVALID_HANDLE && FileSize(log_signals) == 0) FileWrite(log_signals, "Time","Symbol","SignalType","PivotType","PivotPrice","Status","Reason");
 log_state = FileOpen("5janyastate.csv", FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
 if(log_state != INVALID_HANDLE && FileSize(log_state) == 0) FileWrite(log_state, "Time","Level","v_balance","l_profit","in_stepdown","stepdown_level","wins_needed");
 return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
    SaveState(); 
    if(log_h != INVALID_HANDLE) FileClose(log_h); 
    if(log_trades != INVALID_HANDLE) FileClose(log_trades); 
    if(log_signals != INVALID_HANDLE) FileClose(log_signals); 
    if(log_state != INVALID_HANDLE) FileClose(log_state); 
    ObjectsDeleteAll(0, "R6_"); }

//+------------------------------------------------------------------+
void OnTick() {
    datetime cur_bar = iTime(_Symbol, PERIOD_M15, 0);
    bool new_bar = (cur_bar != last_bar);
    if(new_bar) { last_bar = cur_bar; UpdatePivots(); 
    }

    ulong ticket = GetTicket();
    if(ticket > 0) ManageTrade(ticket);
    else if(new_bar) CheckSignal();

   Comment("Panchjanya �| Lvl: ", c_level, " | Lot: ", GetLot(), 
            " | Virtual: $", DoubleToString(v_balance, 2),
            " | Real: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)); 
}

//+------------------------------------------------------------------+
void UpdatePivots() {
    int lb = MathMin(300, Bars(_Symbol, PERIOD_M15) - ZZ_Depth - 1);
    for(int i = lb; i >= ZZ_Depth; i--) {
        bool is_high = true, is_low = true;
        for(int j = 1; j <= ZZ_Depth; j++) {
            if(iHigh(_Symbol, PERIOD_M15, i-j) >= iHigh(_Symbol, PERIOD_M15, i)) is_high = false;
            if(iLow(_Symbol, PERIOD_M15, i-j) <= iLow(_Symbol, PERIOD_M15, i)) is_low = false;
            if(iHigh(_Symbol, PERIOD_M15, i+j) >= iHigh(_Symbol, PERIOD_M15, i)) is_high = false;
            if(iLow(_Symbol, PERIOD_M15, i+j) <= iLow(_Symbol, PERIOD_M15, i)) is_low = false;
        }
        if(is_high) AddPivot(iTime(_Symbol, PERIOD_M15, i), iHigh(_Symbol, PERIOD_M15, i), 1);
        if(is_low) AddPivot(iTime(_Symbol, PERIOD_M15, i), iLow(_Symbol, PERIOD_M15, i), -1);
    }
}

//+------------------------------------------------------------------+
void AddPivot(datetime time, double price, int type) {
    if(pivot_count == 0) {
        ArrayResize(pivots, 1);
        pivots[0].time = time; 
        pivots[0].price = price; 
        pivots[0].type = type;
        pivot_count = 1; 
        return;
    }
    if(pivots[pivot_count-1].type == type) {
        if((type == 1 && price > pivots[pivot_count-1].price) || (type == -1 && price < pivots[pivot_count-1].price)) {
            pivots[pivot_count-1].time = time; pivots[pivot_count-1].price = price;
        }
    } else {
        if(MathAbs(price - pivots[pivot_count-1].price) >= 0.0005) {
            ArrayResize(pivots, pivot_count + 1);
            pivots[pivot_count].time = time; 
            pivots[pivot_count].price = price; 
            pivots[pivot_count].type = type;
            pivot_count++;
        }
    }
}

//+------------------------------------------------------------------+
void CheckSignal() {
    if(GetTicket() > 0) return;
    if(skip_next) { skip_next = false; return; }
    double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pip_size;
    if(spread > MaxSpread) return;
    if(pivot_count < 2) return;

    Pivot last_p = pivots[pivot_count-1];
    if(last_p.time == last_pivot_time) return;

    int pivot_bar = iBarShift(_Symbol, PERIOD_M15, last_p.time);
    if(pivot_bar < 1 || pivot_bar > 3) return;

    double o1 = iOpen(_Symbol, PERIOD_M15, 1), c1 = iClose(_Symbol, PERIOD_M15, 1);
    bool bull = (c1 > o1), bear = (c1 < o1);

    if(last_p.type == -1 && bull) {
        if(IsTrendAgainst("BUY")) {
            if(log_signals != INVALID_HANDLE) FileWrite(log_signals, TimeToString(TimeCurrent()), _Symbol, "BUY", "LOW", last_p.price, "REJECTED", "HighLevel_Guard_Bearish");
    } else {
    if(log_signals != INVALID_HANDLE) FileWrite(log_signals, TimeToString(TimeCurrent()), _Symbol, "BUY", "LOW", last_p.price, "ENTERED", "PivotLow_Green");
        last_pivot_time = last_p.time; OpenTrade("BUY", "PivotLow_Green");
    }
    } else if(last_p.type == 1 && bear) {
    if(IsTrendAgainst("SELL")) {
        if(log_signals != INVALID_HANDLE) FileWrite(log_signals, TimeToString(TimeCurrent()), _Symbol, "SELL", "HIGH", last_p.price, "REJECTED", "HighLevel_Guard_Bullish");
    } else {
    if(log_signals != INVALID_HANDLE) FileWrite(log_signals, TimeToString(TimeCurrent()), _Symbol, "SELL", "HIGH", last_p.price, "ENTERED", "PivotHigh_Red");
        last_pivot_time = last_p.time; OpenTrade("SELL", "PivotHigh_Red");
    }
    } else {
    if(log_signals != INVALID_HANDLE) FileWrite(log_signals, TimeToString(TimeCurrent()), _Symbol,
        (bull?"BULL":"BEAR"), (last_p.type==-1?"LOW":"HIGH"), last_p.price, "REJECTED",
        (last_p.type==-1&&!bull?"NoBullAfterGreen":(last_p.type==1&&!bear?"NoBearAfterRed":"Unknown")));
    }
}

//+------------------------------------------------------------------+
void ManageTrade(ulong ticket) {
   if(!PositionSelectByTicket(ticket)) return;
   long p_type = PositionGetInteger(POSITION_TYPE);
   string dir = (p_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double cur = (dir == "BUY") ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pips = (dir == "BUY") ? (cur - entry)/pip_size : (entry - cur)/pip_size;

   ApplySafeNet(ticket, dir, entry, cur, pips);

    if(EnableChain && pips >= TP_Pips && CheckMomentum(dir)) {
        CloseTrade(ticket, pips, "CHAIN_TP");
        return;
    }

    if(pivot_count >= 2 && pips > 25.0) {
        Pivot last_p = pivots[pivot_count-1];
        if(dir == "BUY" && last_p.type == 1) CloseTrade(ticket, pips, "PIVOT_EXIT");
        else if(dir == "SELL" && last_p.type == -1) CloseTrade(ticket, pips, "PIVOT_EXIT");
    }

    if(pips <= -SL_Pips) CloseTrade(ticket, pips, "SL_HIT");
}

//+------------------------------------------------------------------+
void ApplySafeNet(ulong ticket, string dir, double entry, double cur, double pips) {
   double cur_sl = PositionGetDouble(POSITION_SL);
   double cur_tp = PositionGetDouble(POSITION_TP);
   double new_sl = cur_sl;
   double new_tp = cur_tp;

   double orig_tp_dist = TP_Pips * pip_size;

   if(pips >= BE_Trigger && safe_phase < 2) {
        if(dir == "BUY") {
        new_sl = entry + (BE_Profit * pip_size);
        new_tp = cur + orig_tp_dist;
    } else {
        new_sl = entry - (BE_Profit * pip_size);
        new_tp = cur - orig_tp_dist;
    }
    safe_phase = 2;
   }

   if(pips >= Trail_Trigger && safe_phase < 3) {
        if(dir == "BUY") {
        new_sl = cur - (Trail_Dist * pip_size);
        new_tp = cur + orig_tp_dist;
    } else {
        new_sl = cur + (Trail_Dist * pip_size);
        new_tp = cur - orig_tp_dist;
    }
    safe_phase = 3;
   }

   double norm_new_sl = NormalizeDouble(new_sl, _Digits);
   double norm_cur_sl = NormalizeDouble(cur_sl, _Digits);
   double norm_new_tp = NormalizeDouble(new_tp, _Digits);
   double norm_cur_tp = NormalizeDouble(cur_tp, _Digits);

   if(norm_new_sl == norm_cur_sl && norm_new_tp == norm_cur_tp) return;

   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_SLTP; req.symbol = _Symbol; req.position = ticket;
   req.sl = norm_new_sl; req.tp = norm_new_tp;

   if(!OrderSend(req, res)) {
   if(res.retcode != TRADE_RETCODE_INVALID) Print("SL/TP Error: ", res.retcode);
   }
}

//+------------------------------------------------------------------+
bool CheckMomentum(string dir) {
    int consec = 0;
    for(int i=1; i<=Mom_Candles; i++) {
        double o = iOpen(_Symbol, PERIOD_M3, i), c = iClose(_Symbol, PERIOD_M3, i);
        if((dir == "BUY" && c > o) || (dir == "SELL" && c < o)) consec++;
    }
    return consec >= Mom_Candles;
}

//+------------------------------------------------------------------+
bool IsTrendAgainst(string dir) {
    if(c_level < 19) return false;
    int bear = 0, bull = 0;
    for(int i=1; i<=3; i++) {
        double o = iOpen(_Symbol, PERIOD_M15, i);
        double c = iClose(_Symbol, PERIOD_M15, i);
        if(c < o) bear++; else if(c > o) bull++;
    }
    if(dir == "BUY" && bear > bull) return true;
    if(dir == "SELL" && bull > bear) return true;
    return false;
}
//+------------------------------------------------------------------+
void OpenTrade(string dir, string reason) {
    double lot = GetLot();
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entry = (dir == "BUY") ? ask : bid;
    double sl = NormalizeDouble((dir == "BUY") ? entry - (SL_Pips * pip_size) : entry + (SL_Pips * pip_size), _Digits);
    double tp = NormalizeDouble((dir == "BUY") ? entry + (TP_Pips * pip_size) : entry - (TP_Pips * pip_size), _Digits);

    double margin_req = 0;
    if(!OrderCalcMargin((dir=="BUY")?ORDER_TYPE_BUY:ORDER_TYPE_SELL, _Symbol, lot, entry, margin_req)) return;
    if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin_req + 1.0) return;

    MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
    req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = lot; req.price = entry;
    req.sl = sl; req.tp = tp; req.magic = Magic; req.deviation = 10; req.type_filling = order_fill;
    if(dir == "BUY") req.type = ORDER_TYPE_BUY; else req.type = ORDER_TYPE_SELL;

    if(SendOrder(req, res)) {
        safe_phase = 0;
        Print("ENTRY: ", dir, " ", lot, " @ ", entry, " | SL: ", sl, " | TP: ", tp);
        if(log_h != INVALID_HANDLE) FileWrite(log_h, TimeToString(TimeCurrent()), dir, entry, 0, 0, 0, c_level, reason);
        if(log_trades != INVALID_HANDLE) FileWrite(log_trades, TimeToString(TimeCurrent()), dir, entry, 0, 0, 0, c_level, reason);
    }
}

//+------------------------------------------------------------------+
void CloseTrade(ulong ticket, double pips, string reason) {
    if(!PositionSelectByTicket(ticket)) return;
    long p_type = PositionGetInteger(POSITION_TYPE);
    string dir = (p_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    double lot = PositionGetDouble(POSITION_VOLUME), entry = PositionGetDouble(POSITION_PRICE_OPEN);

    MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
    double close = (dir == "BUY") ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = lot; req.price = close; req.position = ticket;
    req.magic = Magic; req.deviation = 10; req.type_filling = order_fill;
    if(dir == "BUY") req.type = ORDER_TYPE_SELL; else req.type = ORDER_TYPE_BUY;

    if(SendOrder(req, res)) {
        double usd = pips * pip_size * 100000 * lot;
        Print("EXIT: ", pips, " pips | $", usd, " | ", reason);
        if(log_h != INVALID_HANDLE) FileWrite(log_h, TimeToString(TimeCurrent()), dir, entry, close, pips, usd, c_level, reason);
        if(log_trades != INVALID_HANDLE) FileWrite(log_trades, TimeToString(TimeCurrent()), dir, entry, close, pips, usd, c_level, reason);

        ProcessTradeResult(usd);
    }
}

//+------------------------------------------------------------------+
void ProcessTradeResult(double profit_usd) {
    v_balance += profit_usd;
    int prev_level = c_level;
    if (profit_usd < 0) {
 // STRICTLY FOLLOW PDF: Go back ONE level, need TWO wins to recover
    in_stepdown = true; 
    stepdown_level = c_level; 
    c_level = MathMax(1, c_level - 1); // Drop exactly 1 level
    wins_needed = 1; // Need 1 win to recover
    skip_next = true;
    l_profit = 0;
 
 // Balance recalc: if balance has fallen below level total, drop further
 int new_lvl = 1;
    for(int lvl = 30; lvl >= 1; lvl--) { 
    if(v_balance >= levels_total[lvl]) { new_lvl = lvl; break; } 
 }
    if(new_lvl < c_level) { c_level = new_lvl; }
 
    Print("STEPDOWN: loss $", profit_usd, " level ", stepdown_level, "→", c_level, " needs ", wins_needed, " wins");
 } else {
 if (in_stepdown) {
    l_profit += profit_usd; 
    wins_needed--;
    if (wins_needed <= 0) { 
    in_stepdown = false; 
 // SAFETY CHECK: Only jump back if balance supports it!
 if(v_balance >= levels_total[stepdown_level]) {
    c_level = stepdown_level; 
    } else {
 // If not enough balance, find the highest level we can afford
 for(int lvl = 30; lvl >= 1; lvl--) { 
    if(v_balance >= levels_total[lvl]) { c_level = lvl; break; } 
    }
 }
    l_profit = 0; 
 }
    } else {
    l_profit += profit_usd;
    if (l_profit >= goals[c_level]) { 
    c_level++; 
    if (c_level > 30) c_level = 30; 
    l_profit = 0; 
    }
    }
 }
 // ✅ UPDATED: Level lock set to 21 (Resets when level 21 closes)
    if (prev_level == 21 || c_level > 21) {
        c_level = 1;
        v_balance = 20.0;
        l_profit = 0.0;
        in_stepdown = false;
        stepdown_level = 0;
        wins_needed = 0;
        in_recovery = false;
        Print("✅ Order flow 21st closed: Resetting counter to 1st level and Virtual Balance to $20.0");
    }
 
 if(v_balance < 20.0 && !TestMode) in_recovery = true; else in_recovery = false;
        SaveState();
    if(log_state != INVALID_HANDLE) FileWrite(log_state, TimeToString(TimeCurrent()), c_level, DoubleToString(v_balance,2),
    DoubleToString(l_profit,2), in_stepdown?1:0, stepdown_level, wins_needed);
}

//+------------------------------------------------------------------+
double GetLot() {
 if (v_balance < 20.0 && !TestMode) return 0.01;
 if (c_level < 1) c_level = 1; if (c_level > 30) c_level = 30;
 return lots[c_level];
}

ulong GetTicket() {
 for(int i=PositionsTotal()-1; i>=0; i--) {
 ulong t = PositionGetTicket(i);
 if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) return t;
 }
 return 0;
}

//+------------------------------------------------------------------+
void LoadState() {
   string p = "R6_" + IntegerToString(Magic) + "_";
   double sb = GlobalVariableGet(p + "VB"); int sl = (int)GlobalVariableGet(p + "Lvl"); double lp = GlobalVariableGet(p + "LP");
   double sd = GlobalVariableGet(p + "SD"); int sdl = (int)GlobalVariableGet(p + "SD_Lvl"); int sdw = (int)GlobalVariableGet(p + "SD_Wins");
   double lpt = GlobalVariableGet(p + "LPT"); double lb = GlobalVariableGet(p + "LB");
   if(sb > 0) v_balance = sb; if(sl > 0) c_level = sl; if(lp >= 0) l_profit = lp;
   if(sd > 0) in_stepdown = true; if(sdl > 0) stepdown_level = sdl; if(sdw > 0) wins_needed = sdw;
   if(lpt > 0) last_pivot_time = (datetime)lpt; if(lb > 0) last_bar = (datetime)lb;
}

//+------------------------------------------------------------------+
void SaveState() {
   string p = "R6_" + IntegerToString(Magic) + "_";
   GlobalVariableSet(p + "VB", v_balance); GlobalVariableSet(p + "Lvl", c_level); GlobalVariableSet(p + "LP", l_profit);
   GlobalVariableSet(p + "SD", in_stepdown ? 1.0 : 0.0); GlobalVariableSet(p + "SD_Lvl", stepdown_level); GlobalVariableSet(p + "SD_Wins", wins_needed);
   GlobalVariableSet(p + "LPT", (double)last_pivot_time); GlobalVariableSet(p + "LB", (double)last_bar);
}