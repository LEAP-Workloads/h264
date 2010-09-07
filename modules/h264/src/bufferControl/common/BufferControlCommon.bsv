`include "asim/provides/soft_connections.bsh"
`include "asim/provides/processor_library.bsh"
`include "asim/provides/h264_decoder_types.bsh"
`include "asim/provides/h264_types.bsh"

import FIFO::*;
import Vector::*;

import Connectable::*;
import GetPut::*;
import ClientServer::*;

// Some local types related to Frame buffer addressing
// Use FrameBufferSz to define the luma/chroma sizes
typedef Bit#(TSub#(FrameBufferSz, 1)) FrameBufferAddrLuma;
typedef Bit#(TSub#(FrameBufferSz, 3)) FrameBufferAddrChroma;


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
   method Action insert( Bit#(16) frameNum, SlotNum slot, Bit#(5) maxAllowed );
   method Action insert_gap( Bit#(16) frameNum, SlotNum slot, Bit#(5) maxAllowed, Bit#(16) gap, Bit#(5) log2_max_frame_num );
   method Action remove( Bit#(16) frameNum, Bool removeOutputFlag );
   method Action search( Bit#(16) frameNum );
   method Action listAll();
   method Action deq();
   method Maybe#(SlotNum) resultSlot();
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
   FIFO#(Maybe#(SlotNum)) returnList <- mkFIFO();
   
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
   method Action insert( Bit#(5) frameNum, SlotNum slot );
   method Action remove( Bit#(5) frameNum );
   method Action maxIndexPlus1( Bit#(5) maxAllowed );
   method Action search( Bit#(5) frameNum );
   method Action listAll();
   method Action deq();
   method Maybe#(SlotNum) resultSlot();
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
	    returnList.enq(Invalid);
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
   method Action  add( SlotNum slot );
   method Action  remove( SlotNum slot );
   method SlotNum first( );
endinterface

module mkFreeSlots#(function Bool exception(SlotNum slot))( FreeSlots );
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
   
   method Bit#(5) first();
      Bit#(5) tempout = 31;
      for(Integer ii=17; ii>=0; ii=ii-1)
	 begin
	    if(slots[fromInteger(ii)]==1'b0 && !exception(fromInteger(ii)))
	       tempout = fromInteger(ii);
	 end
      return tempout;
   endmethod
   
endmodule




