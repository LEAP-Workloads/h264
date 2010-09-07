`include "asim/provides/soft_connections.bsh"
`include "asim/provides/processor_library.bsh"
`include "asim/provides/h264_decoder_types.bsh"

typedef Bit#(5) SlotNum;

// remember we now seperate the Luma and Chroma...
function ActionValue#(Bit#(FrameBufferSz)) calculateAddrBase(SlotNum slot);
  actionvalue
    let mbSize = 6;
    let fieldSize = 1;
    Bit#(FrameBufferSz) addrBase = (zeroExtend(slot) << fromInteger(mbSize + fieldSize + valueof(PicAreaSz)));
    if(slot != 0 && addrBase == 0)
      begin
        $display("Buffer Control Addr Base overflow! Slot: %d addr: %h",slot,addrBase);
        $finish;
      end
    $display("OutputControl Base Addr Slot: %d addr: %h",slot,addrBase);
    return addrBase;
  endactionvalue
endfunction 


typedef union tagged                
{
 void     Idle;          //not working on anything in particular
 void     OutstandingRequests;
 void     Y;
 void     U;
 void     V;
}
Outprocess deriving(Eq,Bits);

typedef union tagged {
  SlotNum Slot;
//  Bit#(PicAreaSz) FrameInMB;
  void EndOfFile;
  Bit#(PicWidthSz) SPSpic_width_in_mbs;
  PicHeight SPSpic_height_in_map_units;
} OutputControlType deriving (Bits,Eq);

// More parallel output control module


// This interface is just a simple stripped down version of 
// the search fifo
interface OutputControl;
  method Action enq(OutputControlType value);
  method Bool find(SlotNum slot);
  method Bool notEmpty();
endinterface

