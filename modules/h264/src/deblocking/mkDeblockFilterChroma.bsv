
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
// Deblocking Filter
//----------------------------------------------------------------------
//     
//


`include "asim/provides/common_services.bsh"
`include "soft_connections.bsh"
`include "asim/provides/fpga_components.bsh"

`include "h264_types.bsh"
`include "h264_decoder_types_parallel.bsh"
`include "h264_memory_unit.bsh"


module [CONNECTED_MODULE] mkDeblockFilterChroma( );

   Connection_Receive#(PredictionOT) infifo <- mkConnection_Receive("mkDeblocking_infifoChroma");
   Connection_Send#(DeblockFilterOT) outfifo <- mkConnection_Send("mkDeblocking_outfifoChroma"); 

   IDeblockFilter deblockFilterChroma <- mkDeblockFilterChromatic(Chroma);
 
   mkConnection(connectionToGet(infifo),deblockFilterChroma.ioin);  
   mkConnection(deblockFilterChroma.ioout,connectionToPut(outfifo));

endmodule