#ifndef _MKFINALOUTPUTRRR_
#define _MKFINALOUTPUTRRR_

#include <stdio.h>
#include <sys/time.h>

#include "asim/provides/low_level_platform_interface.h"
#include "asim/provides/rrr.h"

// this module provides the RRRTest server functionalities

typedef enum {
  PicWidth = 0,
  PicHeight = 1,
  EndOfFile = 2,
  EndOfFrame = 3
} FinalOutputControl; 



typedef class MKFINALOUTPUTRRR_SERVER_CLASS* MKFINALOUTPUTRRR_SERVER;
class MKFINALOUTPUTRRR_SERVER_CLASS: public RRR_SERVER_CLASS,
                               public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static MKFINALOUTPUTRRR_SERVER_CLASS instance;
    FILE *outputFile;

    // server stub
    RRR_SERVER_STUB serverStub;
    

  public:
    MKFINALOUTPUTRRR_SERVER_CLASS();
    ~MKFINALOUTPUTRRR_SERVER_CLASS();

    // static methods
    static MKFINALOUTPUTRRR_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();
    void Poll();

    //
    // RRR service methods
    //
    UINT64 SendControl(UINT64 dummy);
    UINT64 SendOutput(UINT64 dummy);
};



// include server stub
#include "asim/rrr/server_stub_MKFINALOUTPUTRRR.h"

#endif
