
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
`include "asim/dict/STATS_FINAL_OUTPUT.bsh"

import FIFO::*;
import RegFile::*;

import Connectable::*;
import GetPut::*;
import Vector::*;

//-----------------------------------------------------------
// Final Output Module
//-----------------------------------------------------------

typedef enum {
  OutPicWidth = 0,
  OutPicHeight = 1,
  OutEndOfFrame = 2,
  OutEndOfFile = 3,
  OutData = 4
} FinalOutputControl deriving (Bits,Eq);

typedef 4 WordsPerBurst;


module [HASIM_MODULE] mkFinalOutput( IFinalOutput );
   // External connections
   ClientStub_MKFINALOUTPUTRRR client_stub <- mkClientStub_MKFINALOUTPUTRRR();

   Connection_Receive#(H264OutputAddr) nextFrameRX <- mkConnection_Receive("mkFinalOutput_NextFrame");
   Connection_Send#(Bit#(1)) endOfFileTX <- mkConnection_Send("mkFinalOutput_EndOfFile");    

   FIFO#(BufferControlOT)  infifo    <- mkFIFO; 
  
   Reg#(Bit#(48)) tickCounter <- mkReg(0);
   Reg#(Bit#(32)) data_seen_counter <- mkReg(0); 
   Reg#(Bit#(32)) last_f_count <- mkReg(0);
   Reg#(Bit#(32)) f_count <- mkReg(0);
   Reg#(Bit#(32)) frameNum <- mkReg(0);
   FIFO#(Bit#(0)) rrrRespQ <- mkSizedFIFO(16);
   Reg#(Bit#(PicWidthSz)) picWidth <- mkReg(0);
   Reg#(Bit#(PicHeightSz)) picHeight <- mkReg(0);
   Vector#(TSub#(WordsPerBurst,1),Reg#(Bit#(32))) dataBuffer <- replicateM(mkRegU);
   Reg#(Bit#(TAdd#(1,TLog#(WordsPerBurst)))) burstCount <- mkReg(0);

   STAT picWidthStat  <- mkStatCounter(`STATS_FINAL_OUTPUT_PIC_WIDTH);
   STAT picHeightStat <- mkStatCounter(`STATS_FINAL_OUTPUT_PIC_HEIGHT);
   STAT frameCount    <- mkStatCounter(`STATS_FINAL_OUTPUT_FRAME_COUNT);
   STAT cycleCount    <- mkStatCounter(`STATS_FINAL_OUTPUT_CYCLE_COUNT);

   rule tick;
     tickCounter <= tickCounter + 1;
     cycleCount.incr;
     if(tickCounter%(1<<20) == 0)
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

   rule finaloutDataChunk (infifo.first matches tagged YUV .xdata &&& (burstCount + 1 < fromInteger(valueof(WordsPerBurst)))); 
      infifo.deq();
      dataBuffer[burstCount] <= xdata;
      burstCount <= burstCount + 1;
   endrule   

   rule finaloutData (infifo.first matches tagged YUV .xdata &&& (burstCount + 1 == fromInteger(valueof(WordsPerBurst)))); 
      Vector#(TDiv#(WordsPerBurst,2),Bit#(64)) dataWords = 
         unpack(pack(append(readVReg(dataBuffer),replicate(xdata)))); 
      client_stub.makeRequest_SendControl(zeroExtend(pack(OutData)),
                                          dataWords[0],
                                          dataWords[1]); 
      infifo.deq();
      rrrRespQ.enq(?); 
      burstCount <= 0;
   endrule

   rule finaloutFile (infifo.first matches tagged EndOfFile); 
     $display($time,"FinalOutput: EndOfFile %h",OutEndOfFile); 
     infifo.deq;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutEndOfFile)),zeroExtend(tickCounter),?);
     rrrRespQ.enq(?);
   endrule

   rule finaloutFrame (infifo.first matches tagged EndOfFrame); 
     $display($time,"FinalOutput: EndOfFrame #%d sending(%h) %h", frameNum,OutEndOfFrame);
     frameNum <= frameNum + 1; 
     frameCount.incr;
     infifo.deq;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutEndOfFrame)),zeroExtend(tickCounter),?);
     rrrRespQ.enq(?);
   endrule

   rule finaloutWidth (infifo.first matches tagged SPSpic_width_in_mbs .xdata); 
     $display($time,"FinalOutput: FrameWidth #%d sending %h", xdata,OutPicWidth);
     picWidth <= xdata;
     infifo.deq;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutPicWidth)),zeroExtend(xdata),?);
     rrrRespQ.enq(?);
   endrule

   rule finaloutHeight (infifo.first matches tagged SPSpic_height_in_map_units .xdata); 
     $display($time,"FinalOutput: FramHeight #%d sending %h", xdata,OutPicHeight);
     picHeight <= xdata;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutPicHeight)),zeroExtend(xdata),?);
     infifo.deq;
     rrrRespQ.enq(?);
   endrule

   rule eatCommandResp;
     rrrRespQ.deq;
   endrule

   interface Put ioin  = fifoToPut(infifo);

endmodule

