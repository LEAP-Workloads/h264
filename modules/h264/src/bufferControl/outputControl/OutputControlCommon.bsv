`include "asim/provides/soft_connections.bsh"
`include "asim/provides/processor_library.bsh"
`include "asim/provides/h264_decoder_types.bsh"

typedef Bit#(5) SlotNum;

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
  Bit#(PicHeightSz) SPSpic_height_in_map_units;
} OutputControlType deriving (Bits,Eq);

// More parallel output control module


// This interface is just a simple stripped down version of 
// the search fifo
interface OutputControl;
  method Action enq(OutputControlType value);
  method Bool find(SlotNum slot);
  method Bool notEmpty();
endinterface

