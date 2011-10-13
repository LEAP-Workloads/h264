#include "asim/syntax.h"
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <stdio.h>
#include <sys/stat.h>

#include "asim/rrr/service_ids.h"
#include "mkInputGenRRR.h"

using namespace std;

// ===== service instantiation =====
MKINPUTGENRRR_SERVER_CLASS MKINPUTGENRRR_SERVER_CLASS::instance;

// constructor
MKINPUTGENRRR_SERVER_CLASS::MKINPUTGENRRR_SERVER_CLASS()
{
    // instantiate stub
    //printf("MKINPUTGENRRR init called\n");
    inputFile = NULL;
    serverStub = new MKINPUTGENRRR_SERVER_STUB_CLASS(this);
}

// destructor
MKINPUTGENRRR_SERVER_CLASS::~MKINPUTGENRRR_SERVER_CLASS()
{
    Cleanup();
}

// init
void
MKINPUTGENRRR_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
    parent = p;
}

// uninit
void
MKINPUTGENRRR_SERVER_CLASS::Uninit()
{
    Cleanup();
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
MKINPUTGENRRR_SERVER_CLASS::Cleanup()
{
    delete serverStub;
}

// poll
bool
MKINPUTGENRRR_SERVER_CLASS::Poll()
{
  return false;
}

//
// RRR service methods
//

// F2HTwoWayMsg
UINT64
MKINPUTGENRRR_SERVER_CLASS::Initialize(UINT64 dummy)
{
   struct stat stats;
   //printf("MKINPUTGENRRR Initialize called\n");
    inputFile = fopen("input.264","r");
    assert(inputFile);
    // tabulate file size
    fstat(fileno(inputFile), &stats);
    printf("Size: %d",  stats.st_size);
    fileSize = stats.st_size;
    lengthRemaining = stats.st_size;
    return stats.st_size;
}

// F2HTwoWayMsg
UINT64
MKINPUTGENRRR_SERVER_CLASS::GetInputData(UINT64 dummy)
{
    int value;
    //printf("MKINPUTGENRRR GetInputData called %d\n", dummy);
    if(inputFile == NULL) {
      return 0;
    }

    int count = 0;
    UINT64 data = 0;

    if(lengthRemaining > sizeof(data)) {
      fread(&data,1,sizeof(data),inputFile);
      lengthRemaining = lengthRemaining - sizeof(data);
    } else {
      fread(&data,1,lengthRemaining,inputFile);
      lengthRemaining = 0;
      rewind(inputFile);
    }

    return data;

}
