

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
import Connectable::*;
import GetPut::*;
import ClientServer::*;

`include "h264_types.bsh"
`include "h264_input.bsh"
`include "h264_output.bsh"
`include "h264_memory_unit.bsh"
`include "h264_decoder.bsh"

module [HASIM_MODULE] mkSystem ();

   // Instantiate the modules

   IInputGen     inputgen    <- mkInputGen();
   IFinalOutput   finaloutput   <- mkFinalOutput();
   IH264         h264        <- mkH264();
   IMemEDConnection#(TAdd#(PicWidthSz,1),20) memED          
                              <- mkMemEDConnection("mkCalc_nc_MemReqQ",
                                                   "mkCalc_nc_MemRespQ");
   IMemEDConnection#(TAdd#(PicWidthSz,2),68) memP_intra     
                              <- mkMemEDConnection("mkPrediction_intraMemReqQ",
                                                   "mkPrediction_intraMemRespQ");
   IMemEDConnection#(TAdd#(PicWidthSz,2),32) memP_inter     
                              <- mkMemEDConnection("mkPrediction_interMemReqQ",
                                                   "mkPrediction_interMemRespQ");
   IMemEDDecoupled#(TAdd#(PicWidthSz,5),32)  memD_data      <- mkMemEDDecoupled();
   IMemEDConnection#(PicWidthSz,13)          memD_parameter 
                              <- mkMemEDConnection("mkDeblocking_parameterMemReqQ",
                                                   "mkDeblocking_parameterMemRespQ");



 
   // Cycle counter
   Reg#(Bit#(40)) cyclecount <- mkReg(0);

   rule countCycles ( True );
      if(cyclecount[14:0]==0) $display( "CCLCycleCount %0d", cyclecount );
      let bscTime <- $time;
      cyclecount <= cyclecount+1; 
      if(bscTime > 6000000000)
	 begin
	    $display( $time," ERROR mkTH: time out: %d", cyclecount );
	    $finish(0);
	 end
   endrule
   
   // Internal connections
   
   mkConnection( inputgen.ioout, h264.ioin );

   mkConnection( memD_data.request_store, h264.mem_clientD_data.request_store );
   mkConnection( h264.mem_clientD_data.request_load, memD_data.request_load );
   mkConnection( h264.mem_clientD_data.response, memD_data.response);

   mkConnection( h264.ioout, finaloutput.ioin );
   
endmodule


