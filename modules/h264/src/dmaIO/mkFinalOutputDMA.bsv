
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

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/hasim_common.bsh"
`include "asim/provides/h264_types.bsh"
`include "asim/provides/remote_memory.bsh"
`include "asim/provides/shared_memory.bsh"
`include "asim/provides/physical_platform.bsh"

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
  OutData = 4,
  OutAllocateBuffer = 5
} FinalOutputControl deriving (Bits,Eq);


// need to mark whether we are expecting to get a buffer pointer
typedef enum {
  NoResp,
  Pointer
} FinalOutputHostResp deriving (Bits,Eq);  

typedef 4 WordsPerBurst;

module [HASIM_MODULE] mkFinalOutput( IFinalOutput );
   // External connections
   ClientStub_MKFINALOUTPUTRRR client_stub <- mkClientStub_MKFINALOUTPUTRRR();

   Connection_Receive#(H264OutputAddr) nextFrameRX <- mkConnection_Receive("mkFinalOutput_NextFrame");
   Connection_Send#(Bit#(1)) endOfFileTX <- mkConnection_Send("mkFinalOutput_EndOfFile");    

    //hooks to shared mem
    Connection_Send#(SHARED_MEMORY_REQUEST) link_shmem_req        <- mkConnection_Send("vdev_shmem_req");
    // Not used at present. Ideally, we'd want to send this to the front side
    Connection_Receive#(SHARED_MEMORY_DATA)       link_shmem_data_read  <- mkConnection_Receive("vdev_shmem_data_read");
    Connection_Send#(SHARED_MEMORY_DATA)    link_shmem_data_write <- mkConnection_Send("vdev_shmem_data_write");
  


   FIFO#(BufferControlOT)  infifo    <- mkFIFO; 
  
   Reg#(Bit#(48)) tickCounter <- mkReg(0);
   Reg#(Bit#(32)) data_seen_counter <- mkReg(0); 
   Reg#(Bit#(32)) last_f_count <- mkReg(0);
   Reg#(Bit#(32)) f_count <- mkReg(0);
   Reg#(Bit#(32)) frameNum <- mkReg(0);
   FIFO#(FinalOutputHostResp) rrrRespQ <- mkSizedFIFO(16);
   Reg#(Bit#(PicWidthSz)) picWidth <- mkReg(0);
   Reg#(Bit#(PicHeightSz)) picHeight <- mkReg(0);
   Reg#(Bit#(TAdd#(1,TLog#(WordsPerBurst)))) burstCount <- mkReg(0);

   Reg#(Bool) allocatedBuffer <- mkReg(False);
   FIFO#(SHARED_MEMORY_ADDRESS) bufferPtrs <- mkFIFO();

   STAT picWidthStat  <- mkStatCounter(`STATS_FINAL_OUTPUT_PIC_WIDTH);
   STAT picHeightStat <- mkStatCounter(`STATS_FINAL_OUTPUT_PIC_HEIGHT);
   STAT frameCount    <- mkStatCounter(`STATS_FINAL_OUTPUT_FRAME_COUNT);
   STAT cycleCount    <- mkStatCounter(`STATS_FINAL_OUTPUT_CYCLE_COUNT);

   /// Build the dma engine

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
   
   // for now send exactly one buffer req
   rule allocateBufferReq (!allocatedBuffer);
     allocatedBuffer <= True;
     rrrRespQ.enq(Pointer);   
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutAllocateBuffer)),zeroExtend(tickCounter));     
   endrule


   rule finaloutDataChunk (infifo.first matches tagged YUV .xdata &&& (burstCount > 0)); 
      infifo.deq();
      if(burstCount + 1 == fromInteger(valueof(WordsPerBurst)))
        begin
          // eventually, deq the buffer pointer here
          burstCount <= 0;
        end
      else
        begin
          burstCount <= burstCount + 1;
        end

     link_shmem_data_write.send(zeroExtend(xdata));
   endrule   

   rule finaloutData (infifo.first matches tagged YUV .xdata &&& (burstCount == 0)); 
     infifo.deq();
     // Introduce dummy dep on bufferPtrs.first
     $display("Buffer first %d", bufferPtrs.first);
     link_shmem_data_write.send(zeroExtend(xdata));
     SHARED_MEMORY_REQ_INFO req =  SHARED_MEMORY_REQ_INFO{len: fromInteger(valueof(WordsPerBurst)),addr: 0};
     link_shmem_req.send(tagged SHARED_MEMORY_WRITE req);         
     burstCount <= burstCount + 1;
   endrule

   rule finaloutFile (infifo.first matches tagged EndOfFile); 
     $display($time,"FinalOutput: EndOfFile %h",OutEndOfFile); 
     infifo.deq;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutEndOfFile)),zeroExtend(tickCounter));
     rrrRespQ.enq(NoResp);
   endrule

   rule finaloutFrame (infifo.first matches tagged EndOfFrame); 
     $display($time,"FinalOutput: EndOfFrame #%d sending(%h) %h", frameNum,OutEndOfFrame);
     frameNum <= frameNum + 1; 
     frameCount.incr;
     infifo.deq;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutEndOfFrame)),zeroExtend(tickCounter));
     rrrRespQ.enq(NoResp);
   endrule

   rule finaloutWidth (infifo.first matches tagged SPSpic_width_in_mbs .xdata); 
     $display($time,"FinalOutput: FrameWidth #%d sending %h", xdata,OutPicWidth);
     picWidth <= xdata;
     infifo.deq;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutPicWidth)),zeroExtend(xdata));
     rrrRespQ.enq(NoResp);
   endrule

   rule finaloutHeight (infifo.first matches tagged SPSpic_height_in_map_units .xdata); 
     $display($time,"FinalOutput: FramHeight #%d sending %h", xdata,OutPicHeight);
     picHeight <= xdata;
     client_stub.makeRequest_SendControl(zeroExtend(pack(OutPicHeight)),zeroExtend(xdata));
     infifo.deq;
     rrrRespQ.enq(NoResp);
   endrule

   rule setPtr(rrrRespQ.first == Pointer);
     rrrRespQ.deq;
     let resp <- client_stub.getResponse_SendControl;
     if(rrrRespQ.first == Pointer) 
       begin
         bufferPtrs.enq(unpack(truncate(resp)));
       end     
   endrule

   rule eatResp(rrrRespQ.first == NoResp);
     rrrRespQ.deq;
     let resp <- client_stub.getResponse_SendControl;
   endrule

   interface Put ioin  = fifoToPut(infifo);

endmodule

