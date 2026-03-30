#property strict
#property version   "2.00"
#property description "Balance-reactive multi-entry basket EA for MT5 (research, aggressive with hard safety controls)"

#include <Trade/Trade.mqh>

enum ENUM_LOT_MODE
  {
   LOT_FIXED = 0,
   LOT_BALANCE = 1,
   LOT_RISK_STOP = 2,
   LOT_PROGRESSIVE_INDEX = 3,
   LOT_PROGRESSIVE_TIER = 4
  };

enum ENUM_BASKET_TARGET_MODE
  {
   TARGET_MONEY = 0,
   TARGET_BALANCE_PERCENT = 1,
   TARGET_POINTS_WEIGHTED = 2
  };

//======================== Inputs ========================
input group "General"
input long   InpMagicNumber                = 26033002;
input string InpTradeComment               = "XAU_BR_V2";
input bool   InpEnableBuy                  = true;
input bool   InpEnableSell                 = true;
input bool   InpEntriesOnNewBarOnly        = true;
input int    InpMinSecondsBetweenEntries   = 20;

input group "Signal Engine"
input int    InpEMAFastPeriod              = 21;
input int    InpEMASlowPeriod              = 55;
input int    InpRSIPeriod                  = 14;
input double InpRSIBuyThreshold            = 54.0;
input double InpRSISellThreshold           = 46.0;
input bool   InpUseATRFilter               = true;
input int    InpATRPeriod                  = 14;
input double InpMinATRPoints               = 40.0;
input double InpMaxATRPoints               = 1200.0;
input bool   InpUseBreakoutConfirm         = false;
input bool   InpUseMeanReversionMode       = false;

input group "Scaling / Tiers"
input ENUM_LOT_MODE InpLotMode             = LOT_BALANCE;
input double InpFixedLot                   = 0.01;
input double InpBalanceStep                = 100.0;
input double InpLotIncrementPerStep        = 0.01;
input double InpRiskPerTradePercent        = 0.50;
input double InpProgressiveStep            = 0.15;
input bool   InpAllowGeometricMultiplier   = false;
input double InpMultiplierValue            = 1.20;
input double InpMaxLotPerTrade             = 0.30;
input double InpMaxTotalLotsAll            = 1.20;
input double InpMaxTotalLotsPerSide        = 0.80;
input int    InpTier2Balance               = 200;
input int    InpTier3Balance               = 500;
input int    InpTier4Balance               = 1000;
input int    InpTier1MaxEntriesPerSide     = 2;
input int    InpTier2MaxEntriesPerSide     = 4;
input int    InpTier3MaxEntriesPerSide     = 6;
input int    InpTier4MaxEntriesPerSide     = 8;
input int    InpTier1MaxBasketPositions    = 3;
input int    InpTier2MaxBasketPositions    = 5;
input int    InpTier3MaxBasketPositions    = 8;
input int    InpTier4MaxBasketPositions    = 12;

input group "Entry Limits"
input int    InpMinimumDistancePoints      = 180;
input int    InpMaxEntriesBuy              = 10;
input int    InpMaxEntriesSell             = 10;
input int    InpMaxOpenPositionsTotal      = 16;

input group "Basket Exits"
input ENUM_BASKET_TARGET_MODE InpBasketTargetMode = TARGET_MONEY;
input double InpBasketProfitTargetMoney    = 10.0;
input double InpBasketProfitTargetPercent  = 1.0;
input double InpBasketProfitTargetPtsLot   = 250.0;
input bool   InpCloseOnlyProfitableSide    = false;
input bool   InpEnablePartialClose          = false;
input double InpPartialCloseTriggerMoney    = 7.0;
input double InpPartialClosePercent         = 50.0;
input bool   InpEnableBasketTrailingLock    = true;
input double InpBasketTrailingTriggerMoney  = 15.0;
input double InpBasketTrailingLockMoney     = 5.0;
input bool   InpUseTimeBasedClose           = true;
input int    InpMaxPositionAgeMinutes       = 180;

