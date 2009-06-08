
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
// final output implementation
//----------------------------------------------------------------------
//
//

`include "soft_connections.bsh"
`include "hasim_common.bsh"
`include "h264_types.bsh"

`include "asim/rrr/remote_client_stub_MKFINALOUTPUTRRR.bsh"

import FIFO::*;
import RegFile::*;

import Connectable::*;
import GetPut::*;

//-----------------------------------------------------------
// Final Output Module
//-----------------------------------------------------------

typedef enum {
  PicWidth = 0,
  PicHeight = 1,
  EndOfFile = 2,
  EndOfFrame = 3
} FinalOutputControl deriving (Bits,Eq);

function Bit#(64) packRRRControl(FinalOutputControl comm, Bit#(32) payload);
  return zeroExtend(payload) | zeroExtend({pack(comm),32'h0});
endfunction

typedef enum {
  SendData,
  WaitForResp
} FinalOutputState deriving (Bits,Eq);

module [HASIM_MODULE] mkFinalOutput( IFinalOutput );
   // External connections
   ClientStub_MKFINALOUTPUTRRR client_stub <- mkClientStub_MKFINALOUTPUTRRR();

   Connection_Receive#(H264OutputAddr) nextFrameRX <- mkConnection_Receive("mkFinalOutput_NextFrame");
   Connection_Send#(Bit#(1)) endOfFileTX <- mkConnection_Send("mkFinalOutput_EndOfFile");    

   FIFO#(BufferControlOT)  infifo    <- mkFIFO; 
  
   Reg#(Bit#(32)) tick_counter <- mkReg(0);
   Reg#(Bit#(32)) data_seen_counter <- mkReg(0); 
   Reg#(Bit#(32)) last_f_count <- mkReg(0);
   Reg#(Bit#(32)) f_count <- mkReg(0);
   Reg#(Bit#(32)) frameNum <- mkReg(0);
   Reg#(FinalOutputState) state <- mkReg(SendData);
   Reg#(Bit#(PicWidthSz)) picWidth <- mkReg(0);
   Reg#(Bit#(PicHeightSz)) picHeight <- mkReg(0);

   rule tick;
     tick_counter <= tick_counter + 1;
     if(tick_counter%(1<<20) == 0)
       begin
         if(last_f_count == f_count)
           begin
             $display("mkFinalOutput: Warning: no new frames, stuck at %d", last_f_count); 
           end
         else
           begin
             $display("mkFinalOutput: Feelin' fine current frames: %d", last_f_count); 
           end
         last_f_count <= f_count;
       end
   endrule

   //-----------------------------------------------------------
   // Rules

   rule finaloutData (infifo.first matches tagged YUV .xdata &&& state == SendData); 
      state <= WaitForResp;
      client_stub.makeRequest_SendOutput(zeroExtend(xdata));
      //$display("OUT %h", xdata[7:0]);
      //$display("OUT %h", xdata[15:8]);
      //$display("OUT %h", xdata[23:16]);
      //$display("OUT %h", xdata[31:24]);
      infifo.deq();
   endrule

   rule finaloutFile (infifo.first matches tagged EndOfFile &&& state == SendData); 
     $display($time,"FinalOutput: EndOfFile"); 
     $finish(0);
     infifo.deq;
     client_stub.makeRequest_SendControl(packRRRControl(EndOfFile,0));
     state <= WaitForResp;
   endrule

   rule finaloutFrame (infifo.first matches tagged EndOfFrame &&& state == SendData); 
     $display($time,"FinalOutput: EndOfFrame #%d", frameNum);
     frameNum <= frameNum + 1; 
     infifo.deq;
     client_stub.makeRequest_SendControl(packRRRControl(EndOfFrame,0));
     state <= WaitForResp;
   endrule

   rule finaloutWidth (infifo.first matches tagged SPSpic_width_in_mbs .xdata &&& state == SendData); 
     $display($time,"FinalOutput: FrameWidth #%d", xdata);
     picWidth <= xdata;
     infifo.deq;
     client_stub.makeRequest_SendControl(packRRRControl(PicWidth,zeroExtend(xdata)));
     state <= WaitForResp;
   endrule

   rule finaloutHeight (infifo.first matches tagged SPSpic_height_in_map_units .xdata  &&& state == SendData); 
     $display($time,"FinalOutput: FramHeight #%d", xdata);
     picHeight <= xdata;
     client_stub.makeRequest_SendControl(packRRRControl(PicHeight,zeroExtend(xdata)));
     state <= WaitForResp;
     infifo.deq;
   endrule

    rule eatDataResp(state == WaitForResp);
     state <= SendData;
     let resp <- client_stub.getResponse_SendOutput;
   endrule

    rule eatCommandResp(state == WaitForResp);
     state <= SendData;
     let resp <- client_stub.getResponse_SendControl;
   endrule

   interface Put ioin  = fifoToPut(infifo);

endmodule

