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
// Buffer Controller
//----------------------------------------------------------------------
//
//

`include "soft_connections.bsh"
`include "hasim_common.bsh"
`include "h264_frame_buffer_coalesced_64.bsh"

`include "h264_types.bsh"
`include "h264_decoder_types.bsh"

import FIFO::*;
import Vector::*;

import Connectable::*;
import GetPut::*;
import ClientServer::*;




//-----------------------------------------------------------
// Local Datatypes
//-----------------------------------------------------------

typedef union tagged                
{
 void     Idle;          //not working on anything in particular
 void     Y;
 void     U;
 void     V;
}
Outprocess deriving(Eq,Bits);


//-----------------------------------------------------------
// Short term pic list submodule
//-----------------------------------------------------------

typedef union tagged                
{
 void     Idle;          //not working on anything in particular
 void     Remove;
 void     RemoveOutput;
 void     RemoveFound;
 void     InsertGap;
 void     Search;
 void     ListAll;
}
ShortTermPicListState deriving(Eq,Bits);

interface ShortTermPicList;
   method Action clear();
   method Action insert( Bit#(16) frameNum, Bit#(5) slot, Bit#(5) maxAllowed );
   method Action insert_gap( Bit#(16) frameNum, Bit#(5) slot, Bit#(5) maxAllowed, Bit#(16) gap, Bit#(5) log2_max_frame_num );
   method Action remove( Bit#(16) frameNum, Bool removeOutputFlag );
   method Action search( Bit#(16) frameNum );
   method Action listAll();
   method Action deq();
   method Maybe#(Bit#(5)) resultSlot();
   method Bit#(5) numPics();
endinterface

module mkShortTermPicList( ShortTermPicList );
   function Bit#(5) shortTermPicListNext( Bit#(5) addrFunc );
      if(addrFunc<maxRefFrames-1)
	 return addrFunc+1;
      else
	 return 0;
   endfunction
   function Bit#(5) shortTermPicListPrev( Bit#(5) addrFunc );
      if(addrFunc==0)
	 return maxRefFrames-1;
      else
	 return addrFunc-1;
   endfunction
   
   RFile1#(Bit#(5),Tuple2#(Bit#(16),Bit#(5))) rfile <- mkRFile1(0,maxRefFrames-1);
   Reg#(ShortTermPicListState) state <- mkReg(Idle);
   Reg#(Bit#(5))  log2_mfn  <- mkReg(0);   
   Reg#(Bit#(5))  nextPic   <- mkReg(0);
   Reg#(Bit#(5))  picCount  <- mkReg(0);
   Reg#(Bit#(5))  tempPic   <- mkReg(0);
   Reg#(Bit#(5))  tempCount <- mkReg(0);
   Reg#(Bit#(16)) tempNum   <- mkReg(0);
   FIFO#(Maybe#(Bit#(5))) returnList <- mkFIFO();
   
   rule removing ( state==Remove || state==RemoveOutput || state==RemoveFound );
      if(state!=RemoveFound)
	 begin
	    Tuple2#(Bit#(16),Bit#(5)) temp = rfile.sub(tempPic);
	    if(tpl_1(temp)==tempNum)
	       begin
		  state <= RemoveFound;
		  if(state==RemoveOutput)
		     returnList.enq(tagged Valid tpl_2(temp));
	       end
	    if(tempCount>=picCount)
	       $display( "ERROR BufferControl: ShortTermPicList removing not found");
	 end
      else
	 begin
	    Bit#(5) tempPrev = shortTermPicListPrev(tempPic);
	    rfile.upd(tempPrev,rfile.sub(tempPic));
	    if(tempCount==picCount)
	       begin
		  picCount <= picCount-1;
		  nextPic <= tempPrev;
		  state <= Idle;
	       end
	 end
      tempCount <= tempCount+1;
      tempPic <= shortTermPicListNext(tempPic);
   endrule
   
   rule insertingGap ( state matches tagged InsertGap );
      if(tempCount>0)
	 begin
	    if(tempCount>1)
	       rfile.upd(nextPic,tuple2(tempNum,31));
	    else
	       rfile.upd(nextPic,tuple2(tempNum,tempPic));
	    nextPic <= shortTermPicListNext(nextPic);
	 end
      else
	 state <= Idle;
      Bit#(17) tempOne = 1;
      Bit#(17) maxPicNum = tempOne << log2_mfn;
      if(zeroExtend(tempNum) == maxPicNum-1)
	 tempNum <= 0;
      else
	 tempNum <= tempNum+1;
      tempCount <= tempCount-1;
   endrule
   
   rule searching ( state matches tagged Search );
      if(tempCount<picCount)
	 begin
	    Tuple2#(Bit#(16),Bit#(5)) temp = rfile.sub(tempPic);
	    if(tpl_1(temp)==tempNum)
	       begin
		  returnList.enq(tagged Valid tpl_2(temp));
		  state <= Idle;
	       end
	    tempPic <= shortTermPicListPrev(tempPic);
	    tempCount <= tempCount+1;
	 end
      else
	 $display( "ERROR BufferControl: ShortTermPicList searching not found");
   endrule
   
   rule listingAll ( state matches tagged ListAll );
      if(tempCount<picCount)
	 begin
	    Tuple2#(Bit#(16),Bit#(5)) temp = rfile.sub(tempPic);
	    returnList.enq(tagged Valid tpl_2(temp));
	    tempPic <= shortTermPicListPrev(tempPic);
	    tempCount <= tempCount+1;
	 end
      else
	 begin
	    returnList.enq(tagged Invalid);
	    state <= Idle;
	 end
   endrule
   
   method Action clear() if(state matches tagged Idle);
      picCount <= 0;
      nextPic <= 0;
   endmethod
   
   method Action insert( Bit#(16) frameNum, Bit#(5) slot, Bit#(5) maxAllowed ) if(state matches tagged Idle);
      rfile.upd(nextPic,tuple2(frameNum,slot));
      nextPic <= shortTermPicListNext(nextPic);
      if(maxAllowed>picCount)
	 picCount <= picCount+1;
   endmethod
   
   method Action insert_gap( Bit#(16) frameNum, Bit#(5) slot, Bit#(5) maxAllowed, Bit#(16) gap, Bit#(5) log2_max_frame_num ) if(state matches tagged Idle);
      state <= InsertGap;
      log2_mfn <= log2_max_frame_num;
      if(zeroExtend(picCount)+gap+1 >= zeroExtend(maxAllowed))
	 picCount <= maxAllowed;
      else
	 picCount <= truncate(zeroExtend(picCount)+gap+1);
      Bit#(5) temp;
      if(gap+1 >= zeroExtend(maxAllowed))
	 temp = maxAllowed;
      else
	 temp = truncate(gap+1);
      tempCount <= temp;
      Bit#(17) tempOne = 1;
      Bit#(17) maxPicNum = tempOne << log2_max_frame_num;
      Bit#(17) tempFrameNum = zeroExtend(frameNum);
      if(tempFrameNum+1 > zeroExtend(temp))
	 tempNum <= truncate(tempFrameNum+1-zeroExtend(temp));
      else
	 tempNum <= truncate(maxPicNum+tempFrameNum+1-zeroExtend(temp));
      tempPic <= slot;
   endmethod
   
   method Action remove( Bit#(16) frameNum, Bool removeOutputFlag ) if(state matches tagged Idle);
      if(removeOutputFlag)
	 state <= RemoveOutput;
      else
	 state <= Remove;
      tempCount <= 0;
      Bit#(5) temp = (maxRefFrames-picCount)+nextPic;
      if(temp>maxRefFrames-1)
	 tempPic <= temp-maxRefFrames;
      else
	 tempPic <= temp;
      tempNum <= frameNum;
   endmethod
   
   method Action search( Bit#(16) frameNum ) if(state matches tagged Idle);
      state <= Search;
      tempCount <= 0;
      tempPic <= shortTermPicListPrev(nextPic);
      tempNum <= frameNum;
   endmethod
   
   method Action listAll() if(state matches tagged Idle);
      state <= ListAll;
      tempCount <= 0;
      tempPic <= shortTermPicListPrev(nextPic);
   endmethod
   
   method Action deq();
      returnList.deq();
   endmethod
   
   method Maybe#(Bit#(5)) resultSlot();
      return returnList.first();
   endmethod
   
   method Bit#(5) numPics() if(state matches tagged Idle);
      return picCount;
   endmethod
endmodule

//-----------------------------------------------------------
// Long term pic list submodule
//-----------------------------------------------------------

typedef union tagged                
{
 void     Idle;          //not working on anything in particular
 void     Clear;
 void     ListAll;
}
LongTermPicListState deriving(Eq,Bits);

interface LongTermPicList;
   method Action clear();
   method Action insert( Bit#(5) frameNum, Bit#(5) slot );
   method Action remove( Bit#(5) frameNum );
   method Action maxIndexPlus1( Bit#(5) maxAllowed );
   method Action search( Bit#(5) frameNum );
   method Action listAll();
   method Action deq();
   method Maybe#(Bit#(5)) resultSlot();
   method Bit#(5) numPics();
endinterface

module mkLongTermPicList( LongTermPicList );
//   RegFile#(Bit#(5),Maybe#(Bit#(5))) rfile <- mkRegFile(0,maxRefFrames-1);
   RFile1#(Bit#(5),Maybe#(Bit#(5))) rfile <- mkRFile1Full();
   Reg#(LongTermPicListState) state <- mkReg(Idle);
   Reg#(Bit#(5)) picCount <- mkReg(0);
   Reg#(Bit#(5)) tempPic  <- mkReg(0);
   FIFO#(Maybe#(Bit#(5))) returnList <- mkFIFO();

   rule clearing ( state matches tagged Clear );
      if(tempPic<maxRefFrames)
	 begin
	    if(rfile.sub(tempPic) matches tagged Valid .data &&& picCount!=0)
	       picCount <= picCount-1;
	    rfile.upd(tempPic,Invalid);
	    tempPic <= tempPic+1;
	 end
      else
	 state <= Idle;
      //$display( "TRACE BufferControl: LongTermPicList clearing %h %h", picCount, tempPic);
   endrule

   rule listingAll ( state matches tagged ListAll );
      if(tempPic<maxRefFrames)
	 begin
	    Maybe#(Bit#(5)) temp = rfile.sub(tempPic);
	    if(temp matches tagged Valid .data)
	       returnList.enq(tagged Valid data);
	    tempPic <= tempPic+1;
	 end
      else
	 begin
	    returnList.enq(tagged Invalid);
	    state <= Idle;
	 end
      //$display( "TRACE BufferControl: LongTermPicList listingAll %h %h", picCount, tempPic);
   endrule
   
   method Action clear() if(state matches tagged Idle);
      state <= Clear;
      tempPic <= 0;
      //$display( "TRACE BufferControl: LongTermPicList clear %h", picCount);
   endmethod
   
   method Action insert( Bit#(5) frameNum, Bit#(5) slot ) if(state matches tagged Idle);
      if(rfile.sub(frameNum) matches tagged Invalid)
	 picCount <= picCount+1;
      rfile.upd(frameNum,tagged Valid slot);
      //$display( "TRACE BufferControl: LongTermPicList insert %h %h %h", picCount, frameNum, slot);
   endmethod
   
   method Action remove( Bit#(5) frameNum ) if(state matches tagged Idle);
      if(rfile.sub(frameNum) matches tagged Invalid)
	 $display( "ERROR BufferControl: LongTermPicList removing not found");
      else
	 picCount <= picCount-1;
      rfile.upd(frameNum,Invalid);
      //$display( "TRACE BufferControl: LongTermPicList remove %h %h", picCount, frameNum);
   endmethod
   
   method Action maxIndexPlus1( Bit#(5) index ) if(state matches tagged Idle);
      state <= Clear;
      tempPic <= index;
      //$display( "TRACE BufferControl: LongTermPicList maxIndexPlus1 %h %h", picCount, index);
   endmethod
   
   method Action search( Bit#(5) frameNum ) if(state matches tagged Idle);
      returnList.enq(rfile.sub(frameNum));
      //$display( "TRACE BufferControl: LongTermPicList search %h %h", picCount, frameNum);
   endmethod
   
   method Action listAll() if(state matches tagged Idle);
      state <= ListAll;
      tempPic <= 0;
      //$display( "TRACE BufferControl: LongTermPicList listAll %h", picCount);
   endmethod
   
   method Action deq();
      returnList.deq();
      //$display( "TRACE BufferControl: LongTermPicList deq %h", picCount);
   endmethod
   
   method Maybe#(Bit#(5)) resultSlot();
      return returnList.first();
   endmethod
   
   method Bit#(5) numPics() if(state matches tagged Idle);
      return picCount;
   endmethod
endmodule


//-----------------------------------------------------------
// Free slot module
//-----------------------------------------------------------

interface FreeSlots;
   method Action  init();
   method Action  add( Bit#(5) slot );
   method Action  remove( Bit#(5) slot );
   method Bit#(5) first( Bit#(5) exception );
endinterface

module mkFreeSlots( FreeSlots );
   Reg#(Vector#(18,Bit#(1))) slots <- mkRegU();

   method Action  init();
      Vector#(18,Bit#(1)) tempSlots = replicate(0);
      slots <= tempSlots;
   endmethod
   
   method Action add( Bit#(5) slot );
      Vector#(18,Bit#(1)) tempSlots = slots;
      tempSlots[slot] = 0;
      slots <= tempSlots;
      if(slot >= maxRefFrames+2)
	 $display( "ERROR BufferControl: FreeSlots add out of bounds");
   endmethod
   
   method Action remove( Bit#(5) slot );
      Vector#(18,Bit#(1)) tempSlots = slots;
      if(slot != 31)
	 begin
	    tempSlots[slot] = 1;
	    slots <= tempSlots;
	    if(slot >= maxRefFrames+2)
	       $display( "ERROR BufferControl: FreeSlots remove out of bounds");
	 end
   endmethod
   
   method Bit#(5) first( Bit#(5) exception );
      Bit#(5) tempout = 31;
      for(Integer ii=17; ii>=0; ii=ii-1)
	 begin
	    if(slots[fromInteger(ii)]==1'b0 && fromInteger(ii)!=exception)
	       tempout = fromInteger(ii);
	 end
      return tempout;
   endmethod
   
endmodule


//-----------------------------------------------------------
// Helper functions



//-----------------------------------------------------------
// Buffer Controller  Module
//-----------------------------------------------------------


module [CONNECTED_MODULE] mkBufferControl();

   Empty   framebuffer   <- mkFrameBuffer();

   // Mass of soft connections
   Connection_Receive#(DeblockFilterOT) infifo <- mkConnection_Receive("mkDeblocking_outfifo");  
   Connection_Send#(InterpolatorLoadResp) inLoadRespQ <- mkConnection_Send("mkPrediction_interpolatorMemRespQ");
   Connection_Receive#(InterpolatorLoadReq) inLoadReqQ <- mkConnection_Receive("mkPrediction_interpolatorMemReqQ");
   Connection_Send#(FrameBufferLoadReq) loadReqQ1 <- mkConnection_Send("frameBuffer_LoadReqQ1");
   Connection_Receive#(FrameBufferLoadResp) loadRespQ1 <- mkConnection_Receive("frameBuffer_LoadRespQ1");
   Connection_Send#(FrameBufferLoadReq) loadReqQ2 <- mkConnection_Send("frameBuffer_LoadReqQ2");
   Connection_Receive#(FrameBufferLoadResp) loadRespQ2 <- mkConnection_Receive("frameBuffer_LoadRespQ2");
   Connection_Send#(FrameBufferStoreReq) storeReqQ <- mkConnection_Send("frameBuffer_StoreReqQ");
   Connection_Send#(BufferControlOT) outfifo <- mkConnection_Send("bufferControl_outfifo");


   FIFO#(Bit#(2)) inLoadOutOfBounds <- mkSizedFIFO(64);

   Reg#(Bit#(5)) log2_max_frame_num <- mkReg(0);
   Reg#(Bit#(5)) num_ref_frames <- mkReg(0);
   Reg#(Bit#(1)) gaps_in_frame_num_allowed_flag <- mkReg(0);
   Reg#(Bit#(PicWidthSz))  picWidth  <- mkReg(maxPicWidthInMB);
   Reg#(Bit#(PicHeightSz)) picHeight <- mkReg(0);
   Reg#(Bit#(PicAreaSz))   frameinmb <- mkReg(0);

   Reg#(Bit#(5))  ppsnum_ref_idx_l0_active <- mkReg(0);
   Reg#(Bit#(16)) frame_num <- mkReg(0);
   Reg#(Bit#(16)) prevRefFrameNum <- mkReg(0);
   Reg#(Bit#(5))  num_ref_idx_l0_active <- mkReg(0);
   Reg#(Bit#(2))  reordering_of_pic_nums_idc <- mkReg(0);
   Reg#(Bit#(16)) picNumLXPred <- mkReg(0);
   Reg#(Bit#(3))  memory_management_control_operation <- mkReg(0);

   Reg#(Bool) newInputFrame    <- mkReg(True);
   Reg#(Bool) noMoreInput      <- mkReg(False);
   Reg#(Bool) inputframedone   <- mkReg(False);
   Reg#(Outprocess) outprocess <- mkReg(Idle);
   Reg#(Bool) outputframedone  <- mkReg(True);

   Reg#(Bit#(5)) inSlot <- mkReg(0);
   Reg#(Bit#(FrameBufferSz)) inAddrBase <- mkReg(0);
   Reg#(Bit#(5)) outSlot <- mkReg(31);
   Reg#(Bit#(FrameBufferSz)) outAddrBase <- mkReg(0);
   Reg#(Bit#(TAdd#(PicAreaSz,7))) outRespCount <- mkReg(0);
   Reg#(LumaCoordHor) outputHorIndex  <- mkReg(0);
   Reg#(LumaCoordVer) outputVerIndex <- mkReg(0);


   FreeSlots freeSlots <- mkFreeSlots();//may include outSlot (have to make sure it's not used)
   ShortTermPicList shortTermPicList <- mkShortTermPicList();
   LongTermPicList  longTermPicList  <- mkLongTermPicList();
   RFile1#(Bit#(5),Bit#(5)) refPicList <- mkRFile1(0,maxRefFrames-1);
   Reg#(Bit#(5)) refPicListCount <- mkReg(0);
   Reg#(Bool) initRefPicList <- mkReg(False);
   Reg#(Bool) reorderRefPicList <- mkReg(False);
   Reg#(Bit#(5)) refIdx <- mkReg(0);
   Reg#(Bit#(5)) tempSlot <- mkReg(0);
   Reg#(Bit#(5)) tempSlot2 <- mkReg(0);
   Reg#(Bit#(2)) adjustFreeSlots <- mkReg(0);

   Reg#(Bool) refPicListDone <- mkReg(False);
   Reg#(Bool) lockInterLoads <- mkReg(True);
   DoNotFire donotfire <- mkDoNotFire();
   

   // some generally useful helper functions   
   // We want to interleave adjacent rows.
   function  calculateLumaCoord(LumaCoordHor hor, LumaCoordVer ver);   
       
     // Chop off the low order bits to get the coalescing
     Tuple2#(Bit#(TAdd#(PicHeightSz,3)),Bit#(1)) verBits = split(ver);
     match {.verHigh,.verLow} = verBits;
     
     // throw low 2 bits of ver on hor...
     Bit#(TAdd#(PicAreaSz,6)) addr =  zeroExtend(verLow) + 
                                      zeroExtend(hor) * 2 + 
                                      (zeroExtend(verHigh)*zeroExtend(picWidth) * 8);

     return addr;
   endfunction


   function calculateChromaCoord(ChromaCoordHor hor, ChromaCoordVer ver);     
     // Chop off the low order bits to get the coalescing
     Tuple2#(Bit#(TAdd#(PicHeightSz,2)),Bit#(1)) verBits = split(ver);
     match {.verHigh,.verLow} = verBits;
     
     // throw low 2 bits of ver on hor...
     Bit#(TAdd#(PicAreaSz,4)) addr =  zeroExtend(verLow) + 
                                      zeroExtend(hor) * 2 + 
                                      (zeroExtend(verHigh)*zeroExtend(picWidth) * 4);
     return addr;
   endfunction


   //-----------------------------------------------------------
   // Rules
   
   rule inputing ( !noMoreInput && !inputframedone );
      //$display( "Trace Buffer Control: passing infifo packed %h", pack(infifo.receive()));
      case (infifo.receive()) matches
	 tagged EDOT .indata :
	    begin
	       case (indata) matches
		  tagged SPSlog2_max_frame_num .xdata :
		     begin
			if(adjustFreeSlots == 0)
			   begin
			      infifo.deq();
			      log2_max_frame_num <= xdata;
			      freeSlots.init();
			      shortTermPicList.clear();
			      longTermPicList.clear();
			   end
			else
			   donotfire.doNotFire();
		     end
		  tagged SPSnum_ref_frames .xdata :
		     begin
			infifo.deq();
			num_ref_frames <= xdata;
		     end
		  tagged SPSgaps_in_frame_num_allowed_flag .xdata :
		     begin
			infifo.deq();
			gaps_in_frame_num_allowed_flag <= xdata;
		     end
		  tagged SPSpic_width_in_mbs .xdata :
		     begin
			infifo.deq();
			picWidth <= xdata;
                        outfifo.send(tagged SPSpic_width_in_mbs xdata);
		     end
		  tagged SPSpic_height_in_map_units .xdata :
		     begin
			infifo.deq();
			picHeight <= xdata;
			frameinmb <= zeroExtend(picWidth)*zeroExtend(xdata);
                        outfifo.send(tagged SPSpic_height_in_map_units xdata);
		     end
		  tagged PPSnum_ref_idx_l0_active .xdata :
		     begin
			infifo.deq();
			ppsnum_ref_idx_l0_active <= xdata;
		     end
		  tagged SHfirst_mb_in_slice .xdata :
		     begin
			if(adjustFreeSlots == 0)
			   begin
			      infifo.deq();
			      newInputFrame <= False;
			      shortTermPicList.listAll();
			      longTermPicList.listAll();
			      initRefPicList <= True;
			      refPicListCount <= 0;
			      if(newInputFrame)
				 begin
				    inSlot <= freeSlots.first(outSlot);
				    inAddrBase <= (zeroExtend(freeSlots.first(outSlot))*zeroExtend(frameinmb)*3)<<5;
				 end
			      $display( "Trace BufferControl: passing SHfirst_mb_in_slice %h %h %0d", freeSlots.first(outSlot), outSlot, (newInputFrame ? 1 : 0));
			   end
			else
			   donotfire.doNotFire();
		     end
		  tagged SHframe_num .xdata :
		     begin
			infifo.deq();
			frame_num <= xdata;
			picNumLXPred <= frame_num;
		     end
		  tagged SHnum_ref_idx_active_override_flag .xdata :
		     begin
			infifo.deq();
			num_ref_idx_l0_active <= ppsnum_ref_idx_l0_active;
		     end
		  tagged SHnum_ref_idx_l0_active .xdata :
		     begin
			infifo.deq();
			num_ref_idx_l0_active <= xdata;
		     end
		  tagged SHRref_pic_list_reordering_flag_l0 .xdata :
		     begin
			if(!initRefPicList)
			   begin
			      infifo.deq();
			      if(xdata==0)
				 refPicListDone <= True;
			   end
			else
			   donotfire.doNotFire();
			refIdx <= 0;
		     end
		  tagged SHRreordering_of_pic_nums_idc .xdata :
		     begin
			if(!reorderRefPicList)
			   begin
			      infifo.deq();
			      reordering_of_pic_nums_idc <= xdata;
			      if(xdata==3)
				 refPicListDone <= True;
			   end
			else
			   donotfire.doNotFire();
		     end
		  tagged SHRabs_diff_pic_num .xdata :
		     begin
			if(!reorderRefPicList)
			   begin
			      infifo.deq();
			      Bit#(16) picNumLXNoWrap;
			      Bit#(17) tempOne = 1;
			      Bit#(17) maxPicNum = tempOne << log2_max_frame_num;
			      if(reordering_of_pic_nums_idc==0)
				 begin
				    if(picNumLXPred < truncate(xdata))
				       picNumLXNoWrap = truncate(zeroExtend(picNumLXPred)-xdata+maxPicNum);
				    else
				       picNumLXNoWrap = truncate(zeroExtend(picNumLXPred)-xdata);
				 end
			      else
				 begin
				    if(zeroExtend(picNumLXPred)+xdata >= maxPicNum)
				       picNumLXNoWrap = truncate(zeroExtend(picNumLXPred)+xdata-maxPicNum);
				    else
				       picNumLXNoWrap = truncate(zeroExtend(picNumLXPred)+xdata);
				 end
			      picNumLXPred <= picNumLXNoWrap;
			      shortTermPicList.search(picNumLXNoWrap);
			      reorderRefPicList <= True;
			      refPicListCount <= 0;
			   end
			else
			   donotfire.doNotFire();
		     end
		  tagged SHRlong_term_pic_num .xdata :
		     begin
			if(!reorderRefPicList)
			   begin
			      infifo.deq();
			      longTermPicList.search(xdata);
			      reorderRefPicList <= True;
			      refPicListCount <= 0;
			   end
			else
			   donotfire.doNotFire();
		     end
		  tagged SHDlong_term_reference_flag .xdata :
		     begin
			infifo.deq();
			if(xdata==0)
			   shortTermPicList.insert(frame_num,inSlot,num_ref_frames);
			else
			   longTermPicList.insert(0,inSlot);
			adjustFreeSlots <= 1;
		     end
		  tagged SHDadaptive_ref_pic_marking_mode_flag .xdata :
		     begin
			infifo.deq();
			Bit#(17) tempFrameNum = zeroExtend(frame_num);
			Bit#(17) tempOne = 1;
			Bit#(17) maxPicNum = tempOne << log2_max_frame_num;
			Bit#(16) tempGap = 0;
			if(frame_num < prevRefFrameNum)
			   tempFrameNum = tempFrameNum + maxPicNum;
			if(tempFrameNum-zeroExtend(prevRefFrameNum) > 1)
			   tempGap = truncate(tempFrameNum-zeroExtend(prevRefFrameNum)-1);
			if(xdata==0)
			   begin
			      if(tempGap==0)
				 shortTermPicList.insert(frame_num,inSlot,(num_ref_frames-longTermPicList.numPics()));
			      else
				 shortTermPicList.insert_gap(frame_num,inSlot,(num_ref_frames-longTermPicList.numPics()),tempGap,log2_max_frame_num);
			      adjustFreeSlots <= 1;
			   end
			prevRefFrameNum <= frame_num;
		     end
		  tagged SHDmemory_management_control_operation .xdata :
		     begin
			infifo.deq();
			memory_management_control_operation <= xdata;
			if(xdata==0)
			   adjustFreeSlots <= 1;
			else if(xdata==5)
			   begin
			      shortTermPicList.clear();
			      longTermPicList.clear();
			   end
		     end
		  tagged SHDdifference_of_pic_nums .xdata :
		     begin
			infifo.deq();
			Bit#(16) picNumXNoWrap;
			Bit#(17) tempOne = 1;
			Bit#(17) maxPicNum = tempOne << log2_max_frame_num;
			if(frame_num < truncate(xdata))
			   picNumXNoWrap = truncate(zeroExtend(frame_num)-xdata+maxPicNum);
			else
			   picNumXNoWrap = truncate(zeroExtend(frame_num)-xdata);
			if(memory_management_control_operation == 1)
			   shortTermPicList.remove(picNumXNoWrap,False);
			else
			   shortTermPicList.remove(picNumXNoWrap,True);
		     end
		  tagged SHDlong_term_pic_num .xdata :
		     begin
			infifo.deq();
			longTermPicList.remove(xdata);
		     end
		  tagged SHDlong_term_frame_idx .xdata :
		     begin
			infifo.deq();
			if(memory_management_control_operation == 3)
			   begin
			      if(shortTermPicList.resultSlot() matches tagged Valid .validdata)
				 longTermPicList.insert(xdata,validdata);
			      else
				 $display( "ERROR BufferControl: SHDlong_term_frame_idx Invalid output from shortTermPicList");
			      shortTermPicList.deq();
			   end
			else
			   longTermPicList.insert(xdata,inSlot);
		     end
		  tagged SHDmax_long_term_frame_idx_plus1 .xdata :
		     begin
			infifo.deq();
			longTermPicList.maxIndexPlus1(xdata);
		     end
		  tagged EndOfFile :
		     begin
			infifo.deq();
			$display( "INFO BufferControl: EndOfFile reached");
			noMoreInput <= True;
			//$finish(0);
			//outfifo.send(EndOfFile); 
		     end
		  default: 
                     begin
                       $display("WARNING: Why are we in this clause");
                       infifo.deq();
                     end
	       endcase
	    end
	 tagged DFBLuma .indata :
	    begin
	       infifo.deq();
               Bit#(TAdd#(PicAreaSz,6)) addr = calculateLumaCoord(indata.hor,
                                                                    indata.ver);
               if(`DEBUG_BUFFER_CONTROL == 1) 
                 begin
                   $display("TRACE BufferControl: Luma Store: hor: %d ver: %d addr:%h data:%h", indata.hor, 
                                                                                                indata.ver, 
                                                                                                addr, 
                                                                                                indata.data);
                 end
	       storeReqQ.send(FBStoreReq {addr:inAddrBase+zeroExtend(addr),data:indata.data});
	    end
	 tagged DFBChroma .indata :
	    begin
	       infifo.deq();
	       Bit#(TAdd#(PicAreaSz,4)) addr = calculateChromaCoord(indata.hor,
                                                                    indata.ver);
	       Bit#(TAdd#(PicAreaSz,6)) chromaOffset = {frameinmb,6'b000000};
	       Bit#(TAdd#(PicAreaSz,4)) vOffset = 0;
	       if(indata.uv == 1)
		  vOffset = {frameinmb,4'b0000};
	       storeReqQ.send(FBStoreReq {addr:(inAddrBase+zeroExtend(chromaOffset)+zeroExtend(vOffset)+zeroExtend(addr)),data:indata.data});

               if(`DEBUG_BUFFER_CONTROL == 1) 
                 begin
                   $display("TRACE BufferControl: Chroma Store: hor: %d, ver %d, UV: %h addr:%h data:%h",
                            indata.hor, 
                            indata.ver, 
                            indata.uv, 
                            addr, 
                            indata.data);
                 end
	    end
	 tagged EndOfFrame :
	    begin
	       infifo.deq();
	       $display( "INFO Buffer Control: EndOfFrame reached");
	       inputframedone <= True;
	       newInputFrame <= True;
	       refPicListDone <= False;
	    end
	 default: infifo.deq();
      endcase
   endrule

   
   rule initingRefPicList ( initRefPicList );
      if(shortTermPicList.resultSlot() matches tagged Valid .xdata)
	 begin
	    shortTermPicList.deq();
	    refPicList.upd(refPicListCount,xdata);
	    refPicListCount <= refPicListCount+1;
	    $display( "Trace BufferControl: initingRefPicList shortTermPicList %h", xdata);
	 end
      else if(longTermPicList.resultSlot() matches tagged Valid .xdata)
	 begin
	    longTermPicList.deq();
	    refPicList.upd(refPicListCount,xdata);
	    refPicListCount <= refPicListCount+1;
	    $display( "Trace BufferControl: initingRefPicList longTermPicList %h", xdata);
	 end
      else
	 begin
	    shortTermPicList.deq();
	    longTermPicList.deq();
	    initRefPicList <= False;
	    refPicListCount <= 0;
	    $display( "Trace BufferControl: initingRefPicList end");
	 end
   endrule

   
   rule reorderingRefPicList ( reorderRefPicList );
      $display( "Trace BufferControl: reorderingRefPicList");
      if(shortTermPicList.resultSlot() matches tagged Valid .xdata)//////////////////////////////////////////////////////////////////////////////////////////
	 begin
	    shortTermPicList.deq();
	    tempSlot <= refPicList.sub(refIdx);
	    refPicList.upd(refIdx,xdata);
	    refPicListCount <= refIdx+1;
	    tempSlot2 <= xdata;
	 end
      else if(longTermPicList.resultSlot() matches tagged Valid .xdata)/////////////////////////////////////////////////////////////////////////////////////may get stuck?
	 begin
	    longTermPicList.deq();
	    tempSlot <= refPicList.sub(refIdx);
	    refPicList.upd(refIdx,xdata);
	    refPicListCount <= refIdx+1;
	    tempSlot2 <= xdata;
	 end
      else
	 begin
	    if(refPicListCount<num_ref_idx_l0_active && tempSlot!=tempSlot2)
	       begin
		  tempSlot <= refPicList.sub(refPicListCount);
		  refPicList.upd(refPicListCount,tempSlot);
		  refPicListCount <= refPicListCount+1;
	       end
	    else
	       begin
		  reorderRefPicList <= False;
		  refPicListCount <= 0;
		  refIdx <= refIdx+1;
	       end
	 end
   endrule

   
   rule adjustingFreeSlots ( adjustFreeSlots != 0 );
      if(adjustFreeSlots == 1)
	 begin
	    shortTermPicList.listAll();
	    longTermPicList.listAll();
	    freeSlots.init();
	    adjustFreeSlots <= 2;
	    $display( "Trace BufferControl: adjustingFreeSlots begin");
	 end
      else
	 begin
	    if(shortTermPicList.resultSlot() matches tagged Valid .xdata)
	       begin
		  shortTermPicList.deq();
		  freeSlots.remove(xdata);
		  $display( "Trace BufferControl: adjustingFreeSlots shortTermPicList %h", xdata);
	       end
	    else if(longTermPicList.resultSlot() matches tagged Valid .xdata)
	       begin
		  longTermPicList.deq();
		  freeSlots.remove(xdata);
		  $display( "Trace BufferControl: adjustingFreeSlots longTermPicList %h", xdata);
	       end
	    else
	       begin
		  shortTermPicList.deq();
		  longTermPicList.deq();
		  adjustFreeSlots <= 0;
		  $display( "Trace BufferControl: adjustingFreeSlots end");
	       end
	 end
   endrule

   // need to adjust the accounting here. 
   rule outputingReq ( outprocess != Idle );
     LumaCoordHor maxIndexHor = (outprocess == Y)?zeroExtend(picWidth)*4:zeroExtend(picWidth)*2;
     LumaCoordVer maxIndexVer = (outprocess == Y)?zeroExtend(picHeight)*16:zeroExtend(picHeight)*8;
     
     if(`DEBUG_BUFFER_CONTROL == 1) 
       begin
         $display("BufferControl: pickWidth: %d, picHeight: %d",
                  picWidth,
                  picHeight);
     
         $display("BufferControl: maxIndexHor: %d, curIndexHor: %d, maxIndexVer: %d, curIndexVer: %d",
                  maxIndexHor,
                  outputHorIndex,
                  maxIndexVer, 
                  outputVerIndex);
       end

     if(outputHorIndex + 1 == maxIndexHor)
       begin
         if(outputVerIndex + 1 == maxIndexVer)
           begin
             outputVerIndex <= 0;
           end
         else
           begin
             outputVerIndex <= outputVerIndex + 1;
           end
         outputHorIndex <= 0;
       end
     else
       begin
         outputHorIndex <= outputHorIndex + 1;
       end

      if(outprocess==Y)
	 begin
            if(outputHorIndex + 1 == maxIndexHor && outputVerIndex + 1 == maxIndexVer)
              begin
                outprocess <= U;      
                $display("BufferControl: Transistion to U");
              end

            Bit#(TAdd#(PicAreaSz,6)) addr = calculateLumaCoord(outputHorIndex,
                                                               outputVerIndex);

            if(`DEBUG_BUFFER_CONTROL == 1) 
              begin  
                $display("BufferControl Output Y: %h hor: %d ver: %d",addr,outputHorIndex,outputVerIndex);
              end

	    loadReqQ1.send(FBLoadReq (outAddrBase+zeroExtend(addr)));
	 end
      else if(outprocess==U)
	 begin
            if(outputHorIndex + 1 == maxIndexHor && outputVerIndex + 1 == maxIndexVer)
              begin
                outprocess <= V;      
                $display("BufferControl: Transistion to V");
              end

            ChromaCoordHor hor = truncate(outputHorIndex);
            ChromaCoordVer ver = truncate(outputVerIndex);

            Bit#(TAdd#(PicAreaSz,4)) addr = calculateChromaCoord(hor,
                                                                 ver);
	    Bit#(TAdd#(PicAreaSz,6)) chromaOffset = {frameinmb,6'b000000};	   

            if(`DEBUG_BUFFER_CONTROL == 1) 
              begin
                $display("BufferControl Output U: %h hor: %d ver: %d",addr,outputHorIndex,outputVerIndex);
              end

	    loadReqQ1.send(FBLoadReq (outAddrBase+zeroExtend(chromaOffset)+zeroExtend(addr)));
	 end
      else
	 begin
            if(outputHorIndex + 1 == maxIndexHor && outputVerIndex + 1 == maxIndexVer)
              begin
                outprocess <= Idle;      
                $display("BufferControl: Transistion to Idle");
              end

            ChromaCoordHor hor = truncate(outputHorIndex);
            ChromaCoordVer ver = truncate(outputVerIndex);

            Bit#(TAdd#(PicAreaSz,4)) addr = calculateChromaCoord(hor,
                                                                  ver);
            if(`DEBUG_BUFFER_CONTROL == 1) 
              begin
                $display("BufferControl Output V: %h hor: %d ver: %d",addr,outputHorIndex,outputVerIndex);
              end

             Bit#(TAdd#(PicAreaSz,6)) chromaOffset = {frameinmb,6'b000000};
             Bit#(TAdd#(PicAreaSz,4)) vOffset = {frameinmb,4'b0000};
             loadReqQ1.send(FBLoadReq (outAddrBase+zeroExtend(vOffset)+zeroExtend(chromaOffset)+
                                       zeroExtend(addr)));
	 end
   endrule
   

   rule outputingResp ( !outputframedone );
      if(loadRespQ1.receive() matches tagged FBLoadResp .xdata)
	 begin
	    loadRespQ1.deq();
	    outfifo.send(tagged YUV xdata);
	    if(outRespCount == {1'b0,frameinmb,6'b000000}+{2'b00,frameinmb,5'b00000}-1)
               begin 
	         outputframedone <= True;
                 $display("BufferControl EndOfFrame total data: %d", outRespCount);
               end
	    outRespCount <= outRespCount+1;
	 end
   endrule


   rule goToNextFrame ( outputframedone && inputframedone && inLoadReqQ.receive()==IPLoadEndFrame );
      inputframedone <= False;
      outprocess <= Y;
      outputframedone <= False;
      outSlot <= inSlot;
      outAddrBase <= inAddrBase;
      outRespCount <= 0;
      loadReqQ1.send(FBEndFrameSync);
      loadReqQ2.send(FBEndFrameSync);
      storeReqQ.send(FBEndFrameSync);
      inLoadReqQ.deq();
      lockInterLoads <= True;
      $display("BufferControl Sending EndOfFrame");
      outfifo.send(EndOfFrame);
   endrule


   rule unlockInterLoads ( lockInterLoads && refPicListDone );
      lockInterLoads <= False;
   endrule

   
   //This may not be right...
   rule theEndOfFile ( outputframedone && noMoreInput );
     $display("BufferControl Sending EndOfFile");
     noMoreInput <= False;
     outputframedone <= False;
     outfifo.send(EndOfFile);
   endrule


   rule interLumaReq ( inLoadReqQ.receive() matches tagged IPLoadLuma .reqdata &&& !lockInterLoads );
      inLoadReqQ.deq();
      Bit#(5) slot = refPicList.sub(zeroExtend(reqdata.refIdx));
      Bit#(FrameBufferSz) addrBase = (zeroExtend(slot)*zeroExtend(frameinmb)*3)<<5;
      Bit#(TAdd#(PicAreaSz,6)) addr =  calculateLumaCoord(reqdata.hor,
                                                          reqdata.ver);
      inLoadOutOfBounds.enq({reqdata.horOutOfBounds,(reqdata.hor==0 ? 0 : 1)});
      loadReqQ2.send(FBLoadReq (addrBase+zeroExtend(addr)));
      //$display( "Trace BufferControl: interLumaReq %h %h %h %h %h", reqdata.refIdx, slot, addrBase, addr, addrBase+zeroExtend(addr));
   endrule


   rule interChromaReq ( inLoadReqQ.receive() matches tagged IPLoadChroma .reqdata &&& !lockInterLoads );
      inLoadReqQ.deq();
      Bit#(5) slot = refPicList.sub(zeroExtend(reqdata.refIdx));
      Bit#(FrameBufferSz) addrBase = (zeroExtend(slot)*zeroExtend(frameinmb)*3)<<5;
      Bit#(TAdd#(PicAreaSz,6)) chromaOffset = {frameinmb,6'b000000};
      Bit#(TAdd#(PicAreaSz,4)) vOffset = 0;
      if(reqdata.uv == 1)
	 vOffset = {frameinmb,4'b0000};
     
      Bit#(TAdd#(PicAreaSz,4)) addr =  calculateChromaCoord(reqdata.hor,
                                                            reqdata.ver);
      inLoadOutOfBounds.enq({reqdata.horOutOfBounds,(reqdata.hor==0 ? 0 : 1)});
      loadReqQ2.send(FBLoadReq (addrBase+zeroExtend(chromaOffset)+zeroExtend(vOffset)+zeroExtend(addr)));
      //$display( "Trace BufferControl: interChromaReq %h %h %h %h %h", reqdata.refIdx, slot, addrBase, addr, addrBase+zeroExtend(chromaOffset)+zeroExtend(vOffset)+zeroExtend(addr));
   endrule
    

   rule interResp ( loadRespQ2.receive() matches tagged FBLoadResp .data );
      loadRespQ2.deq();
      if(inLoadOutOfBounds.first() == 2'b10)
	 inLoadRespQ.send(tagged IPLoadResp ({data[7:0],data[7:0],data[7:0],data[7:0]}));
      else if(inLoadOutOfBounds.first() == 2'b11)
	 inLoadRespQ.send(tagged IPLoadResp ({data[31:24],data[31:24],data[31:24],data[31:24]}));
      else
	 inLoadRespQ.send(tagged IPLoadResp data);
      inLoadOutOfBounds.deq();
      //$display( "Trace BufferControl: interResp %h %h", inLoadOutOfBounds.first(), data);
   endrule

endmodule