input group "Per-Trade SL/TP"
input bool   InpUsePerTradeSLTP             = true;
input int    InpPerTradeSLPoints            = 350;
input int    InpPerTradeTPPoints            = 220;
input bool   InpUseBreakEven                = true;
input int    InpBreakEvenTriggerPoints      = 140;
input int    InpBreakEvenLockPoints         = 20;
input bool   InpUseTrailingStop             = true;
input int    InpTrailingStartPoints         = 170;
input int    InpTrailingStepPoints          = 70;
input bool   InpUseHiddenEmergencySL        = true;
input double InpEmergencyStopLossMoney      = 30.0;

input group "Risk Controls"
input double InpMaxDrawdownPercent          = 20.0;
input double InpMaxFloatingLossMoney        = 35.0;
input double InpMaxDailyLossMoney           = 25.0;
input double InpMaxSpreadPoints             = 60.0;
input int    InpMaxSlippagePoints           = 20;
input double InpMaxMarginUsagePercent       = 65.0;
input double InpMinFreeMargin               = 50.0;
input double InpEquityStopAmount            = 70.0;
input int    InpCooldownMinutes             = 20;
input int    InpMaxConsecutiveLosingBaskets = 4;
input bool   InpPauseOnSpreadSpike          = true;
input double InpSpreadSpikePoints           = 120.0;
input int    InpSpreadSpikePauseMinutes     = 15;

input group "Session / Days"
input int    InpSessionStartHour            = 0;
input int    InpSessionEndHour              = 24;
input bool   InpTradeMonday                 = true;
input bool   InpTradeTuesday                = true;
input bool   InpTradeWednesday              = true;
input bool   InpTradeThursday               = true;
input bool   InpTradeFriday                 = true;
input bool   InpForceCloseFriday            = true;
input int    InpForceCloseFridayHour        = 20;

//======================== Globals ========================
CTrade g_trade;
int    g_emaFastHandle=INVALID_HANDLE;
int    g_emaSlowHandle=INVALID_HANDLE;
int    g_rsiHandle=INVALID_HANDLE;
int    g_atrHandle=INVALID_HANDLE;

datetime g_lastBarTime=0;
datetime g_lastEntryTime=0;
datetime g_lastRiskStopTime=0;
datetime g_spreadPauseUntil=0;

double   g_dayStartBalance=0.0;
datetime g_dayStartTime=0;
double   g_peakEquity=0.0;

int      g_consecutiveBasketLosses=0;
double   g_basketPeakProfit=0.0;
bool     g_tradingDisabled=false;
string   g_blockReason="OK";

//======================== Structs ========================
struct SideStats
  {
   int    count;
   double lots;
   double profit;
   double lastOpenPrice;
   datetime oldestOpenTime;
   double worstEntryPrice;
  };

struct BasketStats
  {
   SideStats buy;
   SideStats sell;
   int    totalCount;
   double totalLots;
   double totalProfit;
   datetime oldestTime;
  };

//======================== Helpers ========================
bool IsHedgingMode()
  {
   long mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (mm==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

void ResetDailyAnchor()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);
   t.hour=0; t.min=0; t.sec=0;
   g_dayStartTime=StructToTime(t);
   g_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
  }

void CheckDailyRollover()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);
   t.hour=0; t.min=0; t.sec=0;
   datetime today=StructToTime(t);
   if(today!=g_dayStartTime)
      ResetDailyAnchor();
  }

bool IsNewBar()
  {
   datetime t=iTime(_Symbol,_Period,0);
   if(t<=0) return false;
   if(t!=g_lastBarTime)
     {
      g_lastBarTime=t;
      return true;
     }
   return false;
  }

bool DayAllowed(int dow)
  {
   if(dow==1) return InpTradeMonday;
   if(dow==2) return InpTradeTuesday;
   if(dow==3) return InpTradeWednesday;
   if(dow==4) return InpTradeThursday;
   if(dow==5) return InpTradeFriday;
   return false;
  }

