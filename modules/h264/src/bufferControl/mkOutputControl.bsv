`include "asim/provides/h264_types.bsh"
`include "asim/provides/h264_decoder_types.bsh"
`include "asim/provides/processor_library.bsh"

import FIFO::*;
import Vector::*;

import Connectable::*;
import GetPut::*;
import ClientServer::*;


//Split the ouput buffer control functionality into a different module to reduce clutter.

typedef union tagged                
{
 void     Y;
 void     U;
 void     V;
}
Outprocess deriving(Eq,Bits);

interface OutputControl;
  interface Put#()
endinterface


module mkOutputControl (OutputControl);
  Reg#(Outprocess) outprocess <- mkReg(Idle);


endmodule