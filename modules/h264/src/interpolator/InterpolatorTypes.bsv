`include "asim/provides/h264_types.bsh"
`include "asim/provides/h264_decoder_types.bsh"

//-----------------------------------------------------------
// Local Datatypes
//-----------------------------------------------------------

typedef union tagged
{
 struct { Bit#(4) refIdx; Bit#(TAdd#(PicWidthSz,2)) hor; Bit#(TAdd#(PicHeightSz,4)) ver; Bit#(14) mvhor; Bit#(12) mvver; IPBlockType bt; } IPLuma;
 struct { Bit#(4) refIdx; Bit#(1) uv; Bit#(TAdd#(PicWidthSz,2)) hor; Bit#(TAdd#(PicHeightSz,3)) ver; Bit#(14) mvhor; Bit#(12) mvver; IPBlockType bt; } IPChroma;
 void EndOfFrame;
 Bit#(PicWidthSz)  PicWidth;
 Bit#(PicWidthSz)  PicHeight;
} InterpolatorIT deriving(Eq,Bits);

typedef union tagged
{
 struct { Bit#(2) xFracL; Bit#(2) yFracL; Bit#(2) offset; IPBlockType bt; } IPWLuma;
 struct { Bit#(3) xFracC; Bit#(3) yFracC; Bit#(2) offset; IPBlockType bt; } IPWChroma;
 void EndOfFrame; 
}
InterpolatorWT deriving(Eq,Bits);

//-----------------------------------------------------------
// Helper functions

function Bit#(8) clip1y10to8( Bit#(10) innum );
   if(innum[9] == 1)
      return 0;
   else if(innum[8] == 1)
      return 255;
   else
      return truncate(innum);
endfunction

interface Interpolate8to15; 
  method Bit#(15) interpolate(Bit#(8) in0, Bit#(8) in1, Bit#(8) in2, Bit#(8) in3, Bit#(8) in4, Bit#(8) in5);
endinterface

module mkInterpolate8to15 (Interpolate8to15);
   method Bit#(15) interpolate( Bit#(8) in0, Bit#(8) in1, Bit#(8) in2, Bit#(8) in3, Bit#(8) in4, Bit#(8) in5 );
     return zeroExtend(in0) - 5*zeroExtend(in1) + 20*zeroExtend(in2) + 20*zeroExtend(in3) - 5*zeroExtend(in4) + zeroExtend(in5);
   endmethod
endmodule 


interface Interpolate15to8;
  method Bit#(8) interpolate( Bit#(15) in0, Bit#(15) in1, Bit#(15) in2, Bit#(15) in3, Bit#(15) in4, Bit#(15) in5 );
endinterface

module mkInterpolate15to8 (Interpolate15to8);
  method Bit#(8) interpolate( Bit#(15) in0, Bit#(15) in1, Bit#(15) in2, Bit#(15) in3, Bit#(15) in4, Bit#(15) in5 );
    Bit#(20) temp = signExtend(in0) - 5*signExtend(in1) + 20*signExtend(in2) + 20*signExtend(in3) - 5*signExtend(in4) + signExtend(in5) + 512;
    return clip1y10to8(truncate(temp>>10));
  endmethod
endmodule






