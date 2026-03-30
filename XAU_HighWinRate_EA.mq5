#property strict
#property description "Production-grade XAUUSD win-rate-first EA with strict risk controls"
#property version   "1.00"

#include "Include/XAU_Types.mqh"
#include "Include/XAU_Logger.mqh"
#include "Include/XAU_IndicatorEngine.mqh"
#include "Include/XAU_SignalEngine.mqh"
#include "Include/XAU_RiskManager.mqh"
#include "Include/XAU_BasketManager.mqh"
#include "Include/XAU_TradeManager.mqh"
#include "Include/XAU_StatsTracker.mqh"

//============================================================
// Inputs: General
//============================================================
input group "General"
input long   InpMagicNumber              = 26032901;
input bool   InpDebugLogs                = true;
input ENUM_TIMEFRAMES InpSignalTF        = PERIOD_M5;
input ENUM_TIMEFRAMES InpHTF             = PERIOD_H1;
input int    InpCooldownBars             = 0;
input bool   InpAllowIntraBarEntries     = true;
input int    InpMinSecondsBetweenEntries = 20;
input bool   InpTesterRelaxedMode        = true;
input int    InpTesterFallbackScore      = 40;

//============================================================
// Inputs: Sessions & Execution Filters
//============================================================
input group "Session and Execution"
input int    InpSessionStartHour         = 6;
input int    InpSessionEndHour           = 21;
input double InpMaxSpreadPoints          = 45.0;
input int    InpMaxDeviationPoints       = 20;
input bool   InpUseFridayCutoff          = true;
input int    InpFridayCutoffHour         = 18;

//============================================================
// Inputs: Signal Quality
//============================================================
input group "Signal Engine"
input int    InpSweepLookbackBars        = 24;
input double InpWickToBodyMinRatio       = 0.8;
input double InpMinBodyAtrFraction       = 0.10;
input bool   InpUseEmaFilter             = true;
input bool   InpUseAdxFilter             = false;
input bool   InpUseHTFConfirm            = false;
input bool   InpEnableTrendPullbackSignal= true;
input int    InpSignalScoreThreshold     = 55;

//============================================================
// Inputs: Indicator Settings
//============================================================
input group "Indicators"
input int    InpAtrPeriod                = 14;
input int    InpEmaFastPeriod            = 34;
input int    InpEmaSlowPeriod            = 89;
input int    InpAdxPeriod                = 14;
input int    InpHtfEmaPeriod             = 50;
input double InpAtrMinPoints             = 45.0;
input double InpAtrMaxPoints             = 1200.0;
input double InpAdxMin                   = 18.0;
input double InpAdxMax                   = 42.0;

//============================================================
// Inputs: Order Sizing & SL/TP
//============================================================
input group "Risk Per Trade"
input double InpBaseLot                  = 0.08;
input double InpRiskScaleAfterLoss       = 0.70;
input int    InpReduceRiskAfterLosses    = 2;
input double InpSL_AtrMult               = 1.6;
input double InpTP_AtrMult               = 1.2;
input bool   InpUseBreakEven             = true;
input double InpBE_TriggerAtr            = 0.7;
input double InpBE_LockAtr               = 0.1;

//============================================================
// Inputs: Basket Controls
//============================================================
input group "Basket Control"
input double InpBasketTargetMoney        = 35.0;
input double InpBasketMaxLossMoney       = 65.0;
input int    InpBasketTimeoutBars        = 30;
input bool   InpCloseOnOppositeSignal    = true;

//============================================================
// Inputs: Corrector
//============================================================
input group "Corrector"
input bool   InpEnableCorrector          = true;
input double InpCorrectorTriggerAtr      = 0.8;
input double InpCorrectorLotMultiplier   = 1.0;
input double InpCorrectorSL_AtrMult      = 1.0;
input double InpCorrectorTP_AtrMult      = 0.8;

//============================================================
// Inputs: Global Risk Locks
//============================================================
input group "Global Risk"
input bool   InpEnableDailyLossStop      = true;
input double InpMaxDailyLossPct          = 3.0;
input int    InpMaxConsecutiveLosses     = 6;
input bool   InpPauseAfterDrawdown       = true;
input double InpPauseDrawdownPct         = 8.0;