bool SessionAllowed()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(!DayAllowed(now.day_of_week)) return false;

   if(InpSessionStartHour==InpSessionEndHour) return true;
   if(InpSessionStartHour<InpSessionEndHour)
      return (now.hour>=InpSessionStartHour && now.hour<InpSessionEndHour);
   return (now.hour>=InpSessionStartHour || now.hour<InpSessionEndHour);
  }

double SpreadPoints()
  {
   double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(p<=0.0) return 99999.0;
   return (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/p;
  }

double NormalizeLot(double lot)
  {
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;
   lot=MathMax(minLot,MathMin(maxLot,lot));
   lot=MathFloor(lot/step)*step;
   return NormalizeDouble(lot,2);
  }

int GetBalanceTier(double bal)
  {
   if(bal>=InpTier4Balance) return 4;
   if(bal>=InpTier3Balance) return 3;
   if(bal>=InpTier2Balance) return 2;
   return 1;
  }

int TierMaxEntriesPerSide(int tier)
  {
   if(tier==4) return InpTier4MaxEntriesPerSide;
   if(tier==3) return InpTier3MaxEntriesPerSide;
   if(tier==2) return InpTier2MaxEntriesPerSide;
   return InpTier1MaxEntriesPerSide;
  }

int TierMaxBasketPositions(int tier)
  {
   if(tier==4) return InpTier4MaxBasketPositions;
   if(tier==3) return InpTier3MaxBasketPositions;
   if(tier==2) return InpTier2MaxBasketPositions;
   return InpTier1MaxBasketPositions;
  }

bool ReadBufferValue(int handle,int shift,double &val)
  {
   double b[1];
   if(CopyBuffer(handle,0,shift,1,b)!=1) return false;
   val=b[0];
   return true;
  }

void CollectBasketStats(BasketStats &bs)
  {
   ZeroMemory(bs);
   bs.buy.oldestOpenTime=0;
   bs.sell.oldestOpenTime=0;
   bs.oldestTime=0;

   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double lots=PositionGetDouble(POSITION_VOLUME);
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)+PositionGetDouble(POSITION_COMMISSION);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);

      bs.totalCount++;
      bs.totalLots+=lots;
      bs.totalProfit+=profit;
      if(bs.oldestTime==0 || ot<bs.oldestTime) bs.oldestTime=ot;

      if(type==POSITION_TYPE_BUY)
        {
         bs.buy.count++; bs.buy.lots+=lots; bs.buy.profit+=profit;
         bs.buy.lastOpenPrice=openPrice;
         if(bs.buy.oldestOpenTime==0 || ot<bs.buy.oldestOpenTime) bs.buy.oldestOpenTime=ot;
         if(bs.buy.worstEntryPrice==0.0 || openPrice<bs.buy.worstEntryPrice) bs.buy.worstEntryPrice=openPrice;
        }
      else if(type==POSITION_TYPE_SELL)
        {
         bs.sell.count++; bs.sell.lots+=lots; bs.sell.profit+=profit;
         bs.sell.lastOpenPrice=openPrice;
         if(bs.sell.oldestOpenTime==0 || ot<bs.sell.oldestOpenTime) bs.sell.oldestOpenTime=ot;
         if(bs.sell.worstEntryPrice==0.0 || openPrice>bs.sell.worstEntryPrice) bs.sell.worstEntryPrice=openPrice;
        }
     }
  }

double GetTargetProfitMoney(const BasketStats &bs)
  {
   if(InpBasketTargetMode==TARGET_MONEY)
      return InpBasketProfitTargetMoney;

   if(InpBasketTargetMode==TARGET_BALANCE_PERCENT)
      return AccountInfoDouble(ACCOUNT_BALANCE)*(InpBasketProfitTargetPercent/100.0);

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0) return InpBasketProfitTargetMoney;
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) return InpBasketProfitTargetMoney;
   double valuePerPointPerLot=tickValue*(point/tickSize);
   return InpBasketProfitTargetPtsLot*valuePerPointPerLot*MathMax(0.01,bs.totalLots);
  }

