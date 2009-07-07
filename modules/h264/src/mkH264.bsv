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



`include "hasim_common.bsh"
`include "soft_connections.bsh"

// Include all of the decoder modules here
`include "h264_types.bsh"
`include "h264_entropy_decoder.bsh"
`include "h264_inverse_transform.bsh"
`include "h264_prediction.bsh"
`include "h264_deblocking.bsh"
`include "h264_buffer_control.bsh"
`include "h264_frame_buffer.bsh"
`include "h264_control.bsh"
`include "h264_nal_unwrap.bsh"
 
import Connectable::*;
import GetPut::*;
import ClientServer::*;

//(* synthesize *)
module [HASIM_MODULE] mkH264( IH264 );

   // Instantiate the modules

   INalUnwrap     nalunwrap     <- mkNalUnwrap();
   Empty   framebuffer   <- mkFrameBuffer();
   Empty    control       <- mkControl();
   Empty    entropydec    <- mkEntropyDec();
   Empty    inversetrans  <- mkInverseTrans();
   Empty    prediction    <- mkPrediction();
   Empty    deblockfilter <- mkDeblockFilter();
   Empty    buffercontrol <- mkBufferControl();

   // Soft Connection to Deblock 
   Connection_Send#(MemResp#(32)) dataMemRespQTX <- mkConnection_Send("mkDeblocking_dataMemRespQ");
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,5),32)) dataMemStoreReqQRX <- mkConnection_Receive("mkDeblocking_dataMemStoreReqQ");  
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,5),32)) dataMemLoadReqQRX <- mkConnection_Receive("mkDeblocking_dataMemLoadReqQ");
  

   //Soft Connection to Entropy
   Connection_Receive#(BufferControlOT) outfifoRX <- mkConnection_Receive("bufferControl_outfifo");

   // Interface to input generator
   interface ioin = nalunwrap.ioin;


   // Memory interfaces

 

   interface mem_clientD_data      = interface IDecoupledClient#(MemReq#(TAdd#(PicWidthSz,5),32),MemResp#(32));
                                       interface request_load = connectionToGet(dataMemLoadReqQRX);
                                       interface request_store = connectionToGet(dataMemStoreReqQRX);
                                       interface response = connectionToPut(dataMemRespQTX);
                                     endinterface;
 

   interface ioout =  connectionToGet(outfifoRX);
      
endmodule


