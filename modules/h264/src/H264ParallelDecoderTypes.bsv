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

`include "h264_types.bsh"

import Vector::*;
import RegFile::*;
import FShow::*;

Integer entropyDec_infifo_size = 2;
Integer inverseTrans_infifo_size = 8;
Integer prediction_infifo_size = 4;
Integer prediction_infifo_ITB_size = 16;
Integer prediction_predictedfifo_size = 16;
Integer interpolator_reqfifoLoad_size = 4;
Integer interpolator_reqfifoWork_size = 8;
Integer interpolator_memRespQ_size = 4;
Integer deblockFilter_infifo_size = 4;
Integer bufferControl_infifo_size = 2;

//----------------------------------------------------------------------
// Inter-module FIFO types
//----------------------------------------------------------------------

typedef enum 
{
 Chroma = 1,
 Luma = 0
}
ChromaFlag deriving(Eq,Bits);

typedef union tagged                
{
  EntropyDecOT EDOT;

 ////Prediction Block output
 struct {Bit#(6) qpy; Bit#(6) qpc;} IBTmb_qp;//qp for luma and chroma for the current MB
 struct {Bit#(3) bShor; Bit#(3) bSver; Bit#(4) blockNum;} PBbS;//
 Tuple2#(ChromaFlag,Vector#(4,Bit#(8))) PBoutput;//prediction+residual in regular h.264 order
 
}
PredictionOT deriving(Eq,Bits);

instance FShow#(PredictionOT);
   function Fmt fshow (PredictionOT data);
     case (data) matches 
       tagged IBTmb_qp .data:   return $format("IBTmb_qp"); 
       tagged PBbS .data: return $format("PBbS");
       tagged PBoutput .data: return $format("PBoutput");
       tagged EDOT .edot: return $format("EntropyDecOT: ") + fshow(edot);
     endcase
   endfunction
endinstance


typedef union tagged                
{
 struct {Bit#(TAdd#(PicWidthSz,2)) hor; Bit#(TAdd#(PicHeightSz,4)) ver; Bit#(32) data;} DFBLuma;
 struct {Bit#(1) uv; Bit#(TAdd#(PicWidthSz,1)) hor; Bit#(TAdd#(PicHeightSz,3)) ver; Bit#(32) data;} DFBChroma;
 void EndOfFrame;
 EntropyDecOT EDOT;
}
DeblockFilterOT deriving(Eq,Bits);

instance FShow#(DeblockFilterOT);
   function Fmt fshow (DeblockFilterOT data);
     case (data) matches 
       tagged DFBLuma .data:   return $format("DFBLuma"); 
       tagged DFBChroma .data: return $format("DFBChroma");
       tagged EndOfFrame: return $format("EndOfFrame");
       tagged EDOT .edot: return $format("EntropyDecOT: ") + fshow(edot);
     endcase
   endfunction
endinstance