bool CloseTicket(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   bool ok=g_trade.PositionClose(ticket);
   return ok;
  }

void CloseAllEA(const string reason)
  {
   int total=PositionsTotal();
   for(int i=total-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      g_trade.PositionClose(ticket);
     }
   Print("[RISK] Closed all EA positions. Reason=",reason);
  }

void CloseSide(ENUM_POSITION_TYPE side)
  {
   int total=PositionsTotal();
   for(int i=total-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;
      g_trade.PositionClose(ticket);
     }
  }

void PartialCloseSide(ENUM_POSITION_TYPE side,double percent)
  {
   double ratio=MathMax(0.0,MathMin(100.0,percent))/100.0;
   if(ratio<=0.0) return;

   int total=PositionsTotal();
   for(int i=total-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double closeVol=NormalizeLot(vol*ratio);
      double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      if(closeVol<minLot) continue;
      g_trade.PositionClosePartial(ticket,closeVol);
     }
  }

//======================== Signals ========================
bool BuildSignals(bool &buySig,bool &sellSig)
  {
   buySig=false;
   sellSig=false;

   MqlRates r[3];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,_Period,0,3,r)<3) return false;

   double emaF=0,emaS=0,rsi=0,atr=0;
   if(!ReadBufferValue(g_emaFastHandle,1,emaF)) return false;
   if(!ReadBufferValue(g_emaSlowHandle,1,emaS)) return false;
   if(!ReadBufferValue(g_rsiHandle,1,rsi)) return false;
   if(InpUseATRFilter && !ReadBufferValue(g_atrHandle,1,atr)) return false;

   if(InpUseATRFilter)
     {
      double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      double atrPts=(p>0.0)?atr/p:0.0;
      if(atrPts<InpMinATRPoints || atrPts>InpMaxATRPoints)
         return true;
     }

   bool trendUp=(emaF>emaS);
   bool trendDn=(emaF<emaS);

   bool breakoutBuy=true,breakoutSell=true;
   if(InpUseBreakoutConfirm)
     {
      breakoutBuy=(r[1].close>r[2].high);
      breakoutSell=(r[1].close<r[2].low);
     }

   if(!InpUseMeanReversionMode)
     {
      buySig = trendUp && (rsi>=InpRSIBuyThreshold) && breakoutBuy;
      sellSig= trendDn && (rsi<=InpRSISellThreshold) && breakoutSell;
     }
   else
     {
      // Mean reversion mode uses trend as context but RSI extremes against trend pullback.
      buySig = trendUp && (rsi<=45.0);
      sellSig= trendDn && (rsi>=55.0);
     }

   return true;
  }

