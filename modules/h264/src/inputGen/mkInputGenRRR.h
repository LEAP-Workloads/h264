#ifndef _MKINPUTGENRRR_
#define _MKINPUTGENRRR_

#include <stdio.h>
#include <sys/time.h>

#include "asim/provides/low_level_platform_interface.h"
#include "asim/provides/rrr.h"

// this module provides the RRRTest server functionalities

typedef class MKINPUTGENRRR_SERVER_CLASS* MKINPUTGENRRR_SERVER;
class MKINPUTGENRRR_SERVER_CLASS: public RRR_SERVER_CLASS,
                               public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static MKINPUTGENRRR_SERVER_CLASS instance;
    FILE *inputFile;
    int fileSize;
    int lengthRemaining;
    // server stub
    RRR_SERVER_STUB serverStub;
    

  public:
    MKINPUTGENRRR_SERVER_CLASS();
    ~MKINPUTGENRRR_SERVER_CLASS();

    // static methods
    static MKINPUTGENRRR_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();
    bool Poll();

    //
    // RRR service methods
    //
    UINT64 Initialize(UINT64 dummy);
    UINT64 GetInputData(UINT64 dummy);
};

// include server stub
#include "asim/rrr/server_stub_MKINPUTGENRRR.h"

#endif