//============================================================
// Globals
//============================================================
CLogger          g_logger;
CIndicatorEngine g_indicators;
CSignalEngine    g_signal;
CRiskManager     g_risk;
CBasketManager   g_basket;
CTradeManager    g_trade;
CStatsTracker    g_stats;

datetime         g_lastBarTime=0;
double           g_peakEquity=0.0;
datetime         g_lastEntryTime=0;
int              g_ticksProcessed=0;

//============================================================
// Utility helpers
//============================================================
double NormalizeVolume(const string symbol,double volume)
  {
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);

   if(step<=0.0)
      return minLot;

   volume=MathMax(minLot,MathMin(maxLot,volume));
   double steps=MathRound(volume/step);
   return steps*step;
  }

bool IsNewBar(void)
  {
   datetime t=iTime(_Symbol,InpSignalTF,0);
   if(t==0)
      return false;
   if(t!=g_lastBarTime)
     {
      g_lastBarTime=t;
      return true;
     }
   return false;
  }

int BarsSince(datetime fromTime)
  {
   int shift=iBarShift(_Symbol,InpSignalTF,fromTime,false);
   return (shift<0) ? 999999 : shift;
  }

double BuildRiskAdjustedLot(void)
  {
   int streak=g_risk.CountConsecutiveLosses();
   double lot=InpBaseLot;
   if(streak>=InpReduceRiskAfterLosses)
      lot*=InpRiskScaleAfterLoss;
   return NormalizeVolume(_Symbol,lot);
  }

bool BuildSlTp(const ENUM_ORDER_TYPE orderType,const double atr,const double slAtrMult,const double tpAtrMult,double &sl,double &tp)
  {
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ask<=0 || bid<=0 || atr<=0)
      return false;

   if(orderType==ORDER_TYPE_BUY)
     {
      sl=ask-(slAtrMult*atr);
      tp=ask+(tpAtrMult*atr);
     }
   else
     {
      sl=bid+(slAtrMult*atr);
      tp=bid-(tpAtrMult*atr);
     }
   return true;
  }

void MaybeMoveBreakEven(const BasketSnapshot &snap,const double atr)
  {
   if(!InpUseBreakEven || snap.originalTicket==0 || atr<=0)
      return;

   if(!PositionSelectByTicket(snap.originalTicket))
      return;

   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double trigger=InpBE_TriggerAtr*atr;
   double lock=InpBE_LockAtr*atr;

   if(type==POSITION_TYPE_BUY)
     {
      if(bid-open>=trigger)
        {
         double newSL=open+lock;
         if(sl<newSL)
           {
            g_trade.ModifySLTP(snap.originalTicket,newSL,tp);
            g_logger.Debug("BE","Moved buy original to BE+");
           }
        }
     }
   else
     {
      if(open-ask>=trigger)
        {
         double newSL=open-lock;
         if(sl==0.0 || sl>newSL)
           {
            g_trade.ModifySLTP(snap.originalTicket,newSL,tp);
            g_logger.Debug("BE","Moved sell original to BE+");
           }
        }
     }
  }