//======================== Risk / Permissions ========================
bool HasTradingPermissions(string &reason)
  {
   reason="OK";
   if(g_tradingDisabled) { reason="Trading disabled by equity-stop"; return false; }

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_peakEquity<=0.0 || eq>g_peakEquity) g_peakEquity=eq;

   if(eq<=InpEquityStopAmount)
     {
      CloseAllEA("Equity stop");
      g_tradingDisabled=true;
      reason="Equity stop hit";
      return false;
     }

   double ddPct=(g_peakEquity>0.0)?((g_peakEquity-eq)/g_peakEquity)*100.0:0.0;
   if(ddPct>=InpMaxDrawdownPercent) { reason="Max drawdown exceeded"; return false; }

   BasketStats bs;
   CollectBasketStats(bs);
   if(bs.totalProfit<=-InpMaxFloatingLossMoney) { reason="Max floating loss"; return false; }

   CheckDailyRollover();
   double dailyPnL=eq-g_dayStartBalance;
   if(dailyPnL<=-InpMaxDailyLossMoney) { reason="Max daily loss"; return false; }

   if(TimeCurrent()<g_lastRiskStopTime+(InpCooldownMinutes*60)) { reason="Cooldown active"; return false; }
   if(TimeCurrent()<g_spreadPauseUntil) { reason="Spread spike pause"; return false; }

   double sp=SpreadPoints();
   if(sp>InpMaxSpreadPoints) { reason="Spread too high"; return false; }
   if(InpPauseOnSpreadSpike && sp>=InpSpreadSpikePoints)
     {
      g_spreadPauseUntil=TimeCurrent()+InpSpreadSpikePauseMinutes*60;
      reason="Spread spike pause armed";
      return false;
     }

   if(!SessionAllowed()) { reason="Session/day filter"; return false; }

   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double freeMargin=AccountInfoDouble(ACCOUNT_FREEMARGIN);
   if(freeMargin<InpMinFreeMargin) { reason="Free margin low"; return false; }

   // Approx margin usage (if margin level unavailable, fallback to used/equity).
   double usagePct=0.0;
   if(marginLevel>0.0)
      usagePct=100.0*(100.0/marginLevel);
   else if(eq>0.0)
      usagePct=(margin/eq)*100.0;
   if(usagePct>=InpMaxMarginUsagePercent) { reason="Margin usage high"; return false; }

   if(g_consecutiveBasketLosses>=InpMaxConsecutiveLosingBaskets)
     {
      reason="Consecutive basket loss lock";
      return false;
     }

   return true;
  }

//======================== Lot Calculation ========================
double BaseLotFromBalance(double balance)
  {
   if(InpBalanceStep<=0.0)
      return InpFixedLot;
   int steps=(int)MathFloor(balance/InpBalanceStep);
   return InpFixedLot + steps*InpLotIncrementPerStep;
  }

double LotByRiskStop(double slPoints)
  {
   if(slPoints<=0) return InpFixedLot;
   double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*(InpRiskPerTradePercent/100.0);
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(tickVal<=0 || tickSz<=0 || point<=0) return InpFixedLot;
   double valuePerPointPerLot=tickVal*(point/tickSz);
   if(valuePerPointPerLot<=0) return InpFixedLot;
   return riskMoney/(slPoints*valuePerPointPerLot);
  }

double ComputeEntryLot(int entryIndex,int tier)
  {
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double lot=InpFixedLot;

   switch(InpLotMode)
     {
      case LOT_FIXED:
         lot=InpFixedLot;
         break;
      case LOT_BALANCE:
         lot=BaseLotFromBalance(bal);
         break;
      case LOT_RISK_STOP:
         lot=LotByRiskStop((double)InpPerTradeSLPoints);
         break;
      case LOT_PROGRESSIVE_INDEX:
         lot=BaseLotFromBalance(bal)*(1.0 + InpProgressiveStep*entryIndex);
         break;
      case LOT_PROGRESSIVE_TIER:
         lot=BaseLotFromBalance(bal)*(1.0 + 0.20*(tier-1));
         lot=lot*(1.0 + InpProgressiveStep*entryIndex*0.5);
         break;
     }

   if(InpAllowGeometricMultiplier)
      lot*=MathPow(InpMultiplierValue,entryIndex);

   lot=MathMin(lot,InpMaxLotPerTrade);
   return NormalizeLot(lot);
  }

bool DistanceOkForSide(ENUM_POSITION_TYPE side,double price,double minDistPts)
  {
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0) return false;

   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(price-op)/point<minDistPts)
         return false;
     }
   return true;
  }

