//
// INTEL CONFIDENTIAL
// Copyright (c) 2008 Intel Corp.  Recipient is granted a non-sublicensable 
// copyright license under Intel copyrights to copy and distribute this code 
// internally only. This code is provided "AS IS" with no support and with no 
// warranties of any kind, including warranties of MERCHANTABILITY,
// FITNESS FOR ANY PARTICULAR PURPOSE or INTELLECTUAL PROPERTY INFRINGEMENT. 
// By making any use of this code, Recipient agrees that no other licenses 
// to any Intel patents, trade secrets, copyrights or other intellectual 
// property rights are granted herein, and no other licenses shall arise by 
// estoppel, implication or by operation of law. Recipient accepts all risks 
// of use.
//

#include <stdio.h>
#include <pthread.h>
#include <time.h>
#include <errno.h>

#include "asim/provides/connected_application.h"
#include "asim/provides/stats_device.h"
#include "asim/provides/h264_output.h"
#include "mkTH.h"


using namespace std;

pthread_mutex_t CONNECTED_APPLICATION_CLASS::lock;
pthread_cond_t  CONNECTED_APPLICATION_CLASS::cond;

// constructor
CONNECTED_APPLICATION_CLASS::CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp)
{
  printf("SYSTEM_CLASS_CONSTRUCTOR\n");
  fflush(stdout);
  pthread_mutex_init(&lock, NULL);
  pthread_cond_init(&cond, NULL);
}

// destructor
CONNECTED_APPLICATION_CLASS::~CONNECTED_APPLICATION_CLASS()
{
}

void CONNECTED_APPLICATION_CLASS::EndSimulation()
{
  printf("EndSimulation Called\n");
  fflush(stdout);
  pthread_mutex_lock(&lock);
  pthread_cond_signal(&cond); 
  pthread_mutex_unlock(&lock);
  printf("EndSimulation done\n");
  fflush(stdout);
}

// main
void
CONNECTED_APPLICATION_CLASS::Main()
{
  printf("Hello world\n");
  UINT32 frameCount = 0;
  struct timespec time;
  STATS_DEVICE_SERVER_CLASS::GetInstance()->SetupStats();


  // Sleep for 30 minutes waiting for a frame, else die.
  time.tv_sec = 60*30;
  time.tv_nsec = 0;

  pthread_mutex_lock(&lock);
  while(1) {
    int result;
    result = pthread_cond_timedwait(&cond, &lock,&time);
    if(result == ETIMEDOUT) {
      // Not done yet... Check for new frames;
      if(frameCount == 
         MKFINALOUTPUTRRR_SERVER_CLASS::GetInstance()->getFrameCount()) {
	//Death by timeout
        printf("Timed out after receiving %d frames\n", frameCount);
        fflush(stdout);
        pthread_mutex_unlock(&lock);
        return;
      }
      // not locking this is okay.  It's a relative measure.
      frameCount = MKFINALOUTPUTRRR_SERVER_CLASS::GetInstance()->getFrameCount();
      // Sleep some more      
    } else if(result == 0) { //We're done
      printf("Simulation Complete, Shutting Down\n");
      fflush(stdout);
      pthread_mutex_unlock(&lock); 
      STATS_DEVICE_SERVER_CLASS::GetInstance()->DumpStats();
      STATS_DEVICE_SERVER_CLASS::GetInstance()->EmitFile();
      STARTER_DEVICE_SERVER_CLASS::GetInstance()->End(0);
      return;
    }  
  }
}
