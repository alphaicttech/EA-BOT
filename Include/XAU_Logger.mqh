#ifndef __XAU_LOGGER_MQH__
#define __XAU_LOGGER_MQH__

class CLogger
  {
private:
   bool              m_debug;
public:
                     CLogger(void): m_debug(false) {}
   void              SetDebug(const bool enabled) { m_debug=enabled; }

   void              Info(const string scope,const string msg)
     {
      Print("[INFO][",scope,"] ",msg);
     }

   void              Warn(const string scope,const string msg)
     {
      Print("[WARN][",scope,"] ",msg);
     }

   void              Debug(const string scope,const string msg)
     {
      if(!m_debug)
         return;
      Print("[DEBUG][",scope,"] ",msg);
     }
  };

#endif
