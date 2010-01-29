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

`include "asim/provides/platform_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/soft_connections.bsh"
`include "asim/provides/scratchpad_memory.bsh"
`include "asim/provides/librl_bsv_cache.bsh"

module [CONNECTED_MODULE] mkBasicScratchpadCacheStats#(
                            STATS_DICT_TYPE idLoadHit,
                            STATS_DICT_TYPE idLoadMiss,
                            STATS_DICT_TYPE idWriteHit,
                            STATS_DICT_TYPE idWriteMiss,
                            RL_CACHE_STATS stats)
    // interface:
    ();

    STAT statLoadHit <- mkStatCounter(idLoadHit);
    STAT statLoadMiss <- mkStatCounter(idLoadMiss);
    STAT statWriteHit <- mkStatCounter(idWriteHit);
    STAT statWriteMiss <- mkStatCounter(idWriteMiss);
    
    rule readHit (stats.readHit());
      statLoadHit.incr();
    endrule

    rule readMiss (stats.readMiss());
      statLoadMiss.incr();
    endrule

    rule writeHit (stats.writeHit());
      statWriteHit.incr();
    endrule

    rule writeMiss (stats.writeMiss());
      statWriteMiss.incr();
    endrule
endmodule


module [CONNECTED_MODULE] mkNullScratchpadCacheStats#(RL_CACHE_STATS stats)
    // interface:
    ();


endmodule