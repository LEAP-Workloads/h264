
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

`include "hasim_common.bsh"
`include "soft_connections.bsh"


`include "h264_types.bsh"

import RegFile::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;


//-----------------------------------------------------------
// Register file module
//-----------------------------------------------------------

interface FBRFile2;
   method Action store( Bit#(FrameBufferSz) addr, Bit#(32) data );
   method Bit#(32) load1( Bit#(FrameBufferSz) addr );
   method Bit#(32) load2( Bit#(FrameBufferSz) addr );
endinterface

module mkFBRFile2( FBRFile2 );

   RegFile#(Bit#(FrameBufferSz),Bit#(32)) rfile <- mkRegFile(0,frameBufferSize);
   
   method Action store( Bit#(FrameBufferSz) addr, Bit#(32) data );
      rfile.upd( addr, data );
   endmethod
   
   method Bit#(32) load1( Bit#(FrameBufferSz) addr );  
      return rfile.sub(addr);
   endmethod
   
   method Bit#(32) load2( Bit#(FrameBufferSz) addr );
      return rfile.sub(addr);
   endmethod
   
endmodule


//----------------------------------------------------------------------
// Main module
//----------------------------------------------------------------------


module [HASIM_MODULE] mkFrameBuffer ();

  //-----------------------------------------------------------
  // State

   FBRFile2 rfile2 <- mkFBRFile2;
   
   FIFO#(FrameBufferLoadReq)  loadReqQ1  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespQ1 <- mkFIFO();
   FIFO#(FrameBufferLoadReq)  loadReqQ2  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespQ2 <- mkFIFO();
   FIFO#(FrameBufferStoreReq) storeReqQ  <- mkFIFO();

   rule loading1 ( loadReqQ1.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
            let data = rfile2.load1(addrt);
	    loadRespQ1.enq( tagged FBLoadResp data );
	    loadReqQ1.deq();
            if(`FRAME_BUFFER_DEBUG == 1)
              begin
                $display("FrameBuffer requesting load1 %h", addrt);
                $display("FrameBuffer returns load1 %h", data);
              end
	 end
      else
	 $display( "ERROR FrameBuffer: loading1 outside range" );
   endrule
   
   rule loading2 ( loadReqQ2.first() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
            let data = rfile2.load2(addrt);
	    loadRespQ2.enq( tagged FBLoadResp data );
	    loadReqQ2.deq();
            if(`FRAME_BUFFER_DEBUG == 1)
              begin
                $display("FrameBuffer requesting load2 %h", addrt);
                $display("FrameBuffer returns load2 %h", data);
              end
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule

   rule storing ( storeReqQ.first() matches tagged FBStoreReq { addr:.addrt,data:.datat} );
      if(addrt<frameBufferSize)
	 begin
	    rfile2.store(addrt,datat);
	    storeReqQ.deq();
            $display("FrameBuffer Storing: %h to %h", {addrt,2'b00}, datat);
	 end
      else
	 $display( "ERROR FrameBuffer: storing outside range" );
   endrule
   
   rule syncing ( loadReqQ1.first() matches tagged FBEndFrameSync &&& loadReqQ2.first() matches tagged FBEndFrameSync &&& storeReqQ.first() matches tagged FBEndFrameSync);
      $display("FrameBuffer FrameSync");
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
   mkConnection(fifoToGet(loadRespQ1),connectionToPut(loadRespQ1TX));  
   mkConnection(connectionToGet(loadReqQ2RX),fifoToPut(loadReqQ2));  
   mkConnection(fifoToGet(loadRespQ2),connectionToPut(loadRespQ2TX));  
   mkConnection(connectionToGet(storeReqQRX),fifoToPut(storeReqQ));  

endmodule

