
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
// H264 Types
//----------------------------------------------------------------------
// 
//
//

`include "soft_connections.bsh"
`include "h264_types.bsh"

import Vector::*;
import RegFile::*;
import GetPut::*;
import FShow::*;

Integer prediction_infifo_size = 16;
Integer prediction_infifo_ITB_size = 16;
Integer prediction_predictedfifo_size = 16;
Integer interpolator_reqfifoLoad_size = 16;
Integer interpolator_reqfifoWork_size = 16;
Integer interpolator_memRespQ_size = 16;
Integer deblockFilter_infifo_size = 16;

typedef enum
{
 Pred_L0,
 Intra_4x4,
 Intra_16x16,
 NA
} MbPartPredModeType deriving(Eq,Bits);


typedef Bit#(64) Buffer;//not sure size
typedef Bit#(7) Bufcount;
Nat buffersize = 64;//not sure size



function MbPartPredModeType mbPartPredMode( MbType mbtype, Bit#(1) mbPartIdx );
   if(mbPartIdx == 1)
      begin
	 if(mbtype == P_L0_L0_16x8 || mbtype == P_L0_L0_8x16)
	    return Pred_L0;
	 else
	    return NA;
      end
   else
      begin
	 if(mbtype==P_L0_16x16 || mbtype==P_L0_L0_16x8 || mbtype==P_L0_L0_8x16 || mbtype==P_Skip)
	    return Pred_L0;
	 else if(mbtype == I_NxN)
	    return Intra_4x4;
	 else if(mbtype == P_8x8 || mbtype == P_8x8ref0 || mbtype == I_PCM )
	    return NA;
	 else
	    return Intra_16x16;
      end
endfunction


function Bit#(3) numMbPart( MbType mbtype );
   if(mbtype == P_L0_16x16  || mbtype == P_Skip)
      return 1;
   else if(mbtype == P_L0_L0_16x8 || mbtype == P_L0_L0_8x16)
      return 2;
   else if(mbtype == P_8x8 || mbtype == P_8x8ref0)
      return 4;
   else
      return 0;//should never happen
endfunction


function Bit#(3) numSubMbPart( Bit#(2) submbtype );
   if(submbtype == 0)
      return 1;
   else if(submbtype == 1 || submbtype == 2)
      return 2;
   else
      return 4;
endfunction


//----------------------------------------------------------------------
// Inter-module FIFO types
//----------------------------------------------------------------------


typedef union tagged                
{
 EntropyDecOT EDOT;

 ////Prediction Block output
 struct {Bit#(6) qpy; Bit#(6) qpc;} IBTmb_qp;//qp for luma and chroma for the current MB
 struct {Bit#(3) bShor; Bit#(3) bSver;} PBbS;//
 Vector#(4,Bit#(8)) PBoutput;//prediction+residual in regular h.264 order
}
PredictionOT deriving(Eq,Bits);
 
instance FShow#(PredictionOT);
   function Fmt fshow (PredictionOT pred);
     case (pred) matches 
       tagged IBTmb_qp .data:   return $format("IBTmb_qp"); 
       tagged PBbS .data: return $format("PBbS");
       tagged PBoutput .data: return $format("PBoutput");
       tagged EDOT .edot: return $format("EntropyDecOT: ") + fshow(edot);
     endcase
   endfunction
endinstance

typedef Bit#(TAdd#(PicWidthSz,2)) LumaCoordHor;
typedef Bit#(TAdd#(PicHeightSz,4)) LumaCoordVer;
typedef Bit#(TAdd#(PicWidthSz,1)) ChromaCoordHor;
typedef Bit#(TAdd#(PicHeightSz,3)) ChromaCoordVer;

typedef union tagged                
{
 struct {LumaCoordHor hor; LumaCoordVer ver; Bit#(32) data;} DFBLuma;
 struct {Bit#(1) uv; ChromaCoordHor hor; ChromaCoordVer ver; Bit#(32) data;} DFBChroma;
 void EndOfFrame;
 EntropyDecOT EDOT;
}
DeblockFilterOT deriving(Eq,Bits);

