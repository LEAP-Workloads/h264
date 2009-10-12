
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
`include "h264_types.bsh"

import RegFile::*;
import FIFO::*;

import Connectable::*;
import GetPut::*;

`define INPUT_SIZE 10000000 

module [CONNECTED_MODULE] mkInputGen( IInputGen );

   Connection_Receive#(H264InputAddr) startFileTX <- mkConnection_Receive("mkInput_StartFile");

   RegFile#(Bit#(1), Bit#(32)) rfile2 <- mkRegFileFullLoad("input_size.hex");
   RegFile#(Bit#(27), Bit#(8)) rfile <- mkRegFileLoad("input.hex", 0, `INPUT_SIZE);
   
   FIFO#(InputGenOT) outfifo <- mkFIFO;
   Reg#(Bit#(27))    index   <- mkReg(0);
   Reg#(Bit#(27))    file_size <- mkReg(0);
   Reg#(Bool)        initialized <- mkReg(False);

   rule init (!initialized); 
      file_size <= truncate(rfile2.sub(0));
      initialized <= True;
      startFileTX.deq;
   endrule

   rule output_byte ((index < file_size) && initialized);
      outfifo.enq(DataByte (rfile.sub(index)));
      index <= index+1;
   endrule

   rule end_of_file (index == file_size && initialized);
      //$finish(0);
      index <= 0;         
      initialized <= False;
      $display("InputGen: EndOfFile at %d", file_size);
      outfifo.enq(EndOfFile);
   endrule
   
   interface Get ioout = fifoToGet(outfifo);
   







endmodule
