
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

`include "platform_interface.bsh"
`include "hasim_common.bsh"
`include "soft_connections.bsh"
`include "h264_types.bsh"
`include "asim/dict/VDEV_SCRATCH.bsh"
`include "scratchpad_memory.bsh"




import RegFile::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;
import Vector::*;


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
  
  MEMORY_MULTI_READ_IFC#(2,FrameBufferAddr, FrameBufferData) memory <- 
      mkMultiReadMultiCacheScratchpad(`VDEV_SCRATCH_FRAME_BUFFER, 
                                      replicate(0),
                                      replicate(mkCacheDirectMapped));
  
  
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
            memory.readPorts[0].readReq(addrt);
            allocateSpace1.enq(?);
            $display("FrameBuffer requesting load1 %h", addrt);
	 end
      else
	 $display( "ERROR FrameBuffer: loading1 outside range" );
   endrule

   rule loadingResp1;   
     FrameBufferData value <- memory.readPorts[0].readRsp;
     loadRespQ1.enq( tagged FBLoadResp value );
     $display("FrameBuffer load1 loaded %h", value);
   endrule 

   rule loading2 ( loadReqQ2.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
	    loadReqQ2.deq();
            memory.readPorts[1].readReq(addrt); 
            allocateSpace2.enq(?);   
            $display("FrameBuffer requesting load2 %h", addrt);
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule

   rule loadingResp2;   
     FrameBufferData value <- memory.readPorts[1].readRsp;
     loadRespQ2.enq( tagged FBLoadResp value );
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

