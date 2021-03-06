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

#include "asim/provides/virtual_platform.h"
#include "platforms-module.h"

typedef class CONNECTED_APPLICATION_CLASS* CONNECTED_APPLICATION;
class CONNECTED_APPLICATION_CLASS : public PLATFORMS_MODULE_CLASS 
{
  private:
    static pthread_mutex_t lock;
    static pthread_cond_t  cond;

  public:
    CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp);
    ~CONNECTED_APPLICATION_CLASS();

    static void EndSimulation();
    // main
    void Main();
};

#endif
