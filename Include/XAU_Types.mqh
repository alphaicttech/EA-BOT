#ifndef __XAU_TYPES_MQH__
#define __XAU_TYPES_MQH__

enum ENUM_SIGNAL_DIRECTION
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

struct SignalDecision
  {
   ENUM_SIGNAL_DIRECTION direction;
   string            reason;
   double            confidence;

   void Reset()
     {
      direction=SIGNAL_NONE;
      reason="";
      confidence=0.0;
     }
  };

struct BasketSnapshot
  {
   bool              hasBasket;
   int               positionsCount;
   ulong             originalTicket;
   ulong             correctorTicket;
   datetime          openTime;
   double            floatingProfit;
   bool              hasCorrector;
   ENUM_POSITION_TYPE originalType;
   double            originalOpenPrice;

   void Reset()
     {
      hasBasket=false;
      positionsCount=0;
      originalTicket=0;
      correctorTicket=0;
      openTime=0;
      floatingProfit=0.0;
      hasCorrector=false;
      originalType=POSITION_TYPE_BUY;
      originalOpenPrice=0.0;
     }
  };

#endif