bool CanOpenSide(ENUM_POSITION_TYPE side,const BasketStats &bs,string &reason)
  {
   reason="";
   int tier=GetBalanceTier(AccountInfoDouble(ACCOUNT_BALANCE));
   int maxSideByTier=TierMaxEntriesPerSide(tier);
   int sideCap=(side==POSITION_TYPE_BUY)?MathMin(InpMaxEntriesBuy,maxSideByTier):MathMin(InpMaxEntriesSell,maxSideByTier);

   if(bs.totalCount>=InpMaxOpenPositionsTotal) { reason="Max total positions"; return false; }
   if(bs.totalCount>=TierMaxBasketPositions(tier)) { reason="Tier basket cap"; return false; }

   if(side==POSITION_TYPE_BUY && bs.buy.count>=sideCap) { reason="Buy cap"; return false; }
   if(side==POSITION_TYPE_SELL && bs.sell.count>=sideCap) { reason="Sell cap"; return false; }

   if(side==POSITION_TYPE_BUY && bs.buy.lots>=InpMaxTotalLotsPerSide) { reason="Buy lots cap"; return false; }
   if(side==POSITION_TYPE_SELL && bs.sell.lots>=InpMaxTotalLotsPerSide) { reason="Sell lots cap"; return false; }
   if(bs.totalLots>=InpMaxTotalLotsAll) { reason="Total lots cap"; return false; }

   if(!IsHedgingMode())
     {
      // Netting safety: don't open opposite side if any side already exists.
      if(bs.totalCount>0)
        {
         if(side==POSITION_TYPE_BUY && bs.sell.count>0) { reason="Netting opposite lock"; return false; }
         if(side==POSITION_TYPE_SELL && bs.buy.count>0) { reason="Netting opposite lock"; return false; }
        }
     }

   return true;
  }

bool OpenOrder(ENUM_ORDER_TYPE type,double lot)
  {
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int stopLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minStop=stopLevel*point;

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=0,tp=0;

   if(InpUsePerTradeSLTP)
     {
      double slDist=MathMax(minStop,InpPerTradeSLPoints*point);
      double tpDist=MathMax(minStop,InpPerTradeTPPoints*point);
      if(type==ORDER_TYPE_BUY)
        {
         sl=ask-slDist;
         tp=ask+tpDist;
        }
      else
        {
         sl=bid+slDist;
         tp=bid-tpDist;
        }
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpMaxSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   bool ok=(type==ORDER_TYPE_BUY)
           ?g_trade.Buy(lot,_Symbol,0.0,sl,tp,InpTradeComment)
           :g_trade.Sell(lot,_Symbol,0.0,sl,tp,InpTradeComment);
   if(!ok)
      Print("[ORDER] failed retcode=",g_trade.ResultRetcode()," msg=",g_trade.ResultRetcodeDescription());
   return ok;
  }

//======================== Position Management ========================
void ManagePerTradeStops()
  {
   if(!InpUseBreakEven && !InpUseTrailingStop)
      return;

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);

      double profitPts=(type==POSITION_TYPE_BUY)?(bid-open)/point:(open-ask)/point;
      double newSL=sl;

      if(InpUseBreakEven && profitPts>=InpBreakEvenTriggerPoints)
        {
         if(type==POSITION_TYPE_BUY)
            newSL=MathMax(newSL,open+InpBreakEvenLockPoints*point);
         else
           {
            double be=open-InpBreakEvenLockPoints*point;
            if(newSL==0.0 || newSL>be) newSL=be;
           }
        }

      if(InpUseTrailingStop && profitPts>=InpTrailingStartPoints)
        {
         if(type==POSITION_TYPE_BUY)
           {
            double tsl=bid-InpTrailingStepPoints*point;
            newSL=MathMax(newSL,tsl);
           }
         else
           {
            double tsl=ask+InpTrailingStepPoints*point;
            if(newSL==0.0 || newSL>tsl) newSL=tsl;
           }
        }

      if(newSL!=sl)
         g_trade.PositionModify(ticket,newSL,tp);
     }
  }

