
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

//**********************************************************************
// Frame Buffer
//----------------------------------------------------------------------
//
//
//


`include "asim/provides/soft_connections.bsh"
`include "h264_types.bsh"
`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/dict/STATS_FRAME_BUFFER.bsh"
`include "scratchpad_memory.bsh"
`include "asim/provides/librl_bsv_cache.bsh"
`include "asim/provides/project_common.bsh"
`include "asim/provides/common_service.bsh"
`include "asim/provides/common_utility_devices.bsh"


import RegFile::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;
import FrameBufferStats::*;

//----------------------------------------------------------------------
// Main module
//----------------------------------------------------------------------

module [CONNECTED_MODULE] mkFrameBuffer();
  //-----------------------------------------------------------
  // State
  
  // we curry the cache constructors here.

  // The raster order reader does not need a large cache, stats, and other such things
  String rasterCacheFilename = "RasterCacheDebug";

  DEBUG_FILE rasterCacheLog <- (`SCRATCHPAD_DEBUG == 1)?
                               mkDebugFile(rasterCacheFilename):
                               mkDebugFileNull(rasterCacheFilename); 

  RL_CACHE_STATS rasterStats <- mkBasicRLCacheStats(
                                 `STATS_FRAME_BUFFER_RASTER_CACHE_LOAD_HIT,
                                 `STATS_FRAME_BUFFER_RASTER_CACHE_LOAD_MISS,
                                 `STATS_FRAME_BUFFER_RASTER_CACHE_STORE_HIT,
                                 `STATS_FRAME_BUFFER_RASTER_CACHE_STORE_MISS);
  
  NumTypeParam#(2048) rasterCacheSize = 0;
  function CONNECTED_MODULE#(RL_DM_CACHE#(addr_t,mem_t,ref_t))
               mkRasterCache(RL_DM_CACHE_SOURCE_DATA#(addr_t,mem_t,ref_t) source)
                 provisos(Bits#(addr_t, addr_t_sz),
                          Bits#(mem_t, mem_t_sz),
                          Bits#(ref_t, ref_t_sz))
                = mkCacheDirectMapped(source,rasterCacheSize,
                                      False,rasterStats,rasterCacheLog);
     
 
  //the inter cache does need stats and a large cache.
  String interCacheFilename = "InterCacheDebug";

  DEBUG_FILE interCacheLog <- (`SCRATCHPAD_DEBUG == 1)?
                               mkDebugFile(interCacheFilename):
                               mkDebugFileNull(interCacheFilename); 

  RL_CACHE_STATS interStats <- mkBasicRLCacheStats(
                                 `STATS_FRAME_BUFFER_INTER_CACHE_LOAD_HIT,
                                 `STATS_FRAME_BUFFER_INTER_CACHE_LOAD_MISS,
                                 `STATS_FRAME_BUFFER_INTER_CACHE_STORE_HIT,
                                 `STATS_FRAME_BUFFER_INTER_CACHE_STORE_MISS);
  
  NumTypeParam#(8192) interCacheSize = 0;
  function CONNECTED_MODULE#(RL_DM_CACHE#(addr_t,mem_t,ref_t)) 
               mkInterCache(RL_DM_CACHE_SOURCE_DATA#(addr_t,mem_t,ref_t) source)
                 provisos(Bits#(addr_t, addr_t_sz),
                          Bits#(mem_t, mem_t_sz),
                          Bits#(ref_t, ref_t_sz))
            = mkCacheDirectMapped(source,interCacheSize,
                                  False,interStats,interCacheLog);

  // Make constructor list here
  let constructors = cons(mkRasterCache, cons(mkInterCache,nil));

  MEMORY_MULTI_READ_IFC#(2,FrameBufferContainerAddr, 
                         Vector#(2,FrameBufferData)) memory <- 
      mkMultiReadMultiCacheScratchpad(`VDEV_SCRATCH_FRAME_BUFFER, 
                                      replicate(2),
                                      constructors);
  
   // Instantiate frame buffer state. Some of these fifos may be largish
   FIFO#(Bit#(1)) allocateSpace1 <- mkSizedFIFO(32);
   FIFO#(Bit#(1)) allocateSpace2 <- mkSizedFIFO(32);
   FIFO#(Bit#(FrameBufferSz)) addrs1 <- mkSizedFIFO(32);
   FIFO#(Bit#(FrameBufferSz)) addrs2 <- mkSizedFIFO(32);
   FIFOF#(FrameBufferLoadReq)  loadReqQ1  <- mkSizedFIFOF(16);
   FIFO#(Vector#(2,FrameBufferData)) loadRespQ1 <- mkSizedFIFO(32);
   FIFOF#(FrameBufferLoadReq)  loadReqQ2  <- mkSizedFIFOF(16);
   FIFO#(Vector#(2,FrameBufferData)) loadRespQ2 <- mkSizedFIFO(32);
   FIFOF#(FrameBufferStoreReq) storeReqQ  <- mkSizedFIFOF(16);
   Reg#(Bool) loadReg <- mkReg(True);
   Reg#(FrameBufferData) registeredData <- mkRegU;

   // Make some stats
   STAT statLoadQ1Full  <- mkStatCounter(`STATS_FRAME_BUFFER_LOAD_Q1_FULL);
   STAT statLoadQ1Empty <- mkStatCounter(`STATS_FRAME_BUFFER_LOAD_Q1_EMPTY);
   STAT statLoadQ2Full  <- mkStatCounter(`STATS_FRAME_BUFFER_LOAD_Q2_FULL);
   STAT statLoadQ2Empty <- mkStatCounter(`STATS_FRAME_BUFFER_LOAD_Q2_EMPTY);
   STAT statStoreQFull  <- mkStatCounter(`STATS_FRAME_BUFFER_STORE_Q_FULL);
   STAT statStoreQEmpty <- mkStatCounter(`STATS_FRAME_BUFFER_STORE_Q_EMPTY);


 
   rule checkLoadQ1Full(!loadReqQ1.notFull);
     statLoadQ1Full.incr(); 
   endrule

   rule checkLoadQ1Empty(!loadReqQ1.notEmpty);
     statLoadQ1Empty.incr(); 
   endrule

   rule checkLoadQ2Full(!loadReqQ2.notFull);
     statLoadQ2Full.incr(); 
   endrule

   rule checkLoadQ2Empty(!loadReqQ2.notEmpty);
     statLoadQ2Empty.incr(); 
   endrule
  
   rule checkStoreQFull(!storeReqQ.notFull);
     statLoadQ1Full.incr(); 
   endrule

   rule checkStoreEmpty(!storeReqQ.notEmpty);
     statStoreQEmpty.incr(); 
   endrule



   rule loading1 ( loadReqQ1.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
	    loadReqQ1.deq();
            addrs1.enq(addrt);
            memory.readPorts[0].readReq(truncateLSB(addrt));
            allocateSpace1.enq(truncate(addrt));
            if(`FRAME_BUFFER_DEBUG == 1)
              begin
                $display("FrameBuffer requesting load1 %h", addrt);
              end
	 end
      else
	 $display( "ERROR FrameBuffer: loading1 outside range" );
   endrule

   rule loadingResp1;   
     let value <- memory.readPorts[0].readRsp;
     loadRespQ1.enq(value);
     if(`FRAME_BUFFER_DEBUG == 1)
       begin
         $display("FrameBuffer load1 loaded %h", value);
       end
   endrule 

   rule loading2 ( loadReqQ2.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
	    loadReqQ2.deq();
            addrs2.enq(addrt);
            memory.readPorts[1].readReq(truncateLSB(addrt)); 
            allocateSpace2.enq(truncate(addrt));   
            if(`FRAME_BUFFER_DEBUG == 1)
              begin
                $display("FrameBuffer requesting load2 %h", addrt);
              end
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule

   rule loadingResp2;   
     let value <- memory.readPorts[1].readRsp;
     loadRespQ2.enq(value);
     if(`FRAME_BUFFER_DEBUG == 1)
       begin
         $display("FrameBuffer load2 loaded %h", value);
       end
   endrule

   // feed requests from store Q into coalescer
   rule storingRegister ( storeReqQ.first() matches tagged FBStoreReq { addr:.addrt,data:.datat} &&& loadReg);
      if(addrt<frameBufferSize)
	 begin
            if(truncate(addrt) != 1'b0)
              begin 
                $display( "ERROR FrameBuffer: register store requests out of order: %h to %h",datat,addrt );
              end
            loadReg <= False;
            registeredData <= datat;
            
	    storeReqQ.deq();
            if(`FRAME_BUFFER_DEBUG == 1)
              begin
                $display("FrameBuffer Storing: %h to %h", addrt, datat);
              end
	 end
      else
	 $display( "ERROR FrameBuffer: storing outside range" );
   endrule


   rule storingDispatch ( storeReqQ.first() matches tagged FBStoreReq { addr:.addrt,data:.datat} &&& !loadReg);
      if(addrt<frameBufferSize)
	 begin
            if(truncate(addrt) != 1'b1)
              begin 
                $display( "ERROR FrameBuffer: output store requests out of order: %h to %h",datat,addrt );
              end
            // Wasteful, but forces coherence
            loadReg <= True;
            Vector#(2,FrameBufferData) dataVec = newVector;
            dataVec[1] = datat;
            dataVec[0] = registeredData;
            registeredData <= datat;
            memory.write(truncateLSB(addrt),dataVec);           
	    storeReqQ.deq();
            if(`FRAME_BUFFER_DEBUG == 1)
              begin
                $display("FrameBuffer Storing: %h to %h", addrt, dataVec);
              end
	 end
      else
	 $display( "ERROR FrameBuffer: storing outside range" );
   endrule

   // may need to sync with end of pipeline
   // Does this have any meaning in a coherent system?
   rule syncing ( loadReqQ1.first() matches tagged FBEndFrameSync &&& loadReqQ2.first() matches tagged FBEndFrameSync &&& storeReqQ.first() matches tagged FBEndFrameSync);
      if(`FRAME_BUFFER_DEBUG == 1)
        begin
          $display("FrameBuffer FrameSync");
        end
      loadReqQ1.deq();
      loadReqQ2.deq();
      storeReqQ.deq();
   endrule


   Connection_Receive#(FrameBufferLoadReq) loadReqQ1RX <- mkConnection_Receive("frameBuffer_LoadReqQ1");
   Connection_Send#(FrameBufferLoadResp) loadRespQ1TX <- mkConnection_Send("frameBuffer_LoadRespQ1");
   Connection_Receive#(FrameBufferLoadReq) loadReqQ2RX <- mkConnection_Receive("frameBuffer_LoadReqQ2");
   Connection_Send#(FrameBufferLoadResp) loadRespQ2TX <- mkConnection_Send("frameBuffer_LoadRespQ2");
   Connection_Receive#(FrameBufferStoreReq) storeReqQRX <- mkConnection_Receive("frameBuffer_StoreReqQ");
   mkConnection(connectionToGet(loadReqQ1RX),fifoToPut(fifofToFifo(loadReqQ1)));  

   rule dumpData1;
     Vector#(2,FrameBufferData) dataVec = loadRespQ1.first;
     loadRespQ1TX.send(tagged FBLoadResp dataVec[allocateSpace1.first]);
     loadRespQ1.deq;
     allocateSpace1.deq;
     addrs1.deq;
     if(`FRAME_BUFFER_DEBUG == 1)
       begin
         $display("FrameBuffer returns load1 %h %h", addrs1.first, dataVec[allocateSpace1.first]);
       end
   endrule

   mkConnection(connectionToGet(loadReqQ2RX),fifoToPut(fifofToFifo(loadReqQ2)));  

   rule dumpData2;
     Vector#(2,FrameBufferData) dataVec = loadRespQ2.first;
     loadRespQ2TX.send(tagged FBLoadResp dataVec[allocateSpace2.first]);
     loadRespQ2.deq;
     addrs2.deq;
     allocateSpace2.deq;
     if(`FRAME_BUFFER_DEBUG == 1)
       begin
         $display("FrameBuffer returns load2 %h %h", addrs2.first, dataVec[allocateSpace2.first]);
       end
   endrule

   mkConnection(connectionToGet(storeReqQRX),fifoToPut(fifofToFifo(storeReqQ)));  

endmodule

