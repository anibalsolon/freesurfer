#ifndef Broadcaster_h
#define Broadcaster_h

#include <list>
#include <string>
#include "Listener.h"

class Broadcaster {

 public:

  Broadcaster ();
  ~Broadcaster ();

  void AddListener ( Listener* iListener );
  void RemoveListener ( Listener* iListener );

  virtual void SendBroadcast ( std::string iMessage, void* iData );

 protected:

  std::list<Listener*> mlListeners;
};


#endif