void HandleBasketExits(BasketStats &bs)
  {
   if(bs.totalCount<=0)
     {
      g_basketPeakProfit=0.0;
      return;
     }

   double target=GetTargetProfitMoney(bs);

   if(InpCloseOnlyProfitableSide)
     {
      if(bs.buy.profit>=target && bs.buy.count>0)
         CloseSide(POSITION_TYPE_BUY);
      if(bs.sell.profit>=target && bs.sell.count>0)
         CloseSide(POSITION_TYPE_SELL);
     }

   if(bs.totalProfit>=target)
     {
      CloseAllEA("Basket target hit");
      g_consecutiveBasketLosses=0;
      g_lastRiskStopTime=TimeCurrent();
      return;
     }

   if(InpEnablePartialClose && bs.totalProfit>=InpPartialCloseTriggerMoney)
     {
      if(bs.buy.profit>0) PartialCloseSide(POSITION_TYPE_BUY,InpPartialClosePercent);
      if(bs.sell.profit>0) PartialCloseSide(POSITION_TYPE_SELL,InpPartialClosePercent);
     }

   if(InpEnableBasketTrailingLock)
     {
      if(bs.totalProfit>g_basketPeakProfit)
         g_basketPeakProfit=bs.totalProfit;

      if(g_basketPeakProfit>=InpBasketTrailingTriggerMoney)
        {
         double floorProfit=g_basketPeakProfit-InpBasketTrailingLockMoney;
         if(bs.totalProfit<=floorProfit)
           {
            CloseAllEA("Basket trailing lock fallback");
            if(bs.totalProfit<0) g_consecutiveBasketLosses++;
            else g_consecutiveBasketLosses=0;
            g_lastRiskStopTime=TimeCurrent();
            g_basketPeakProfit=0.0;
           }
        }
     }

   if(InpUseHiddenEmergencySL && bs.totalProfit<=-InpEmergencyStopLossMoney)
     {
      CloseAllEA("Hidden emergency SL");
      g_consecutiveBasketLosses++;
      g_lastRiskStopTime=TimeCurrent();
      g_basketPeakProfit=0.0;
      return;
     }

   if(InpUseTimeBasedClose && bs.oldestTime>0)
     {
      if((TimeCurrent()-bs.oldestTime)>=InpMaxPositionAgeMinutes*60)
        {
         CloseAllEA("Time based closure");
         if(bs.totalProfit<0) g_consecutiveBasketLosses++;
         else g_consecutiveBasketLosses=0;
         g_lastRiskStopTime=TimeCurrent();
         g_basketPeakProfit=0.0;
        }
     }
  }

void ForceCloseFridayIfNeeded()
  {
   if(!InpForceCloseFriday) return;
   MqlDateTime n;
   TimeToStruct(TimeCurrent(),n);
   if(n.day_of_week==5 && n.hour>=InpForceCloseFridayHour)
      CloseAllEA("Forced Friday close");
  }

//======================== Panel ========================
double TodayClosedPnL()
  {
   if(!HistorySelect(g_dayStartTime,TimeCurrent()))
      return 0.0;

   double pnl=0.0;
   int deals=(int)HistoryDealsTotal();
   for(int i=0;i<deals;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber) continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      pnl+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_COMMISSION);
     }
   return pnl;
  }

void DrawPanel(const BasketStats &bs,const string status)
  {
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   int tier=GetBalanceTier(bal);
   string txt="XAU BalanceReactive V2\n";
   txt+="Balance: "+DoubleToString(bal,2)+" Equity: "+DoubleToString(eq,2)+"\n";
   txt+="Floating P/L: "+DoubleToString(bs.totalProfit,2)+" Today Closed: "+DoubleToString(TodayClosedPnL(),2)+"\n";
   txt+="Buy Cnt/Lots: "+IntegerToString(bs.buy.count)+" / "+DoubleToString(bs.buy.lots,2)+"\n";
   txt+="Sell Cnt/Lots: "+IntegerToString(bs.sell.count)+" / "+DoubleToString(bs.sell.lots,2)+"\n";
   txt+="Basket Target: "+DoubleToString(GetTargetProfitMoney(bs),2)+" Basket Profit: "+DoubleToString(bs.totalProfit,2)+"\n";
   txt+="Tier: "+IntegerToString(tier)+"  Status: "+status+"\n";
   txt+="Block reason: "+g_blockReason;
   Comment(txt);
  }

