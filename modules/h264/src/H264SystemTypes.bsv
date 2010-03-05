
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

import Vector::*;
import RegFile::*;
import GetPut::*;
import FShow::*;

typedef 7   PicWidthSz;//number of bits to represent the horizontal position of a MB
typedef 7   PicHeightSz;//number of bits to represent the vertical position of a MB
typedef 14  PicAreaSz;//number of bits to represent the 2D position of a MB (max 16)
Bit#(PicWidthSz) maxPicWidthInMB=127;//(2^PicWidthSz)-1

Bit#(PicAreaSz) maxPicAreaInMB=14'b10000000000000;
typedef 25  FrameBufferSz;//number of bits to address the frame buffer (5+PicAreaSz+6)
typedef 16  MaxRefFrames;//max number of frames in the frame buffer
Bit#(5) maxRefFrames=16;//max number of frames in the frame buffer
Bit#(FrameBufferSz) frameBufferSize=25'b0110110000000000000000000;//size of frame buffer ((maxRefFrames+2)*maxPicAreaInMB*1.5*64)

Integer entropyDec_infifo_size = 2;
Integer inverseTrans_infifo_size = 8;
Integer bufferControl_infifo_size = 2;

//-----------------------------------------------------------
// 1 read port register file module

interface RFile1#(type idx_t, type d_t);
   method Action upd(idx_t x1, d_t x2);
   method d_t sub(idx_t x1);
endinterface

