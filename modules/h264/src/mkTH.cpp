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

#include "asim/provides/connected_application.h"

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

  pthread_mutex_lock(&lock);
  pthread_cond_wait(&cond, &lock);
  pthread_mutex_unlock(&lock);

  printf("EndSimulation Main is awake\n");
  fflush(stdout);

  //STARTER_SERVER_CLASS::GetInstance()->EndSim(1);
  // And now we are done.

  printf("EndSimulation Stats dump complete\n");
  fflush(stdout);  
}
