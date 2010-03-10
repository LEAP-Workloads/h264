#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <stdio.h>
#include <sys/stat.h>

#include "asim/rrr/service_ids.h"
#include "asim/provides/connected_application.h"

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



UINT32
MKFINALOUTPUTRRR_SERVER_CLASS::SendControl(UINT32 control, UINT64 data0 ,UINT64 data1)
{
  //printf("FinalOutput C got %llx\n",control);
  FinalOutputControl finalOutputControl = (FinalOutputControl) control;
  switch(finalOutputControl) {
    case EndOfFile:
      if(outputFile != NULL) {
        printf("FinalOutput C got EndOfFile at %llu \n",data0);
        fflush(outputFile);
        fclose(outputFile);
        outputFile = NULL;
        //Deadlock?
        CONNECTED_APPLICATION_CLASS::EndSimulation();
      }
    break;

    case EndOfFrame:
      printf("FinalOutput C got EndOfFrame at %llu \n",data0);
    break;

    case Data:
      UINT64 dataArr[2];
      dataArr[0] = data0;
      dataArr[1] = data1; 
      if(outputFile == NULL) {
        //printf("SendOutput Called, opening file\n");
        outputFile = fopen("out_hw.yuv","w");
        assert(outputFile);
      }
  
      // endianess issue?
     
      fwrite(&dataArr, 16,1 , outputFile);
    break;
  }
  return 0;
}