//======================== Main ========================
int OnInit()
  {
   if(StringFind(_Symbol,"XAU")<0)
      Print("[WARN] EA optimized for XAU symbols. Current=",_Symbol);

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpMaxSlippagePoints);

   g_emaFastHandle=iMA(_Symbol,_Period,InpEMAFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_emaSlowHandle=iMA(_Symbol,_Period,InpEMASlowPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_rsiHandle=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE);
   g_atrHandle=iATR(_Symbol,_Period,InpATRPeriod);

   if(g_emaFastHandle==INVALID_HANDLE || g_emaSlowHandle==INVALID_HANDLE || g_rsiHandle==INVALID_HANDLE || g_atrHandle==INVALID_HANDLE)
     {
      Print("[INIT] indicator initialization failed");
      return INIT_FAILED;
     }

   ResetDailyAnchor();
   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_lastBarTime=0;
   g_lastEntryTime=0;
   g_blockReason="OK";
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_emaFastHandle!=INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if(g_rsiHandle!=INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_atrHandle!=INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Comment("");
   Print("[DEINIT] reason=",reason);
  }

void OnTick()
  {
   ForceCloseFridayIfNeeded();

   BasketStats bs;
   CollectBasketStats(bs);

   HandleBasketExits(bs);
   ManagePerTradeStops();

   string reason;
   if(!HasTradingPermissions(reason))
     {
      g_blockReason=reason;
      DrawPanel(bs,"BLOCKED");
      return;
     }

   bool entryGate=true;
   if(InpEntriesOnNewBarOnly)
      entryGate=IsNewBar();

   if(!entryGate)
     {
      g_blockReason="Waiting gate";
      DrawPanel(bs,"ACTIVE");
      return;
     }

   if((TimeCurrent()-g_lastEntryTime)<InpMinSecondsBetweenEntries)
     {
      g_blockReason="Entry throttle";
      DrawPanel(bs,"ACTIVE");
      return;
     }

   bool buySig=false,sellSig=false;
   if(!BuildSignals(buySig,sellSig))
     {
      g_blockReason="Signal data not ready";
      DrawPanel(bs,"ACTIVE");
      return;
     }

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int tier=GetBalanceTier(AccountInfoDouble(ACCOUNT_BALANCE));

   if(InpEnableBuy && buySig)
     {
      string r;
      if(CanOpenSide(POSITION_TYPE_BUY,bs,r) && DistanceOkForSide(POSITION_TYPE_BUY,ask,InpMinimumDistancePoints))
        {
         int idx=bs.buy.count;
         double lot=ComputeEntryLot(idx,tier);
         if((bs.buy.lots+lot)<=InpMaxTotalLotsPerSide && (bs.totalLots+lot)<=InpMaxTotalLotsAll)
           {
            if(OpenOrder(ORDER_TYPE_BUY,lot))
               g_lastEntryTime=TimeCurrent();
           }
        }
      else
         g_blockReason=(r==""?"Buy distance/cap":r);
     }

   CollectBasketStats(bs); // refresh after potential buy

   if(InpEnableSell && sellSig)
     {
      string r;
      if(CanOpenSide(POSITION_TYPE_SELL,bs,r) && DistanceOkForSide(POSITION_TYPE_SELL,bid,InpMinimumDistancePoints))
        {
         int idx=bs.sell.count;
         double lot=ComputeEntryLot(idx,tier);
         if((bs.sell.lots+lot)<=InpMaxTotalLotsPerSide && (bs.totalLots+lot)<=InpMaxTotalLotsAll)
           {
            if(OpenOrder(ORDER_TYPE_SELL,lot))
               g_lastEntryTime=TimeCurrent();
           }
        }
      else
         g_blockReason=(r==""?"Sell distance/cap":r);
     }

   CollectBasketStats(bs);
   g_blockReason="OK";
   DrawPanel(bs,"ACTIVE");
  }
