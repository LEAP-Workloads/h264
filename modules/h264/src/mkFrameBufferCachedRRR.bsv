
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
`include "scratchpad_memory.bsh"

//`include "asim/rrr/service_ids.bsh"



import RegFile::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;
import LoadCache::*;


//----------------------------------------------------------------------
// Main module
//----------------------------------------------------------------------

typedef enum { 
  Q1,
  Q2
} Queue deriving (Bits,Eq);



module [HASIM_MODULE] mkFrameBuffer();

  //-----------------------------------------------------------
  // State

   Connection_Client#(SCRATCHPAD_MEM_REQUEST, SCRATCHPAD_MEM_VALUE) link_memory <- mkConnection_Client("vdev_memory");
   Connection_Receive#(SCRATCHPAD_MEM_ADDRESS)              link_memory_inval <- mkConnection_Receive("vdev_memory_invalidate");

   FIFO#(Queue) qFIFO <- mkFIFO();
   FIFO#(FrameBufferLoadReq)  loadReqQ1  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespQ1 <- mkFIFO();
   FIFO#(FrameBufferLoadReq)  loadReqQ2  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespQ2 <- mkFIFO();
   FIFO#(FrameBufferStoreReq) storeReqQ  <- mkFIFO();

   LoadCache loadCache1 <- mkLoadCache("loadCache1");
   LoadCache loadCache2 <- mkLoadCache("loadCache2");   

   rule linkDeq;
     $display("Frame Buffer invalidate");
     link_memory_inval.deq();
   endrule

   rule loading1 ( loadReqQ1.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
            qFIFO.enq(Q1);
	    loadReqQ1.deq();
            link_memory.makeReq(tagged SCRATCHPAD_MEM_LOAD zeroExtend({addrt,2'b00}));  
	 end
      else
	 $display( "ERROR FrameBuffer: loading1 outside range" );
   endrule

   rule loadingResp1(qFIFO.first == Q1);   
     qFIFO.deq;
     SCRATCHPAD_MEM_VALUE value = link_memory.getResp();
     link_memory.deq();
     loadRespQ1.enq( tagged FBLoadResp value );
     $display("FrameBuffer loaded %h", value);
   endrule

   rule loading2 ( loadReqQ2.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
            qFIFO.enq(Q2);
	    loadReqQ2.deq();
            link_memory.makeReq(tagged SCRATCHPAD_MEM_LOAD zeroExtend({addrt,2'b00}));  
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule

   rule loadingResp2(qFIFO.first == Q2);   
     qFIFO.deq;
     SCRATCHPAD_MEM_VALUE value = link_memory.getResp();
     link_memory.deq();
     loadRespQ2.enq( tagged FBLoadResp value );
     $display("FrameBuffer loaded %h", value);
   endrule

   rule storing ( storeReqQ.first() matches tagged FBStoreReq { addr:.addrt,data:.datat} );
      if(addrt<frameBufferSize)
	 begin
            link_memory.makeReq(tagged SCRATCHPAD_MEM_STORE {addr:zeroExtend({addrt,2'b00}),val:datat});  
	    storeReqQ.deq();
            $display("FrameBuffer Storing: %h to %h", {addrt,2'b00}, datat);
	 end
      else
	 $display( "ERROR FrameBuffer: storing outside range" );
   endrule
   
   rule syncing ( loadReqQ1.first() matches tagged FBEndFrameSync &&& loadReqQ2.first() matches tagged FBEndFrameSync &&& storeReqQ.first() matches tagged FBEndFrameSync);
      loadReqQ1.deq();
      loadReqQ2.deq();
      storeReqQ.deq();
   endrule


   Connection_Receive#(FrameBufferLoadReq) loadReqQ1RX <- mkConnection_Receive("frameBuffer_LoadReqQ1");
   Connection_Send#(FrameBufferLoadResp) loadRespQ1TX <- mkConnection_Send("frameBuffer_LoadRespQ1");
   Connection_Receive#(FrameBufferLoadReq) loadReqQ2RX <- mkConnection_Receive("frameBuffer_LoadReqQ2");
   Connection_Send#(FrameBufferLoadResp) loadRespQ2TX <- mkConnection_Send("frameBuffer_LoadRespQ2");
   Connection_Receive#(FrameBufferStoreReq) storeReqQRX <- mkConnection_Receive("frameBuffer_StoreReqQ");

   // hookup the cache
  

   mkConnection(connectionToGet(loadReqQ1RX),loadCache1.loadReqIn.request);  
   mkConnection(loadCache1.loadReqIn.response,connectionToPut(loadRespQ1TX));  
   mkConnection(loadCache1.loadReqOut.request,fifoToPut(loadReqQ1));  
   mkConnection(fifoToGet(loadRespQ1),loadCache1.loadReqOut.response);  
   
   mkConnection(connectionToGet(loadReqQ2RX),loadCache2.loadReqIn.request);  
   mkConnection(loadCache2.loadReqIn.response,connectionToPut(loadRespQ2TX));  
   mkConnection(loadCache2.loadReqOut.request,fifoToPut(loadReqQ2));  
   mkConnection(fifoToGet(loadRespQ2),loadCache2.loadReqOut.response);  

 
   mkConnection(connectionToGet(storeReqQRX),fifoToPut(storeReqQ));  

endmodule