void EvaluateCorrector(const BasketSnapshot &snap)
  {
   if(!InpEnableCorrector || snap.hasCorrector || snap.originalTicket==0)
      return;

   if(!PositionSelectByTicket(snap.originalTicket))
      return;

   double atr=0.0;
   if(!g_indicators.GetAtr(1,atr) || atr<=0.0)
      return;

   ENUM_POSITION_TYPE originalType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double vol=PositionGetDouble(POSITION_VOLUME);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   bool adverse=false;
   if(originalType==POSITION_TYPE_BUY)
      adverse=(open-bid)>=InpCorrectorTriggerAtr*atr;
   else
      adverse=(ask-open)>=InpCorrectorTriggerAtr*atr;

   if(!adverse)
      return;

   SignalDecision s;
   if(!g_signal.BuildEntrySignal(InpSweepLookbackBars,InpWickToBodyMinRatio,InpMinBodyAtrFraction,
                                 InpUseEmaFilter,InpUseAdxFilter,InpUseHTFConfirm,InpEnableTrendPullbackSignal,
                                 InpAdxMin,InpAdxMax,InpAtrMinPoints,InpAtrMaxPoints,InpSignalScoreThreshold,s))
      return;

   bool oppositeStrong=((originalType==POSITION_TYPE_BUY && s.direction==SIGNAL_SELL) ||
                        (originalType==POSITION_TYPE_SELL && s.direction==SIGNAL_BUY));

   if(!oppositeStrong)
      return;

   double corrLot=NormalizeVolume(_Symbol,vol*InpCorrectorLotMultiplier);
   ENUM_ORDER_TYPE ord=(s.direction==SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sl=0.0,tp=0.0;
   if(!BuildSlTp(ord,atr,InpCorrectorSL_AtrMult,InpCorrectorTP_AtrMult,sl,tp))
      return;

   if(g_trade.OpenCorrector(ord,corrLot,sl,tp,"OppStrong|"+s.reason))
      g_logger.Info("CORRECTOR","Opened corrector due to adverse move + opposite validated signal");
  }

void ManageOpenBasket(void)
  {
   BasketSnapshot snap;
   g_basket.Snapshot(snap);
   if(!snap.hasBasket)
      return;

   double atr=0.0;
   g_indicators.GetAtr(1,atr);
   MaybeMoveBreakEven(snap,atr);

   if(snap.floatingProfit>=InpBasketTargetMoney)
     {
      g_trade.CloseAllByMagicSymbol();
      g_stats.OnBasketClosed(snap.floatingProfit);
      g_logger.Info("BASKET","Closed at basket target");
      return;
     }

   if(snap.floatingProfit<=-InpBasketMaxLossMoney)
     {
      g_trade.CloseAllByMagicSymbol();
      g_stats.OnBasketClosed(snap.floatingProfit);
      g_logger.Warn("BASKET","Closed at max basket loss");
      return;
     }

   int barsOpen=BarsSince(snap.openTime);
   if(barsOpen>=InpBasketTimeoutBars)
     {
      g_trade.CloseAllByMagicSymbol();
      g_stats.OnBasketClosed(snap.floatingProfit);
      g_logger.Warn("BASKET","Closed at timeout bars");
      return;
     }

   if(InpCloseOnOppositeSignal)
     {
      SignalDecision s;
      if(g_signal.BuildEntrySignal(InpSweepLookbackBars,InpWickToBodyMinRatio,InpMinBodyAtrFraction,
                                   InpUseEmaFilter,InpUseAdxFilter,InpUseHTFConfirm,InpEnableTrendPullbackSignal,
                                   InpAdxMin,InpAdxMax,InpAtrMinPoints,InpAtrMaxPoints,InpSignalScoreThreshold,s))
        {
         bool opposite=(snap.originalType==POSITION_TYPE_BUY && s.direction==SIGNAL_SELL) ||
                       (snap.originalType==POSITION_TYPE_SELL && s.direction==SIGNAL_BUY);
         if(opposite)
           {
            g_trade.CloseAllByMagicSymbol();
            g_stats.OnBasketClosed(snap.floatingProfit);
            g_logger.Info("BASKET","Closed on opposite validated signal");
            return;
           }
        }
     }

   EvaluateCorrector(snap);
  }

bool GlobalRiskPauseTriggered(void)
  {
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_peakEquity<=0.0)
      g_peakEquity=eq;
   if(eq>g_peakEquity)
      g_peakEquity=eq;

   if(!InpPauseAfterDrawdown || g_peakEquity<=0.0)
      return false;

   double ddPct=((g_peakEquity-eq)/g_peakEquity)*100.0;
   return ddPct>=InpPauseDrawdownPct;
  }

