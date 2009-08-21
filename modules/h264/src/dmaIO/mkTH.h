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

// possibly use include paths to hide existing modules?

#ifndef __MKTH_SYSTEM__
#define __MKTH_SYSTEM__

#include <stdio.h>
#include <pthread.h>

#include "platforms-module.h"
#include "asim/provides/remote_memory.h"

typedef class SYSTEM_CLASS* SYSTEM;
class SYSTEM_CLASS
{
  private:
    static pthread_mutex_t lock;
    static pthread_cond_t  cond;

  public:
    SYSTEM_CLASS();
    ~SYSTEM_CLASS();

    static void EndSimulation();
    // main
    void Main();
};

#endif
