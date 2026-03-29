#ifndef __XAU_BASKET_MANAGER_MQH__
#define __XAU_BASKET_MANAGER_MQH__

#include "XAU_Types.mqh"
#include "XAU_Logger.mqh"

class CBasketManager
  {
private:
   string            m_symbol;
   long              m_magic;
   CLogger          *m_logger;

public:
                     CBasketManager(void)
     {
      m_symbol="";
      m_magic=0;
      m_logger=NULL;
     }

   void              Init(const string symbol,const long magic,CLogger &logger)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_logger=&logger;
     }

   void              Snapshot(BasketSnapshot &snap)
     {
      snap.Reset();
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;

         string symbol=PositionGetString(POSITION_SYMBOL);
         if(symbol!=m_symbol)
            continue;

         long magic=PositionGetInteger(POSITION_MAGIC);
         if(magic!=m_magic)
            continue;

         string comment=PositionGetString(POSITION_COMMENT);
         snap.hasBasket=true;
         snap.positionsCount++;
         snap.floatingProfit+=PositionGetDouble(POSITION_PROFIT);

         datetime open=(datetime)PositionGetInteger(POSITION_TIME);
         if(snap.openTime==0 || open<snap.openTime)
            snap.openTime=open;

         if(StringFind(comment,"ORIG")>=0)
           {
            snap.originalTicket=ticket;
            snap.originalType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            snap.originalOpenPrice=PositionGetDouble(POSITION_PRICE_OPEN);
           }
         else if(StringFind(comment,"CORR")>=0)
           {
            snap.correctorTicket=ticket;
            snap.hasCorrector=true;
           }
        }
     }
  };

#endif
