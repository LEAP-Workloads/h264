
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
// Input Generator implementation
//----------------------------------------------------------------------
//
//

`include "soft_connections.bsh"
`include "hasim_common.bsh"
`include "h264_types.bsh"

`include "asim/rrr/remote_client_stub_MKINPUTGENRRR.bsh"

import RegFile::*;
import FIFO::*;
import FIFOF::*;
import FShow::*;

import Connectable::*;
import GetPut::*;

instance FShow#(InputGenOT) ;
  function Fmt fshow(InputGenOT val);
    case (val) matches
      tagged DataByte .byteVal: return $format("DataByte") + fshow(byteVal);
      tagged EndOfFile        : return $format("EndOfFile");
    endcase
  endfunction
endinstance

`define INPUT_SIZE 10000000 

typedef enum {
  IssueInit,
  WaitForInit,
  DataReq,
  DataResp,
  EndOfFile
} InputState deriving (Bits,Eq);

module [HASIM_MODULE] mkInputGen( IInputGen );

   ClientStub_MKINPUTGENRRR client_stub <- mkClientStub_MKINPUTGENRRR();

   Connection_Receive#(H264InputAddr) startFileTX <- mkConnection_Receive("mkInput_StartFile");
   Reg#(InputState) state <- mkReg(IssueInit);
   Reg#(Bit#(64)) length <- mkReg(0);
   Reg#(Bit#(64)) reqs   <- mkReg(0);
   Reg#(Bit#(64)) resps  <- mkReg(0);
   Reg#(Bit#(64)) cycles <- mkReg(0);
   FIFOF#(Bit#(0)) outstandingReqs <- mkSizedFIFOF(8);
   FIFOF#(InputGenOT) buffer <- mkSizedFIFOF(8);
   FIFOF#(InputGenOT) outfifo <- mkFIFOF;
   
   rule count;
     cycles <= cycles + 1;
     if(truncate(cycles) == 18'h0) 
       begin
         $display("mkInputGenRRR ",fshow(outfifo));
       end
   endrule

   rule sendInitizationReq(state == IssueInit);
     client_stub.makeRequest_Initialize(?);
     state <= WaitForInit;
   endrule   

   rule getInitResp(state == WaitForInit);
     let lengthIn <- client_stub.getResponse_Initialize;
     length <= lengthIn;
     state <= DataReq;
     reqs <= 0;
     resps <= 0;
   endrule

   rule fetchData(reqs < length && state == DataReq); 
     client_stub.makeRequest_GetInputData(reqs);
     reqs <= reqs + 1;
     outstandingReqs.enq(?);
   endrule

   // are we done?
   rule fetchDataDone(reqs == length && state == DataReq && 
                      !outstandingReqs.notEmpty); 
     reqs <= 0;
     state <= EndOfFile;
   endrule

   rule getData; 
      Bit#(64) data <- client_stub.getResponse_GetInputData();      
      buffer.enq(tagged DataByte (truncate(data)));
   endrule 

   rule endOfFile(state == EndOfFile);     
     $display("InputGen: EndOfFile %d", length);
     outfifo.enq(tagged EndOfFile);
     state <= IssueInit;          
   endrule

   rule feedOutfifo;
     outfifo.enq(buffer.first);
     outstandingReqs.deq;
     buffer.deq;
   endrule

   interface Get ioout = fifoToGet(fifofToFifo(outfifo));
   
endmodule
