#ifndef __XAU_INDICATOR_ENGINE_MQH__
#define __XAU_INDICATOR_ENGINE_MQH__

#include "XAU_Logger.mqh"

class CIndicatorEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   ENUM_TIMEFRAMES   m_htf;

   int               m_atrHandle;
   int               m_emaFastHandle;
   int               m_emaSlowHandle;
   int               m_adxHandle;
   int               m_htfEmaHandle;

   CLogger          *m_logger;

public:
                     CIndicatorEngine(void)
     {
      m_symbol="";
      m_tf=PERIOD_CURRENT;
      m_htf=PERIOD_H1;
      m_atrHandle=INVALID_HANDLE;
      m_emaFastHandle=INVALID_HANDLE;
      m_emaSlowHandle=INVALID_HANDLE;
      m_adxHandle=INVALID_HANDLE;
      m_htfEmaHandle=INVALID_HANDLE;
      m_logger=NULL;
     }

   bool              Init(const string symbol,
                          const ENUM_TIMEFRAMES tf,
                          const ENUM_TIMEFRAMES htf,
                          const int atrPeriod,
                          const int emaFast,
                          const int emaSlow,
                          const int adxPeriod,
                          const int htfEmaPeriod,
                          CLogger &logger)
     {
      m_symbol=symbol;
      m_tf=tf;
      m_htf=htf;
      m_logger=&logger;

      m_atrHandle=iATR(m_symbol,m_tf,atrPeriod);
      m_emaFastHandle=iMA(m_symbol,m_tf,emaFast,0,MODE_EMA,PRICE_CLOSE);
      m_emaSlowHandle=iMA(m_symbol,m_tf,emaSlow,0,MODE_EMA,PRICE_CLOSE);
      m_adxHandle=iADX(m_symbol,m_tf,adxPeriod);
      m_htfEmaHandle=iMA(m_symbol,m_htf,htfEmaPeriod,0,MODE_EMA,PRICE_CLOSE);

      if(m_atrHandle==INVALID_HANDLE || m_emaFastHandle==INVALID_HANDLE ||
         m_emaSlowHandle==INVALID_HANDLE || m_adxHandle==INVALID_HANDLE ||
         m_htfEmaHandle==INVALID_HANDLE)
        {
         logger.Warn("INDICATORS","Failed to initialize one or more indicator handles");
         return false;
        }
      return true;
     }

   void              Release(void)
     {
      if(m_atrHandle!=INVALID_HANDLE)
         IndicatorRelease(m_atrHandle);
      if(m_emaFastHandle!=INVALID_HANDLE)
         IndicatorRelease(m_emaFastHandle);
      if(m_emaSlowHandle!=INVALID_HANDLE)
         IndicatorRelease(m_emaSlowHandle);
      if(m_adxHandle!=INVALID_HANDLE)
         IndicatorRelease(m_adxHandle);
      if(m_htfEmaHandle!=INVALID_HANDLE)
         IndicatorRelease(m_htfEmaHandle);
     }

   bool              GetAtr(const int shift,double &value)
     {
      return ReadSingle(m_atrHandle,0,shift,value);
     }

   bool              GetEmaFast(const int shift,double &value)
     {
      return ReadSingle(m_emaFastHandle,0,shift,value);
     }

   bool              GetEmaSlow(const int shift,double &value)
     {
      return ReadSingle(m_emaSlowHandle,0,shift,value);
     }

   bool              GetAdxMain(const int shift,double &value)
     {
      return ReadSingle(m_adxHandle,0,shift,value);
     }

   bool              GetHTFEma(const int shift,double &value)
     {
      return ReadSingle(m_htfEmaHandle,0,shift,value);
     }

private:
   bool              ReadSingle(const int handle,const int buffer,const int shift,double &value)
     {
      double arr[1];
      if(CopyBuffer(handle,buffer,shift,1,arr)!=1)
        {
         if(m_logger!=NULL)
            m_logger.Debug("INDICATORS","CopyBuffer failed for handle="+IntegerToString(handle));
         return false;
        }
      value=arr[0];
      return true;
     }
  };

#endif
