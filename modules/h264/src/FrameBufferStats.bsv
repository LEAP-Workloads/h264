// The MIT License

// Copyright (c) 2006-2007 Massachusetts Institute of Technology

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

`include "asim/provides/platform_interface.bsh"
`include "asim/provides/hasim_common.bsh"
`include "asim/provides/soft_connections.bsh"
`include "scratchpad_memory.bsh"
`include "asim/provides/librl_bsv_cache.bsh"

module [HASIM_MODULE] mkBasicRLCacheStats#(STATS_DICT_TYPE idLoadHit,
                            STATS_DICT_TYPE idLoadMiss,
                            STATS_DICT_TYPE idWriteHit,
                            STATS_DICT_TYPE idWriteMiss)
    // interface:
    (RL_CACHE_STATS);

    STAT statLoadHit <- mkStatCounter(idLoadHit);
    STAT statLoadMiss <- mkStatCounter(idLoadMiss);
    STAT statWriteHit <- mkStatCounter(idWriteHit);
    STAT statWriteMiss <- mkStatCounter(idWriteMiss);
    
    method Action readHit();
      statLoadHit.incr;
    endmethod

    method Action readMiss();
      statLoadMiss.incr;
    endmethod

    method Action writeHit();
      statWriteHit.incr;
    endmethod

    method Action writeMiss();
      statWriteMiss.incr;
    endmethod

    method Action invalEntry();
    endmethod

    method Action dirtyEntryFlush();
    endmethod

    method Action forceInvalLine();
    endmethod
endmodule