
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
// top level control implementation
//----------------------------------------------------------------------
//
//

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/h264_types.bsh"

import FIFO::*;
import RegFile::*;

import Connectable::*;
import GetPut::*;

//-----------------------------------------------------------
// dummy control module
//-----------------------------------------------------------

module [CONNECTED_MODULE] mkControl();
   // External connections

   Connection_Send#(H264OutputAddr) nextFrameTX <- mkConnection_Send("mkFinalOutput_NextFrame");
   Connection_Send#(H264InputAddr) startFileTX <- mkConnection_Send("mkInput_StartFile");
   Connection_Receive#(Bit#(1)) endOfFileRX <- mkConnection_Receive("mkFinalOutput_EndOfFile");    

   // always send next frame signals
   rule sendNextFrame;
     $display("Control: sending EndOfFrame");
     nextFrameTX.send(0);
   endrule

   // consume end of file tokens
   rule receiveEndOfFile;
     $display("Control: receiving EndOfFile");
     endOfFileRX.deq;
   endrule
   
   //send start file signal
   rule sendStartFile;
     $display("Control: sending StartFile");
     startFileTX.send(0);
   endrule

endmodule


