
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
// H264 Test Bench
//----------------------------------------------------------------------
//
//

`include "low_level_platform_interface.bsh"
`include "soft_connections.bsh"
`include "hasim_common.bsh"

`include "h264_entropy_decoder.bsh"
`include "h264_inverse_transform.bsh"
`include "h264_prediction.bsh"
`include "h264_deblocking.bsh"
`include "h264_buffer_control.bsh"
`include "h264_frame_buffer.bsh"
`include "h264_decoder.bsh"
`include "h264_memory_unit.bsh"
`include "h264_types.bsh"

import Connectable::*;
import GetPut::*;
import ClientServer::*;


module [HASIM_MODULE] mkSystem (Empty);



   // Instantiate the modules

   IInputGen     inputgen    <- mkInputGen();
   IH264         h264        <- mkH264();
   IMemED#(TAdd#(PicWidthSz,1),20) memED          <- mkMemED();
   IMemED#(TAdd#(PicWidthSz,2),68) memP_intra     <- mkMemED();
   IMemED#(TAdd#(PicWidthSz,2),32) memP_inter     <- mkMemED();
   IMemEDDecoupled#(TAdd#(PicWidthSz,5),32) memD_data      <- mkMemEDDecoupled();
   IMemED#(PicWidthSz,13)          memD_parameter <- mkMemED();
   Empty   framebuffer   <- mkFrameBuffer();
   IFinalOutput   finaloutput   <- mkFinalOutput();

   Empty    entropydec    <- mkEntropyDec();
   Empty    inversetrans  <- mkInverseTrans();
   Empty    prediction    <- mkPrediction();
   Empty    deblockfilter <- mkDeblockFilter();
   Empty    buffercontrol <- mkBufferControl();
 
   // Cycle counter
   Reg#(Bit#(40)) cyclecount <- mkReg(0);

   rule countCycles ( True );
      if(cyclecount[4:0]==0) $display( "CCLCycleCount %0d", cyclecount );
      cyclecount <= cyclecount+1;
      if(cyclecount > 6000000000)
	 begin
	    $display( "ERROR mkTH: time out" );
	    $finish(0);
	 end
   endrule
   
   // Internal connections
   
   mkConnection( inputgen.ioout, h264.ioin );
   mkConnection( h264.mem_clientED, memED.mem_server );
   mkConnection( h264.mem_clientP_intra, memP_intra.mem_server );
   mkConnection( h264.mem_clientP_inter, memP_inter.mem_server );

   mkConnection( memD_data.request_store, h264.mem_clientD_data.request_store );
   mkConnection( h264.mem_clientD_data.request_load, memD_data.request_load );
   mkConnection( h264.mem_clientD_data.response, memD_data.response);

   mkConnection( h264.mem_clientD_parameter, memD_parameter.mem_server );
//   mkConnection( h264.buffer_client_load1, framebuffer.server_load1 );
//   mkConnection( h264.buffer_client_load2, framebuffer.server_load2 );
//   mkConnection( h264.buffer_client_store, framebuffer.server_store );
   mkConnection( h264.ioout, finaloutput.ioin );
   
endmodule


