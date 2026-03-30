#ifndef __XAU_RISK_MANAGER_MQH__
#define __XAU_RISK_MANAGER_MQH__

#include "XAU_Logger.mqh"

class CRiskManager
  {
private:
   string            m_symbol;
   long              m_magic;
   CLogger          *m_logger;

   datetime          m_dayStart;
   double            m_dayStartBalance;
   bool              m_dailyLock;

public:
                     CRiskManager(void)
     {
      m_symbol="";
      m_magic=0;
      m_logger=NULL;
      m_dayStart=0;
      m_dayStartBalance=0;
      m_dailyLock=false;
     }

   void              Init(const string symbol,const long magic,CLogger &logger)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_logger=&logger;
      ResetDailyAnchor();
     }

   void              OnTickDayUpdate(void)
     {
      datetime now=TimeCurrent();
      MqlDateTime t;
      TimeToStruct(now,t);
      t.hour=0;
      t.min=0;
      t.sec=0;
      datetime todayStart=StructToTime(t);
      if(todayStart!=m_dayStart)
        {
         ResetDailyAnchor();
         if(m_logger!=NULL)
            m_logger.Info("RISK","New day detected. Daily lock reset.");
        }
     }

   bool              IsDailyLocked(void) const { return m_dailyLock; }

   void              EvaluateDailyLossStop(const bool enabled,const double maxDailyLossPct)
     {
      if(!enabled || m_dailyLock)
         return;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_dayStartBalance<=0.0)
         return;

      double ddPct=((m_dayStartBalance-eq)/m_dayStartBalance)*100.0;
      if(ddPct>=maxDailyLossPct)
        {
         m_dailyLock=true;
         if(m_logger!=NULL)
            m_logger.Warn("RISK","Daily loss stop hit. Drawdown %="+DoubleToString(ddPct,2));
        }
     }

   bool              SessionAllowed(const int startHour,const int endHour,const bool fridayCutoff,const int fridayHour)
     {
      MqlDateTime now;
      TimeToStruct(TimeCurrent(),now);

      if(fridayCutoff && now.day_of_week==5 && now.hour>=fridayHour)
         return false;

      if(startHour==endHour)
         return true;

      if(startHour<endHour)
         return (now.hour>=startHour && now.hour<endHour);

      return (now.hour>=startHour || now.hour<endHour);
     }

   bool              SpreadAllowed(const double maxSpreadPoints)
     {
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0)
         return false;
      double spread=(ask-bid)/point;
      return spread<=maxSpreadPoints;
     }

   int               CountConsecutiveLosses(const int lookbackDeals=100)
     {
      if(!HistorySelect(TimeCurrent()-86400*30,TimeCurrent()))
         return 0;

      int losses=0;
      int total=(int)HistoryDealsTotal();
      int seen=0;
      for(int i=total-1;i>=0 && seen<lookbackDeals;i--)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0)
            continue;

         string sym=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
         if(sym!=m_symbol)
            continue;

         long mg=HistoryDealGetInteger(dealTicket,DEAL_MAGIC);
         if(mg!=m_magic)
            continue;

         long entry=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT)
            continue;

         double profit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+HistoryDealGetDouble(dealTicket,DEAL_SWAP)+HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
         seen++;
         if(profit<0)
            losses++;
         else
            break;
        }
      return losses;
     }

private:
   void              ResetDailyAnchor(void)
     {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(),t);
      t.hour=0;
      t.min=0;
      t.sec=0;
      m_dayStart=StructToTime(t);
      m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dailyLock=false;
     }
  };

#endif
