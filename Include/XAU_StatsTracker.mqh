#ifndef __XAU_STATS_TRACKER_MQH__
#define __XAU_STATS_TRACKER_MQH__

#include "XAU_Logger.mqh"

class CStatsTracker
  {
private:
   int               m_basketsClosed;
   int               m_basketsWon;
   int               m_basketsLost;
   datetime          m_lastBasketClose;
   CLogger          *m_logger;

public:
                     CStatsTracker(void)
     {
      m_basketsClosed=0;
      m_basketsWon=0;
      m_basketsLost=0;
      m_lastBasketClose=0;
      m_logger=NULL;
     }

   void              Init(CLogger &logger)
     {
      m_logger=&logger;
     }

   void              OnBasketClosed(const double pnl)
     {
      m_basketsClosed++;
      if(pnl>=0.0)
         m_basketsWon++;
      else
         m_basketsLost++;
      m_lastBasketClose=TimeCurrent();
      if(m_logger!=NULL)
         m_logger.Info("STATS","Basket closed pnl="+DoubleToString(pnl,2)+" wins="+IntegerToString(m_basketsWon)+" losses="+IntegerToString(m_basketsLost));
     }

   datetime          LastBasketCloseTime(void) const { return m_lastBasketClose; }
  };

#endif
