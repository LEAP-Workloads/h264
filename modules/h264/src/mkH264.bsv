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
// H264 Main Module
//----------------------------------------------------------------------
//
//



`include "asim/provides/common_services.bsh"
`include "asim/provides/soft_connections.bsh"

// Include all of the decoder modules here
`include "asim/provides/h264_types.bsh"
`include "asim/provides/h264_entropy_decoder.bsh"
`include "asim/provides/h264_inverse_transform.bsh"
`include "asim/provides/h264_prediction.bsh"
`include "asim/provides/h264_deblocking.bsh"
`include "asim/provides/h264_buffer_control.bsh"
`include "asim/provides/h264_control.bsh"
`include "asim/provides/h264_nal_unwrap.bsh"
 
import Connectable::*;
import GetPut::*;
import ClientServer::*;

//(* synthesize *)
module [CONNECTED_MODULE] mkH264( IH264 );

   // Instantiate the modules

   INalUnwrap     nalunwrap     <- mkNalUnwrap();
   Empty    control       <- mkControl();
   Empty    entropydec    <- mkEntropyDec();
   Empty    inversetrans  <- mkInverseTrans();
   Empty    prediction    <- mkPrediction();
   Empty    deblockfilter <- mkDeblockFilter();
   Empty    buffercontrol <- mkBufferControl();

   // Soft Connection to Deblock 

   //Soft Connection to Entropy
   Connection_Receive#(BufferControlOT) outfifoRX <- mkConnection_Receive("bufferControl_outfifo");

   // Interface to input generator
   interface ioin = nalunwrap.ioin;



   interface ioout =  connectionToGet(outfifoRX);
      
endmodule


