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
import FIFO::*;


//-----------------------------------------------------------
// Register file module
//-----------------------------------------------------------

interface FBRFile2;
   method Action store( Bit#(FrameBufferSz) addr, Bit#(32) data );
   method Bit#(32) load1( Bit#(FrameBufferSz) addr );
   method Bit#(32) load2( Bit#(FrameBufferSz) addr );
   method Bit#(32) load3( Bit#(FrameBufferSz) addr );
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

   method Bit#(32) load3( Bit#(FrameBufferSz) addr );
      return rfile.sub(addr);
   endmethod
   
endmodule


//----------------------------------------------------------------------
// Main module
//----------------------------------------------------------------------

module [HASIM_MODULE] mkFrameBuffer( );

  //-----------------------------------------------------------
  // State

   Connection_Receive#(FrameBufferLoadReq) loadReqQ1 <- mkConnection_Receive("frameBuffer_LoadReqQ1");
   Connection_Send#(FrameBufferLoadResp) loadRespQ1 <- mkConnection_Send("frameBuffer_LoadRespQ1");
   Connection_Receive#(FrameBufferLoadReq) loadReqQ2 <- mkConnection_Receive("frameBuffer_LoadReqQLuma");
   Connection_Send#(FrameBufferLoadResp) loadRespQ2 <- mkConnection_Send("frameBuffer_LoadRespQLuma");
   Connection_Receive#(FrameBufferLoadReq) loadReqQ3 <- mkConnection_Receive("frameBuffer_LoadReqQChroma");
   Connection_Send#(FrameBufferLoadResp) loadRespQ3 <- mkConnection_Send("frameBuffer_LoadRespQChroma");
   Connection_Receive#(FrameBufferStoreReq) storeReqQ <- mkConnection_Receive("frameBuffer_StoreReqQ");

   FBRFile2 rfile2 <- mkFBRFile2;
   

   rule loading1 ( loadReqQ1.receive() matches tagged FBLoadReq .addrt );
      if(addrt<frameBufferSize)
	 begin
	    loadRespQ1.send( tagged FBLoadResp rfile2.load1(addrt) );
	    loadReqQ1.deq();
	 end
      else
	 $display( "ERROR FrameBuffer: loading1 outside range" );
   endrule
   
   rule loading2 ( loadReqQ2.receive() matches tagged FBLoadReq .addrt );
      $display("Trace FrameBuffer interLumaReq");
      if(addrt<frameBufferSize)
	 begin
	    loadRespQ2.send( tagged FBLoadResp rfile2.load2(addrt) );
	    loadReqQ2.deq();
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule

   rule loading3 ( loadReqQ3.receive() matches tagged FBLoadReq .addrt );
      $display("Trace FrameBuffer interChromaReq");
      if(addrt<frameBufferSize)
	 begin
	    loadRespQ3.send( tagged FBLoadResp rfile2.load3(addrt) );
	    loadReqQ3.deq();
	 end
      else
	 $display( "ERROR FrameBuffer: loading2 outside range" );
   endrule


   rule storing ( storeReqQ.receive() matches tagged FBStoreReq { addr:.addrt,data:.datat} );
      if(addrt<frameBufferSize)
	 begin
	    rfile2.store(addrt,datat);
	    storeReqQ.deq();
	 end
      else
	 $display( "ERROR FrameBuffer: storing outside range" );
   endrule
   
   rule syncing ( loadReqQ1.receive() matches tagged FBEndFrameSync &&& loadReqQ2.receive() matches tagged FBEndFrameSync &&& 
                  loadReqQ3.receive() matches tagged FBEndFrameSync &&& storeReqQ.receive() matches tagged FBEndFrameSync);
      $display("Trace FrameBuffer: EndOfFrame Sync");
      loadReqQ1.deq();
      loadReqQ2.deq();
      loadReqQ3.deq();
      storeReqQ.deq();
   endrule

   rule loadReq1Blocked;
     $display("Trace FrameBuffer: check LoadQ1 %h", loadReqQ1.receive);     
   endrule
   
   rule loadReq2Blocked;
     $display("Trace FrameBuffer: check LoadQ2 %h", loadReqQ2.receive);     
   endrule
   
   rule loadReq3Blocked;
     $display("Trace FrameBuffer: check LoadQ3 %h", loadReqQ3.receive);     
   endrule
   


endmodule

