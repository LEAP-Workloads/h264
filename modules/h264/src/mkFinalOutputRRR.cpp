#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <stdio.h>
#include <sys/stat.h>

#include "asim/rrr/service_ids.h"
#include "mkFinalOutputRRR.h"

using namespace std;

// ===== service instantiation =====
MKFINALOUTPUTRRR_SERVER_CLASS MKFINALOUTPUTRRR_SERVER_CLASS::instance;

// constructor
MKFINALOUTPUTRRR_SERVER_CLASS::MKFINALOUTPUTRRR_SERVER_CLASS()
{
    // instantiate stub
    printf("MKFINALOUTPUTRRR init called\n");
    outputFile = NULL;
    serverStub = new MKFINALOUTPUTRRR_SERVER_STUB_CLASS(this);
}

// destructor
MKFINALOUTPUTRRR_SERVER_CLASS::~MKFINALOUTPUTRRR_SERVER_CLASS()
{
    Cleanup();
}

// init
void
MKFINALOUTPUTRRR_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
    parent = p;
}

// uninit
void
MKFINALOUTPUTRRR_SERVER_CLASS::Uninit()
{
    Cleanup();
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
MKFINALOUTPUTRRR_SERVER_CLASS::Cleanup()
{
    delete serverStub;
}

// poll
void
MKFINALOUTPUTRRR_SERVER_CLASS::Poll()
{
}

//
// RRR service methods
//

FinalOutputControl extractCommand(UINT64 control) {
  return (FinalOutputControl)((control >> 32) & 0xffffffff);
}


// F2HTwoWayMsg
UINT64
MKFINALOUTPUTRRR_SERVER_CLASS::SendControl(UINT64 control)
{
  printf("FinalOutput C got %llx\n",control);
  if(EndOfFrame == extractCommand(control)) {
    if(outputFile != NULL) {
      printf("FinalOutput C got EndOfFile\n");
      fclose(outputFile);
      exit(0);
    }
  }

  return 0;
}

// F2HTwoWayMsg
UINT64
MKFINALOUTPUTRRR_SERVER_CLASS::SendOutput(UINT64 dummy)
{
  int value = dummy & 0xffffffff;
  
  if(outputFile == NULL) {
    printf("SendOutput Called, opening file\n");
    outputFile = fopen("out_hw.yuv","w");
    assert(outputFile);
  }
  
  // endianess issue?
  fwrite(&value, 4, 1 , outputFile);
 
  return 0;
}
