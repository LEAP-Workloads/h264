
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
`include "asim/provides/h264_types.bsh"
`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/provides/scratchpad_memory.bsh"
`include "asim/provides/stats_service.bsh"
`include "asim/provides/mem_services.bsh"
`include "asim/provides/librl_bsv_cache.bsh"
`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/fpga_components.bsh"
`include "asim/provides/project_common.bsh"
`include "asim/provides/platform_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/common_utility_devices.bsh"





import RegFile::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;



//----------------------------------------------------------------------
// Main module
//----------------------------------------------------------------------

typedef enum { 
  Q1,
  Q2
} Queue deriving (Bits,Eq);

module [CONNECTED_MODULE] mkFrameBuffer();

  //-----------------------------------------------------------
  // State
  MEMORY_IFC#(FrameBufferAddr, FrameBufferData) memory <- mkScratchpad(`VDEV_SCRATCH_FRAME_BUFFER, SCRATCHPAD_CACHED);

  
   FIFO#(Queue) qFIFO <- mkSizedFIFO(32);
   FIFO#(Bit#(0)) allocateSpace1 <- mkSizedFIFO(32);
   FIFO#(Bit#(0)) allocateSpace2 <- mkSizedFIFO(32);
   FIFO#(FrameBufferLoadReq)  loadReqQ1  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespQ1 <- mkSizedFIFO(32);
   FIFO#(FrameBufferLoadReq)  loadReqQ2  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespQ2 <- mkSizedFIFO(32);
   FIFO#(FrameBufferStoreReq) storeReqQ  <- mkFIFO();

  
   rule loading1 ( loadReqQ1.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
	    loadReqQ1.deq();
            memory.readReq(addrt);
            allocateSpace1.enq(?);
            qFIFO.enq(Q1);  
            $display("FrameBuffer requesting load1 %h", addrt);
	 end
      else
	 $display( "ERROR FrameBuffer: loading1 outside range" );
   endrule

   rule loadingResp1(qFIFO.first == Q1);   
     FrameBufferData value <- memory.readRsp;
     loadRespQ1.enq( tagged FBLoadResp value );
     $display("FrameBuffer load1 loaded %h", value);
     qFIFO.deq;
   endrule 

   rule loading2 ( loadReqQ2.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
	    loadReqQ2.deq();
            qFIFO.enq(Q2);  
            memory.readReq(addrt); 
            allocateSpace2.enq(?);   
            $display("FrameBuffer requesting load2 %h", addrt);
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule

   rule loadingResp2(qFIFO.first == Q2);   
     FrameBufferData value <- memory.readRsp;
     loadRespQ2.enq( tagged FBLoadResp value );
     qFIFO.deq;
     $display("FrameBuffer load2 loaded %h", value);
   endrule

   rule storing ( storeReqQ.first() matches tagged FBStoreReq { addr:.addrt,data:.datat} );
      if(addrt<frameBufferSize)
	 begin
            // Wasteful, but forces coherence
            memory.write(addrt,datat);  
	    storeReqQ.deq();
            $display("FrameBuffer Storing: %h to %h", addrt, datat);
	 end
      else
	 $display( "ERROR FrameBuffer: storing outside range" );
   endrule
   // may need to sync with end of pipeline
   rule syncing ( loadReqQ1.first() matches tagged FBEndFrameSync &&& loadReqQ2.first() matches tagged FBEndFrameSync &&& storeReqQ.first() matches tagged FBEndFrameSync);
      $display("FrameBuffer Frame Sync");
      loadReqQ1.deq();
      loadReqQ2.deq();
      storeReqQ.deq();
   endrule


   Connection_Receive#(FrameBufferLoadReq) loadReqQ1RX <- mkConnection_Receive("frameBuffer_LoadReqQ1");
   Connection_Send#(FrameBufferLoadResp) loadRespQ1TX <- mkConnection_Send("frameBuffer_LoadRespQ1");
   Connection_Receive#(FrameBufferLoadReq) loadReqQ2RX <- mkConnection_Receive("frameBuffer_LoadReqQ2");
   Connection_Send#(FrameBufferLoadResp) loadRespQ2TX <- mkConnection_Send("frameBuffer_LoadRespQ2");
   Connection_Receive#(FrameBufferStoreReq) storeReqQRX <- mkConnection_Receive("frameBuffer_StoreReqQ");
   mkConnection(connectionToGet(loadReqQ1RX),fifoToPut(loadReqQ1));  

   rule dumpData1;
     loadRespQ1TX.send(loadRespQ1.first);
     loadRespQ1.deq;
     allocateSpace1.deq;
   endrule

   mkConnection(connectionToGet(loadReqQ2RX),fifoToPut(loadReqQ2));  

   rule dumpData2;
     loadRespQ2TX.send(loadRespQ2.first);
     loadRespQ2.deq;
     allocateSpace2.deq;
   endrule

   mkConnection(connectionToGet(storeReqQRX),fifoToPut(storeReqQ));  

endmodule

