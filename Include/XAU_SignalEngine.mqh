#ifndef __XAU_SIGNAL_ENGINE_MQH__
#define __XAU_SIGNAL_ENGINE_MQH__

#include "XAU_Types.mqh"
#include "XAU_IndicatorEngine.mqh"
#include "XAU_Logger.mqh"

class CSignalEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   CIndicatorEngine *m_ind;
   CLogger          *m_logger;

public:
                     CSignalEngine(void)
     {
      m_symbol="";
      m_tf=PERIOD_CURRENT;
      m_ind=NULL;
      m_logger=NULL;
     }

   void              Init(const string symbol,const ENUM_TIMEFRAMES tf,CIndicatorEngine &ind,CLogger &logger)
     {
      m_symbol=symbol;
      m_tf=tf;
      m_ind=&ind;
      m_logger=&logger;
     }

   bool              BuildEntrySignal(const int lookback,
                                      const double wickToBody,
                                      const double minBodyAtr,
                                      const bool useTrend,
                                      const bool useAdx,
                                      const bool useHtf,
                                      const double adxMin,
                                      const double adxMax,
                                      const double atrMinPts,
                                      const double atrMaxPts,
                                      SignalDecision &out)
     {
      out.Reset();
      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      int need=lookback+10;
      if(CopyRates(m_symbol,m_tf,0,need,rates)<need)
        {
         out.reason="Not enough bars";
         return false;
        }

      double atr=0.0,emaFast=0.0,emaSlow=0.0,adx=0.0,htfEma=0.0;
      if(!m_ind.GetAtr(1,atr) || !m_ind.GetEmaFast(1,emaFast) || !m_ind.GetEmaSlow(1,emaSlow))
        {
         out.reason="Indicator read failed";
         return false;
        }

      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      double atrPts=(point>0.0) ? atr/point : 0.0;
      if(atrPts<atrMinPts || atrPts>atrMaxPts)
        {
         out.reason="ATR regime blocked";
         return true;
        }

      if(useAdx)
        {
         if(!m_ind.GetAdxMain(1,adx))
           {
            out.reason="ADX read failed";
            return false;
           }
         if(adx<adxMin || adx>adxMax)
           {
            out.reason="ADX regime blocked";
            return true;
           }
        }

      // Use closed bar only (shift=1) to keep backtest-safe.
      MqlRates b=rates[1];
      double body=MathAbs(b.close-b.open);
      double upperWick=b.high-MathMax(b.close,b.open);
      double lowerWick=MathMin(b.close,b.open)-b.low;

      if(body<=0)
        {
         out.reason="Doji-like candle filtered";
         return true;
        }

      if(body<minBodyAtr*atr)
        {
         out.reason="Body too small vs ATR";
         return true;
        }

      double prevHigh=rates[2].high;
      double prevLow=rates[2].low;
      for(int i=3;i<lookback+2;i++)
        {
         if(rates[i].high>prevHigh)
            prevHigh=rates[i].high;
         if(rates[i].low<prevLow)
            prevLow=rates[i].low;
        }

      bool bullSweep=(b.low<prevLow && b.close>prevLow);
      bool bearSweep=(b.high>prevHigh && b.close<prevHigh);

      bool bullishReject=(lowerWick/body)>=wickToBody && b.close>b.open;
      bool bearishReject=(upperWick/body)>=wickToBody && b.close<b.open;

      bool trendBuy=true,trendSell=true;
      if(useTrend)
        {
         trendBuy=(b.close>emaFast && emaFast>emaSlow);
         trendSell=(b.close<emaFast && emaFast<emaSlow);
        }

      bool htfBuy=true,htfSell=true;
      if(useHtf)
        {
         if(!m_ind.GetHTFEma(1,htfEma))
           {
            out.reason="HTF EMA read failed";
            return false;
           }
         htfBuy=(b.close>htfEma);
         htfSell=(b.close<htfEma);
        }

      if(bullSweep && bullishReject && trendBuy && htfBuy)
        {
         out.direction=SIGNAL_BUY;
         out.reason="Bull sweep + reject + filters";
         out.confidence=1.0;
         return true;
        }
      if(bearSweep && bearishReject && trendSell && htfSell)
        {
         out.direction=SIGNAL_SELL;
         out.reason="Bear sweep + reject + filters";
         out.confidence=1.0;
         return true;
        }

      out.reason="No qualified sweep/rejection setup";
      return true;
     }
  };

#endif
