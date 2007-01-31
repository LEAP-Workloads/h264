//**********************************************************************
// H264 Test Bench
//----------------------------------------------------------------------
//
//

package mkTH;

import H264Types::*;
import IMemED::*;
import IFrameBuffer::*;
import IInputGen::*;
import IH264::*;
import IVgaController::*;
import IFPGAInterface::*;
import IEDKBRAM::*;
import mkMemED::*;
import mkFrameBuffer::*;
import mkInputGen::*;
import mkH264::*;
import mkVgaController::*;
import BRAM::*;
import mkRoundRobinMemScheduler::*;
import mkSRAMMemController::*;
import IMemClient::*;
import IMemController::*;
import IMemScheduler::*;
import ISRAMWires::*;
import Connectable::*;
import GetPut::*;
import ClientServer::*;

(* synthesize *)
module mkth( IFPGAInterface );

   // Instantiate the modules

   IInputGen     inputgen    <- mkInputGen();
   IH264         h264        <- mkH264();
   IMemED#(TAdd#(PicWidthSz,1),20) memED          <- mkMemED();
   IMemED#(TAdd#(PicWidthSz,2),68) memP_intra     <- mkMemED();
   IMemED#(TAdd#(PicWidthSz,2),32) memP_inter     <- mkMemED();
   IMemED#(TAdd#(PicWidthSz,5),32) memD_data      <- mkMemED();
   IMemED#(PicWidthSz,13)          memD_parameter <- mkMemED();
   IFrameBuffer   framebuffer   <- mkFrameBuffer();

   // Cycle counter
   Reg#(Bit#(32)) cyclecount <- mkReg(0);

   rule countCycles ( True );
      if(cyclecount[4:0]==0) $display( "CCLCycleCount %0d", cyclecount );
      cyclecount <= cyclecount+1;
      if(cyclecount > 60000000)
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
   mkConnection( h264.mem_clientD_data, memD_data.mem_server );
   mkConnection( h264.mem_clientD_parameter, memD_parameter.mem_server );
   mkConnection( h264.buffer_client_load, framebuffer.server_load );
   mkConnection( h264.buffer_client_store, framebuffer.server_store );

  interface IEDKBRAM bram_controller = inputgen.bram_interface;
  interface IVgaController vga_controller = h264.vga_controller;
  interface ISRAMWires  sram_controller = h264.sram_controller;
  interface ISRAMWires  sram_controller2 = framebuffer.sram_controller;
   
endmodule

endpackage
