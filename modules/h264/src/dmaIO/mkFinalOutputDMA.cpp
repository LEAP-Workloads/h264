#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <stdio.h>
#include <sys/stat.h>

#include "asim/rrr/service_ids.h"
#include "asim/provides/software_system.h"
#include "asim/provides/shared_memory.h"

#include "mkFinalOutputRRRWide.h"


using namespace std;

// ===== service instantiation =====
MKFINALOUTPUTRRR_SERVER_CLASS MKFINALOUTPUTRRR_SERVER_CLASS::instance;

// constructor
MKFINALOUTPUTRRR_SERVER_CLASS::MKFINALOUTPUTRRR_SERVER_CLASS()
{
    // instantiate stub
    printf("MKFINALOUTPUTRRR init called\n");
    outputFile = NULL;
    outputBuffer = NULL;
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



UINT64
MKFINALOUTPUTRRR_SERVER_CLASS::SendControl(UINT32 control, UINT64 timestamp)
{
  //printf("FinalOutput C got %llx\n",control);
  FinalOutputControl finalOutputControl = (FinalOutputControl) control;
  switch(finalOutputControl) {
    case EndOfFile:
      if(outputFile != NULL) {
        printf("FinalOutput C got EndOfFile at %llu \n",timestamp);
        fflush(outputFile);
        fclose(outputFile);
        outputFile = NULL;
        //Deadlock?
	SYSTEM_CLASS::EndSimulation();
      }
    break;

    case EndOfFrame:
      printf("FinalOutput C got EndOfFrame at %llu \n",timestamp);
    break;

    // Probably want some start of file
    case AllocateBuffer:
      if(outputBuffer == NULL) {
        assert(outputBuffer = Allocate());        
      }
      
      return outputBuffer; 
    break;

  }
  return 0;
}