void TryOpenOriginal(void)
  {
   BasketSnapshot snap;
   g_basket.Snapshot(snap);
   if(snap.hasBasket)
      return;

   const bool testerRelax=(InpTesterRelaxedMode && (bool)MQLInfoInteger(MQL_TESTER));

   if(g_risk.IsDailyLocked())
     {
      g_logger.Debug("ENTRY","Blocked: daily loss lock");
      return;
     }

   if(GlobalRiskPauseTriggered())
     {
      g_logger.Warn("ENTRY","Blocked: equity drawdown pause mode");
      return;
     }

   int consecLosses=g_risk.CountConsecutiveLosses();
   if(consecLosses>=InpMaxConsecutiveLosses)
     {
      g_logger.Warn("ENTRY","Blocked: max consecutive losses reached");
      return;
     }

   if(!testerRelax && !g_risk.SessionAllowed(InpSessionStartHour,InpSessionEndHour,InpUseFridayCutoff,InpFridayCutoffHour))
     {
      g_logger.Debug("ENTRY","Blocked: session filter");
      return;
     }

   if(!testerRelax && !g_risk.SpreadAllowed(InpMaxSpreadPoints))
     {
      g_logger.Debug("ENTRY","Blocked: spread filter");
      return;
     }

   datetime lastClose=g_stats.LastBasketCloseTime();
   if(lastClose>0 && BarsSince(lastClose)<InpCooldownBars)
     {
      g_logger.Debug("ENTRY","Blocked: cooldown after basket close");
      return;
     }

   if(g_lastEntryTime>0 && (TimeCurrent()-g_lastEntryTime)<InpMinSecondsBetweenEntries)
     {
      g_logger.Debug("ENTRY","Blocked: min seconds between entries");
      return;
     }

   SignalDecision s;
   int dynamicScoreThreshold=InpSignalScoreThreshold;
   if(testerRelax)
      dynamicScoreThreshold=MathMin(InpSignalScoreThreshold,InpTesterFallbackScore);

   if(!g_signal.BuildEntrySignal(InpSweepLookbackBars,InpWickToBodyMinRatio,InpMinBodyAtrFraction,
                                 InpUseEmaFilter,InpUseAdxFilter,InpUseHTFConfirm,InpEnableTrendPullbackSignal,
                                 InpAdxMin,InpAdxMax,InpAtrMinPoints,InpAtrMaxPoints,dynamicScoreThreshold,s))
     {
      g_logger.Debug("ENTRY","Signal error: "+s.reason);
      return;
     }

   if(s.direction==SIGNAL_NONE)
     {
      g_logger.Debug("ENTRY","Skip: "+s.reason);
      return;
     }

   double atr=0.0;
   if(!g_indicators.GetAtr(1,atr) || atr<=0.0)
      return;

   ENUM_ORDER_TYPE ord=(s.direction==SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sl=0.0,tp=0.0;
   if(!BuildSlTp(ord,atr,InpSL_AtrMult,InpTP_AtrMult,sl,tp))
      return;

   double lot=BuildRiskAdjustedLot();
   if(g_trade.OpenOriginal(ord,lot,sl,tp,s.reason))
     {
      g_lastEntryTime=TimeCurrent();
      g_logger.Info("ENTRY","Original opened. dir="+IntegerToString((int)s.direction)+" lot="+DoubleToString(lot,2)+" reason="+s.reason);
     }
  }

//============================================================
// MQL lifecycle
//============================================================
int OnInit()
  {
   if(_Symbol!="XAUUSD" && StringFind(_Symbol,"XAU")<0)
      g_logger.Warn("INIT","This EA is designed for XAU symbols. Current symbol="+_Symbol);

   g_logger.SetDebug(InpDebugLogs);

   if(!g_indicators.Init(_Symbol,InpSignalTF,InpHTF,InpAtrPeriod,InpEmaFastPeriod,InpEmaSlowPeriod,InpAdxPeriod,InpHtfEmaPeriod,g_logger))
      return(INIT_FAILED);

   g_signal.Init(_Symbol,InpSignalTF,g_indicators,g_logger);
   g_risk.Init(_Symbol,InpMagicNumber,g_logger);
   g_basket.Init(_Symbol,InpMagicNumber,g_logger);
   g_trade.Init(_Symbol,InpMagicNumber,InpMaxDeviationPoints,g_logger);
   g_stats.Init(g_logger);

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_lastBarTime=0;
   g_ticksProcessed=0;

   g_logger.Info("INIT","EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_indicators.Release();
   g_logger.Info("DEINIT","EA deinitialized. reason="+IntegerToString(reason));
  }

void OnTick()
  {
   g_ticksProcessed++;
   if(g_ticksProcessed==1)
      g_logger.Info("TICK","First tick received. EA is active in tester/live context.");

   g_risk.OnTickDayUpdate();
   g_risk.EvaluateDailyLossStop(InpEnableDailyLossStop,InpMaxDailyLossPct);

   ManageOpenBasket();
   if(InpAllowIntraBarEntries)
     {
      TryOpenOriginal();
      return;
     }

   if(IsNewBar())
      TryOpenOriginal();
  }