module mkRFile1#( idx_t lo, idx_t hi ) ( RFile1#(idx_t, d_t) )
   provisos (Bits#(idx_t, si),Bits#(d_t, sa));
   RegFile#(idx_t,d_t) rf <- mkRegFile(lo,hi);
   method Action upd( idx_t index, d_t data );
      rf.upd( index, data );
   endmethod
   method d_t sub( idx_t index );
      return rf.sub(index);
   endmethod
endmodule
   
module mkRFile1Full( RFile1#(idx_t, d_t) )
   provisos (Bits#(idx_t, si),Bits#(d_t, sa),Bounded#(idx_t) );
   RegFile#(idx_t,d_t) rf <- mkRegFileFull();
   method Action upd( idx_t index, d_t data );
      rf.upd( index, data );
   endmethod
   method d_t sub( idx_t index );
      return rf.sub(index);
   endmethod
endmodule


//-----------------------------------------------------------
// Do not fire module

interface DoNotFire;
   method Action doNotFire();
endinterface

module mkDoNotFire( DoNotFire );
   method Action doNotFire() if(False);
      noAction;
   endmethod   
endmodule



// Intra/Inter Types

typedef union tagged                
{
 void    NewUnit;
 Bit#(8) RbspByte;
 void    EndOfFile;
}
NalUnwrapOT deriving(Eq,Bits);


typedef union tagged                
{
 Bit#(8)  NewUnit;

 ////Picture Parameter Set
 Bit#(8)  PPSpic_parameter_set_id;//ue 0 to 255
 Bit#(7)  PPSpic_init_qp;//se+26 0 to 51
 Bit#(7)  PPSpic_init_qs;//se+26 0 to 51
 Bit#(5)  PPSchroma_qp_index_offset;//se -12 to 12

 ////Slice Header
 Bit#(7)  SHslice_qp_delta;//se -51 to 51

 ////macroblock layer
 MbType   SDMmbtype;//ue ->process-> MbType
 Bit#(7)  SDMmb_qp_delta;//se -26 to 25
 ////residual data (cavlc output in reverse order (high frequency first))
 struct {Bit#(13) level; Bit#(5) zeros;} SDMRcoeffLevelPlusZeros;//one non-zero coeff level followed by # of consecutive zeros
 Bit#(5)  SDMRcoeffLevelZeros;//# of consecutive zeros
}
EntropyDecOT_InverseTrans deriving(Eq,Bits);


typedef union tagged                
{
 void ITBcoeffLevelZeros;//16 consecutive zeros
 Vector#(4,Bit#(10)) ITBresidual;//residual data in regular h.264 order
 struct {Bit#(6) qpy; Bit#(6) qpc;} IBTmb_qp;//qp for luma and chroma for the current MB
}
InverseTransOT deriving(Eq,Bits);

// Pass the new frame size along with the update width height
typedef struct {
  Bit#(PicWidthSz) width;
  Bit#(PicAreaSz) area;
} PicWidth deriving (Bits,Eq);

typedef struct {
  Bit#(PicWidthSz) height;
  Bit#(PicAreaSz) area;
} PicHeight deriving (Bits,Eq);

typedef union tagged                
{
 Bit#(8)  NewUnit;

 ////Sequence Parameter Set
 Bit#(5)  SPSseq_parameter_set_id;//ue 0 to 31
 Bit#(5)  SPSlog2_max_frame_num;//ue+4 4 to 16
 Bit#(2)  SPSpic_order_cnt_type;//ue 0 to 2
 Bit#(5)  SPSlog2_max_pic_order_cnt_lsb;//ue+4 4 to 16
 Bit#(1)  SPSdelta_pic_order_always_zero_flag;//u(1)
 Bit#(32) SPSoffset_for_non_ref_pic;//se -2^31 to 2^31-1
 Bit#(32) SPSoffset_for_top_to_bottom_field;//se -2^31 to 2^31-1
 Bit#(8)  SPSnum_ref_frames_in_pic_order_cnt_cycle;//ue 0 to 255
 Bit#(32) SPSoffset_for_ref_frame;//se -2^31 to 2^31-1
 Bit#(5)  SPSnum_ref_frames;//ue 0 to MaxDpbSize (depends on Level)
 Bit#(1)  SPSgaps_in_frame_num_allowed_flag;//u(1)
 Bit#(PicWidthSz) SPSpic_width_in_mbs;//ue+1 1 to ?
 Bit#(PicHeightSz) SPSpic_height_in_map_units;//ue+1 1 to ?
 // Use this to get rid of subsequent calculations downstream
 
//// Bit#(1)  SPSframe_mbs_only_flag//u(1) (=1 for baseline)
 Bit#(1)  SPSdirect_8x8_inference_flag;//u(1)
 Bit#(1)  SPSframe_cropping_flag;//u(1)
 Bit#(16) SPSframe_crop_left_offset;//ue 0 to ?
 Bit#(16) SPSframe_crop_right_offset;//ue 0 to ?
 Bit#(16) SPSframe_crop_top_offset;//ue 0 to ?
 Bit#(16) SPSframe_crop_bottom_offset;//ue 0 to ?

 ////Picture Parameter Set
 Bit#(8)  PPSpic_parameter_set_id;//ue 0 to 255
 Bit#(5)  PPSseq_parameter_set_id;//ue 0 to 31
//// Bit#(1)  PPSentropy_coding_mode_flag//u(1) (=0 for baseline)
 Bit#(1)  PPSpic_order_present_flag;//u(1)
//// Bit#(4)  PPSnum_slice_groups;//ue+1 1 to 8 (=1 for main)
////some info if PPSnum_slice_groups>1 (not in main)
 Bit#(5)  PPSnum_ref_idx_l0_active;//ue+1 1 to 32 (16 for frame mb)
 Bit#(5)  PPSnum_ref_idx_l1_active;//ue+1 1 to 32 (16 for frame mb)
//// Bit#(1)  PPSweighted_pred_flag;//u(1) (=0 for baseline)
//// Bit#(2)  PPSweighted_bipred_flag;//u(2) (=0 for baseline)
//////// Bit#(7)  PPSpic_init_qp;//se+26 0 to 51
//////// Bit#(7)  PPSpic_init_qs;//se+26 0 to 51
//////// Bit#(5)  PPSchroma_qp_index_offset;//se -12 to 12
 Bit#(1)  PPSdeblocking_filter_control_present_flag;//u(1)
 Bit#(1)  PPSconstrained_intra_pred_flag;//u(1)
//// Bit#(1)  PPSredundant_pic_cnt_present_flag;//u(1) (=0 for main)

 ////Slice Header
 Bit#(PicAreaSz) SHfirst_mb_in_slice;//ue 0 to PicSizeInMbs-1
 Bit#(4)  SHslice_type;//ue 0 to 9
 Bit#(8)  SHpic_parameter_set_id;//ue 0 to 255
 Bit#(16) SHframe_num;//u(log2_max_frame_num)
 Bit#(16) SHidr_pic_id;//ue 0 to 65535
 Bit#(16) SHpic_order_cnt_lsb;//u(log2_max_pic_order_cnt_lsb)
 Bit#(32) SHdelta_pic_order_cnt_bottom;//se -2^31 to 2^31-1
 Bit#(32) SHdelta_pic_order_cnt0;//se -2^31 to 2^31-1
 Bit#(32) SHdelta_pic_order_cnt1;//se -2^31 to 2^31-1
 Bit#(1)  SHnum_ref_idx_active_override_flag;//u(1)
 Bit#(5)  SHnum_ref_idx_l0_active;//ue+1 1 to 32 (16 for frame mb)
 ////reference picture list reordering
 Bit#(1)  SHRref_pic_list_reordering_flag_l0;//u(1)
 Bit#(2)  SHRreordering_of_pic_nums_idc;//ue 0 to 3
 Bit#(17) SHRabs_diff_pic_num;//ue 1 to MaxPicNum
 Bit#(5)  SHRlong_term_pic_num;//ue 0 to ?
 ////decoded reference picture marking
 Bit#(1)  SHDno_output_of_prior_pics_flag;//u(1)
 Bit#(1)  SHDlong_term_reference_flag;//u(1)
 Bit#(1)  SHDadaptive_ref_pic_marking_mode_flag;//u(1)
 Bit#(3)  SHDmemory_management_control_operation;//ue 0 to 6
 Bit#(17) SHDdifference_of_pic_nums;//ue 1 to MaxPicNum
 Bit#(5)  SHDlong_term_pic_num;//ue 0 to 32 (16 for frame mb)
 Bit#(5)  SHDlong_term_frame_idx;//ue 0 to MaxLongTermFrameIdx
 Bit#(5)  SHDmax_long_term_frame_idx_plus1;//ue 0 to num_ref_frames (0 to 16)
 ////Slice Header (continued)
//////// Bit#(7)  SHslice_qp_delta;//se -51 to 51
 Bit#(2)  SHdisable_deblocking_filter_idc;//ue 0 to 2
 Bit#(5)  SHslice_alpha_c0_offset;//se*2 -12 to 12
 Bit#(5)  SHslice_beta_offset;//se*2 -12 to 12

 ////Slice Data
 Bit#(PicAreaSz) SDmb_skip_run;//ue 0 to PicSizeInMbs
//// Bit#(PicAreaSz) SDcurrMbAddr;//ue ->process-> 0 to PicSizeInMbs
 ////macroblock layer
 MbType   SDMmbtype;//ue ->process-> MbType
 Bit#(8)  SDMpcm_sample_luma;//ue 0 to 255
 Bit#(8)  SDMpcm_sample_chroma;//ue 0 to 255
//// Bit#(6)  SDMcoded_block_pattern;//me
//////// Bit#(7)  SDMmb_qp_delta;//se -26 to 25
 ////macroblock prediction
// Bit#(1)  SDMMprev_intra4x4_pred_mode_flag;//u(1)
 Bit#(4)  SDMMrem_intra4x4_pred_mode;//(SDMMprev_intra4x4_pred_mode_flag ? 4'b1000 : {1'b0,u(3)})
 Bit#(2)  SDMMintra_chroma_pred_mode;//ue 0 to 3
 Bit#(5)  SDMMref_idx_l0;//te 0 to num_ref_idx_active_minus1
 Bit#(16) SDMMmvd_l0;//se ? to ? (see Annex A)
 ////sub-macroblock prediction
 Bit#(2)  SDMSsub_mb_type;//ue 0 to 3
 Bit#(5)  SDMSref_idx_l0;//te 0 to num_ref_idx_active_minus1
 Bit#(16) SDMSmvd_l0;//se ? to ? (see Annex A)
 ////residual data
//////// Bit#(13) SDMRcoeffLevel;//cavlc output in reverse order (high frequency first)
//////// Bit#(5)  SDMRcoeffLevelZeros;//# of consecutive zeros (also used for ITBresidual)

 ////Prediction Block output

 //// various delimiters
 Bit#(3)  AUDPrimaryPicType;
 void     EndOfSequence;
 void     EndOfStream;
 void     EndOfFile;
}
EntropyDecOT deriving(Eq,Bits);


instance FShow#(EntropyDecOT);
   function Fmt fshow (EntropyDecOT data);
     case (data) matches 
       tagged NewUnit .data:  return $format("NewUnit");  
       tagged SPSseq_parameter_set_id .data:  return $format("SPSseq_parameter_set_id"); 
       tagged SPSlog2_max_frame_num .data:  return $format("SPSlog2_max_frame_num");  
       tagged SPSpic_order_cnt_type .data:  return $format("SPSpic_order_cnt_type");  
       tagged SPSlog2_max_pic_order_cnt_lsb .data:  return $format("SPSlog2_max_pic_order_cnt_lsb");  
       tagged SPSdelta_pic_order_always_zero_flag .data:  return $format("SPSdelta_pic_order_always_zero_flag");         
       tagged SPSoffset_for_non_ref_pic .data:  return $format("SPSoffset_for_non_ref_pic");         
       tagged SPSoffset_for_top_to_bottom_field .data:  return $format("SPSoffset_for_top_to_bottom_field");         
       tagged SPSnum_ref_frames_in_pic_order_cnt_cycle .data:  return $format("SPSnum_ref_frames_in_pic_order_cnt_cycle");         
       tagged SPSoffset_for_ref_frame .data:  return $format("SPSoffset_for_ref_frame");         
       tagged SPSnum_ref_frames .data:  return $format("SPSnum_ref_frames");         
       tagged SPSgaps_in_frame_num_allowed_flag .data:  return $format("SPSgaps_in_frame_num_allowed_flag");         
       tagged SPSpic_width_in_mbs .data:  return $format("SPSpic_width_in_mbs");         
       tagged SPSpic_height_in_map_units .data:  return $format("SPSpic_height_in_map_units");         
       tagged SPSdirect_8x8_inference_flag .data:  return $format("SPSdirect_8x8_inference_flag");         
       tagged SPSframe_cropping_flag .data:  return $format("SPSframe_cropping_flag");         
       tagged SPSframe_crop_left_offset .data:  return $format("SPSframe_crop_left_offset");         
       tagged SPSframe_crop_right_offset .data:  return $format("SPSframe_crop_right_offset");         
       tagged SPSframe_crop_top_offset .data:  return $format("SPSframe_crop_top_offset");         
       tagged SPSframe_crop_bottom_offset .data:  return $format("SPSframe_crop_bottom_offset");         
       tagged PPSpic_parameter_set_id .data:  return $format("PPSpic_parameter_set_id");         
       tagged PPSseq_parameter_set_id .data:  return $format("PPSseq_parameter_set_id");         
       tagged PPSpic_order_present_flag .data:  return $format("PPSpic_order_present_flag");         
       tagged PPSnum_ref_idx_l0_active .data:  return $format("PPSnum_ref_idx_l0_active");         
       tagged PPSnum_ref_idx_l1_active .data:  return $format("PPSnum_ref_idx_l1_active");         
       tagged PPSdeblocking_filter_control_present_flag .data:  return $format("PPSdeblocking_filter_control_present_flag");         
       tagged PPSconstrained_intra_pred_flag .data:  return $format("PPSconstrained_intra_pred_flag");         
       tagged SHfirst_mb_in_slice .data:  return $format("SHfirst_mb_in_slice");         
       tagged SHslice_type .data:  return $format("SHslice_type");         
       tagged SHpic_parameter_set_id .data:  return $format("SHpic_parameter_set_id");         
       tagged SHframe_num .data:  return $format("SHframe_num");         
       tagged SHidr_pic_id .data:  return $format("SHidr_pic_id");         
       tagged SHpic_order_cnt_lsb .data:  return $format("SHpic_order_cnt_lsb");         
       tagged SHdelta_pic_order_cnt_bottom .data:  return $format("SHdelta_pic_order_cnt_bottom");         
       tagged SHdelta_pic_order_cnt0 .data:  return $format("SHdelta_pic_order_cnt0");         
       tagged SHdelta_pic_order_cnt1 .data:  return $format("SHdelta_pic_order_cnt1");         
       tagged SHnum_ref_idx_active_override_flag .data:  return $format("SHnum_ref_idx_active_override_flag");         
       tagged SHnum_ref_idx_l0_active .data:  return $format("SHnum_ref_idx_l0_active");         
       tagged SHRref_pic_list_reordering_flag_l0 .data:  return $format("SHRref_pic_list_reordering_flag_l0");         
       tagged SHRreordering_of_pic_nums_idc .data:  return $format("SHRreordering_of_pic_nums_idc");         
       tagged SHRabs_diff_pic_num .data:  return $format("SHRabs_diff_pic_num");         
       tagged SHRlong_term_pic_num .data:  return $format("SHRlong_term_pic_num");         
       tagged SHDno_output_of_prior_pics_flag .data:  return $format("SHDno_output_of_prior_pics_flag");         
       tagged SHDlong_term_reference_flag .data:  return $format("SHDlong_term_reference_flag");         
       tagged SHDadaptive_ref_pic_marking_mode_flag .data:  return $format("SHDadaptive_ref_pic_marking_mode_flag");         
       tagged SHDmemory_management_control_operation .data:  return $format("SHDmemory_management_control_operation");         
       tagged SHDdifference_of_pic_nums .data:  return $format("SHDdifference_of_pic_nums");         
       tagged SHDlong_term_frame_idx .data:  return $format("SHDlong_term_frame_idx");         
       tagged SHDmax_long_term_frame_idx_plus1 .data:  return $format("SHDmax_long_term_frame_idx_plus1");         
       tagged SHdisable_deblocking_filter_idc .data:  return $format("SHdisable_deblocking_filter_idc");         
       tagged SHslice_alpha_c0_offset .data:  return $format("SHslice_alpha_c0_offset");         
       tagged SHslice_beta_offset .data:  return $format("SHslice_beta_offset");         
       tagged SDmb_skip_run .data:  return $format("SDmb_skip_run");         
       tagged SDMmbtype .data:  return $format("SDMmbtype");         
       tagged SDMpcm_sample_luma .data:  return $format("SDMpcm_sample_luma");         
       tagged SDMpcm_sample_chroma .data:  return $format("SDMpcm_sample_chroma");         
       tagged SDMMrem_intra4x4_pred_mode .data:  return $format("SDMMrem_intra4x4_pred_mode");         
       tagged SDMMref_idx_l0 .data:  return $format("SDMMref_idx_l0");         
       tagged SDMSmvd_l0 .data:  return $format("SDMSmvd_l0");         
       tagged AUDPrimaryPicType .data:  return $format("AUDPrimaryPicType"); 
       tagged EndOfSequence: return $format("EndOfSequence");
       tagged EndOfStream: return $format("EndOfStream");
       tagged EndOfFile: return $format("EndOfFile");
     endcase
   endfunction
endinstance


typedef union tagged                
{
 void P_L0_16x16;
 void P_L0_L0_16x8;
 void P_L0_L0_8x16;
 void P_8x8;
 void P_8x8ref0;
 void I_NxN;
 struct{
 Bit#(2) intra16x16PredMode;
 Bit#(2) codedBlockPatternChroma;
 Bit#(1) codedBlockPatternLuma;
 }I_16x16;	  
 void I_PCM;
 void P_Skip;
} MbType deriving(Eq,Bits);


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
 Bit#(8) DataByte;
 void    EndOfFile;
}
InputGenOT deriving(Eq,Bits);


typedef enum
{
 IP16x16,
 IP16x8,
 IP8x16,
 IP8x8,
 IP8x4,
 IP4x8,
 IP4x4
} IPBlockType deriving(Eq,Bits);

typedef union tagged
{
 struct { Bit#(4) refIdx; Bit#(TAdd#(PicWidthSz,2)) hor; Bit#(TAdd#(PicHeightSz,4)) ver; Bit#(14) mvhor; Bit#(12) mvver; IPBlockType bt; } IPLuma;
 struct { Bit#(4) refIdx; Bit#(1) uv; Bit#(TAdd#(PicWidthSz,2)) hor; Bit#(TAdd#(PicHeightSz,3)) ver; Bit#(14) mvhor; Bit#(12) mvver; IPBlockType bt; } IPChroma;
}
InterpolatorIT deriving(Eq,Bits);

typedef union tagged                
{
 Bit#(32)  YUV;
 void      EndOfFile;
 void      EndOfFrame;
 Bit#(PicWidthSz) SPSpic_width_in_mbs;//ue+1 1 to ?
 Bit#(PicHeightSz) SPSpic_height_in_map_units;//ue+1 1 to ?
}
BufferControlOT deriving(Eq,Bits);

typedef Bit#(FrameBufferSz) FrameBufferAddr;
typedef Bit#(TSub#(FrameBufferSz,1)) FrameBufferContainerAddr;
typedef Bit#(32) FrameBufferData;
typedef 0 FrameBufferMemory;

typedef union tagged                
{
 FrameBufferAddr FBLoadReq;
 void FBEndFrameSync;
}
FrameBufferLoadReq deriving(Eq,Bits);

typedef union tagged                
{
  FrameBufferData FBLoadResp;
}
FrameBufferLoadResp deriving(Eq,Bits);

typedef union tagged                
{
 struct {FrameBufferAddr addr; FrameBufferData data; } FBStoreReq;  
 void FBEndFrameSync;
}
FrameBufferStoreReq deriving(Eq,Bits);

typedef union tagged                
{
 struct { Bit#(4) refIdx; Bit#(1) horOutOfBounds; Bit#(TAdd#(PicWidthSz,2)) hor; Bit#(TAdd#(PicHeightSz,4)) ver; } IPLoadLuma;
 struct { Bit#(4) refIdx; Bit#(1) uv; Bit#(1) horOutOfBounds; Bit#(TAdd#(PicWidthSz,1)) hor; Bit#(TAdd#(PicHeightSz,3)) ver; } IPLoadChroma;
 void IPLoadEndFrame;
}
InterpolatorLoadReq deriving(Eq,Bits);

typedef union tagged                
{
 Bit#(32) IPLoadResp;
}
InterpolatorLoadResp deriving(Eq,Bits);


typedef union tagged
{
  Bit#(addrSz) LoadReq;
  struct { Bit#(addrSz) addr; Bit#(dataSz) data; } StoreReq;  
}
MemReq#( type addrSz, type dataSz ) 
deriving(Eq,Bits);

typedef union tagged
{
  Bit#(dataSz) LoadResp;
}
MemResp#( type dataSz )
deriving(Eq,Bits);


   function Put#(data_t) connectionToPut(Connection_Send#(data_t) connection);
      Put#(data_t) m = interface Put#(data_t);
               method Action put(data_t data);
                 connection.send(data);
               endmethod
        endinterface;
      return m;
   endfunction

  function Get#(data_t) connectionToGet(Connection_Receive#(data_t) connection);
      Get#(data_t) m = interface Get#(data_t);
               method ActionValue#(data_t) get();
                 soft_connections::Connection_Receive#(data_t) connect = connection;
                 connect.deq;
                 return connect.receive;
               endmethod
      endinterface; 
      return m;
   endfunction


typedef Bit#(64) H264OutputAddr;
typedef Bit#(64) H264InputAddr;


typedef enum {
 Y,
 U,
 V
} FieldType deriving (Bits,Eq);

// Use FrameBufferSz to define the luma/chroma sizes
typedef Bit#(TSub#(FrameBufferSz, 1)) FrameBufferAddrLuma;
typedef Bit#(TSub#(FrameBufferSz, 3)) FrameBufferAddrChroma;