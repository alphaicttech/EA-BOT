#ifndef __XAU_TRADE_MANAGER_MQH__
#define __XAU_TRADE_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "XAU_Logger.mqh"

class CTradeManager
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   long              m_magic;
   CLogger          *m_logger;

public:
                     CTradeManager(void)
     {
      m_symbol="";
      m_magic=0;
      m_logger=NULL;
     }

   void              Init(const string symbol,const long magic,const int deviation,CLogger &logger)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_logger=&logger;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviation);
      m_trade.SetTypeFillingBySymbol(m_symbol);
     }

   bool              OpenOriginal(const ENUM_ORDER_TYPE type,const double volume,const double sl,const double tp,const string signalReason)
     {
      string cmt="ORIG|"+signalReason;
      bool ok=(type==ORDER_TYPE_BUY) ? m_trade.Buy(volume,m_symbol,0.0,sl,tp,cmt)
                                     : m_trade.Sell(volume,m_symbol,0.0,sl,tp,cmt);
      if(!ok && m_logger!=NULL)
         m_logger.Warn("TRADE","OpenOriginal failed. retcode="+IntegerToString((int)m_trade.ResultRetcode()));
      return ok;
     }

   bool              OpenCorrector(const ENUM_ORDER_TYPE type,const double volume,const double sl,const double tp,const string reason)
     {
      string cmt="CORR|"+reason;
      bool ok=(type==ORDER_TYPE_BUY) ? m_trade.Buy(volume,m_symbol,0.0,sl,tp,cmt)
                                     : m_trade.Sell(volume,m_symbol,0.0,sl,tp,cmt);
      if(!ok && m_logger!=NULL)
         m_logger.Warn("TRADE","OpenCorrector failed. retcode="+IntegerToString((int)m_trade.ResultRetcode()));
      return ok;
     }

   bool              ModifySLTP(const ulong ticket,const double sl,const double tp)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      bool ok=m_trade.PositionModify(ticket,sl,tp);
      if(!ok && m_logger!=NULL)
         m_logger.Warn("TRADE","ModifySLTP failed ticket="+IntegerToString((int)ticket));
      return ok;
     }

   bool              CloseTicket(const ulong ticket)
     {
      bool ok=m_trade.PositionClose(ticket);
      if(!ok && m_logger!=NULL)
         m_logger.Warn("TRADE","Close ticket failed ticket="+IntegerToString((int)ticket));
      return ok;
     }

   void              CloseAllByMagicSymbol(void)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic)
            continue;
         m_trade.PositionClose(ticket);
        }
     }
  };

#endif
