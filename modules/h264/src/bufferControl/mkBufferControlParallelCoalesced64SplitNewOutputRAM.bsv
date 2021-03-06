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

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/scratchpad_memory.bsh"
`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/mem_services.bsh"

`include "asim/provides/h264_types.bsh"
`include "asim/provides/h264_decoder_types.bsh"
`include "asim/dict/VDEV_SCRATCH.bsh"
`include "asim/provides/h264_output_control_split.bsh"
`include "asim/provides/h264_buffer_control_common.bsh"

import FIFO::*;
import Vector::*;

import Connectable::*;
import GetPut::*;
import ClientServer::*;





//-----------------------------------------------------------
// Buffer Controller  Module
//-----------------------------------------------------------


module [CONNECTED_MODULE] mkBufferControl();

   // Instantiate RL Stats
   let mkBufferYStats = mkBasicScratchpadCacheStats("FRAME_BUFFER_Y_",
                                                    "H264 FRAME BUFFER Y: ");
   let mkBufferUStats = mkBasicScratchpadCacheStats("FRAME_BUFFER_U_",
                                                    "H264 FRAME BUFFER U: ");
   let mkBufferVStats = mkBasicScratchpadCacheStats("FRAME_BUFFER_V_",
                                                    "H264 FRAME BUFFER V: ");

   // We use three mem interfaces here

   MEMORY_MULTI_READ_IFC#(2,FrameBufferAddrLuma, FrameBufferData)   bufferY <-  mkBRAMMultiRead();
   MEMORY_MULTI_READ_IFC#(2,FrameBufferAddrChroma, FrameBufferData) bufferU <-  mkBRAMMultiRead();
   MEMORY_MULTI_READ_IFC#(2,FrameBufferAddrChroma, FrameBufferData) bufferV <-  mkBRAMMultiRead();

   // protect the read interfaces
   MEMORY_READER_IFC#(FrameBufferAddrLuma, FrameBufferData) bufferYRead <- mkSafeMemoryReader(bufferY.readPorts[0]);
   MEMORY_READER_IFC#(FrameBufferAddrChroma, FrameBufferData) bufferURead <- mkSafeMemoryReader(bufferU.readPorts[0]);
   MEMORY_READER_IFC#(FrameBufferAddrChroma, FrameBufferData) bufferVRead <- mkSafeMemoryReader(bufferV.readPorts[0]);

   // Soft connections

   Connection_Receive#(DeblockFilterOT) infifo <- mkConnection_Receive("mkDeblocking_outfifo");  

   Connection_Send#(InterpolatorLoadResp) inLoadRespQ <- mkConnection_Send("mkPrediction_interpolatorMemRespQ");
   Connection_Receive#(InterpolatorLoadReq) inLoadReqQ <- mkConnection_Receive("mkPrediction_interpolatorMemReqQ");

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

   Reg#(SlotNum) inSlot <- mkReg(0);
   Reg#(Bit#(FrameBufferSz)) inAddrBase <- mkReg(0);


   OutputControl outputControl <- mkOutputControl(bufferY.readPorts[1],bufferU.readPorts[1],bufferV.readPorts[1]);    
   FreeSlots freeSlots <- mkFreeSlots(outputControl.find);//may include outSlot (have to make sure it's not used)
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
   function calculateLumaCoord(LumaCoordHor hor, LumaCoordVer ver);     
     Bit#(TAdd#(PicAreaSz,6)) addr = {(zeroExtend(ver)*zeroExtend(picWidth)),2'b00}+zeroExtend(hor);
     return addr;
   endfunction

   function calculateChromaCoord(ChromaCoordHor hor, ChromaCoordVer ver);
     Bit#(TAdd#(PicAreaSz,4)) addr = {(zeroExtend(ver)*zeroExtend(picWidth)),1'b0}+zeroExtend(hor);
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
                        outputControl.enq(tagged SPSpic_width_in_mbs xdata);
		     end
		  tagged SPSpic_height_in_map_units .xdata :
		     begin
			infifo.deq();
			picHeight <= xdata;
                        Bit#(PicAreaSz) area = zeroExtend(picWidth)*zeroExtend(xdata);
			frameinmb <= area;
                        PicHeight height; 
                        height.height = xdata;
                        height.area = area;
                        outputControl.enq(tagged SPSpic_height_in_map_units height);
		     end
		  tagged PPSnum_ref_idx_l0_active .xdata :
		     begin
			infifo.deq();
			ppsnum_ref_idx_l0_active <= xdata;
		     end
		  tagged SHfirst_mb_in_slice .xdata :
		     begin
			if(adjustFreeSlots == 0) // Use SFIFO here 
			   begin
			      infifo.deq();
			      newInputFrame <= False;
			      shortTermPicList.listAll();
			      longTermPicList.listAll();
			      initRefPicList <= True;
			      refPicListCount <= 0;
			      if(newInputFrame)
				 begin
				    inSlot <= freeSlots.first; //Use SFIFO - this call to first should probably take a function ...
                                    Bit#(FrameBufferSz) addr <- calculateAddrBase(freeSlots.first);
				    inAddrBase <= addr;
				 end
			      $display( "Trace BufferControl: passing SHfirst_mb_in_slice %h %0d", freeSlots.first, (newInputFrame ? 1 : 0));
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
                       infifo.deq();                     end
	       endcase
	    end
	 tagged DFBLuma .indata :
	    begin
	       infifo.deq();
	       //$display( "TRACE Buffer Control: input Luma %0d %h %h", indata.mb, indata.pixel, indata.data);
	         Bit#(TAdd#(PicAreaSz,6)) addr = calculateLumaCoord(indata.hor,
                                                                    indata.ver);
               if(`DEBUG_BUFFER_CONTROL == 1) 
                 begin
                   $display("TRACE BufferControl: Luma Store: hor: %d ver: %d addr:%h data:%h", indata.hor, 
                                                                                                indata.ver, 
                                                                                                addr, 
                                                                                                indata.data);
                 end

               bufferY.write(truncateLSB(inAddrBase)+zeroExtend(addr), indata.data);
	    end
	 tagged DFBChroma .indata :
	    begin
	       infifo.deq();
	       Bit#(TAdd#(PicAreaSz,4)) addr = calculateChromaCoord(indata.hor,
                                                                    indata.ver);

	       if(indata.uv == 0)
                 begin
                   bufferU.write(truncateLSB(inAddrBase)+zeroExtend(addr), indata.data);
                 end 
               else 
                 begin
                   bufferV.write(truncateLSB(inAddrBase)+zeroExtend(addr), indata.data);
                 end

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
               outputControl.enq(tagged Slot inSlot); // must wait till end of frame
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

   rule goToNextFrame ( inputframedone && inLoadReqQ.receive()==IPLoadEndFrame );
      inputframedone <= False;      
      inLoadReqQ.deq();
      lockInterLoads <= True;
      $display("BufferControl Sending EndOfFrame");
      
   endrule


   rule unlockInterLoads ( lockInterLoads && refPicListDone );
      lockInterLoads <= False;
   endrule

   
   //This may not be right...
   rule theEndOfFile (noMoreInput);
     $display("BufferControl Sending EndOfFile");
     noMoreInput <= False;
     outputControl.enq(EndOfFile);
   endrule


   // Rules for handling interprediction
   FIFO#(FieldType) fifoTarget <- mkSizedFIFO(32);
   
   rule interLumaReq ( inLoadReqQ.receive() matches tagged IPLoadLuma .reqdata &&& !lockInterLoads );
      inLoadReqQ.deq();
      Bit#(5) slot = refPicList.sub(zeroExtend(reqdata.refIdx));
      Bit#(FrameBufferSz) addrBase <- calculateAddrBase(slot);    
      Bit#(TAdd#(PicAreaSz,6)) addr = {(zeroExtend(reqdata.ver)*zeroExtend(picWidth)),2'b00}+zeroExtend(reqdata.hor);
      inLoadOutOfBounds.enq({reqdata.horOutOfBounds,(reqdata.hor==0 ? 0 : 1)});
      fifoTarget.enq(Y);
      FrameBufferAddrLuma addrY = truncateLSB(addrBase)+zeroExtend(addr);
      bufferYRead.readReq(addrY);
      $display( "Trace BufferControl: interLumaReq %h %h %h %h %h", reqdata.refIdx, slot, addrBase, addr, addrY);
   endrule


   rule interChromaReq ( inLoadReqQ.receive() matches tagged IPLoadChroma .reqdata &&& !lockInterLoads );
      inLoadReqQ.deq();
      Bit#(5) slot = refPicList.sub(zeroExtend(reqdata.refIdx));
      Bit#(FrameBufferSz) addrBase <- calculateAddrBase(slot);
      Bit#(TAdd#(PicAreaSz,6)) addr = {(zeroExtend(reqdata.ver)*zeroExtend(picWidth)),1'b0}+zeroExtend(reqdata.hor);
      FrameBufferAddrChroma addrUV = truncateLSB(addrBase)+zeroExtend(addr);
      if(reqdata.uv == 1)
        begin
          bufferVRead.readReq(addrUV);
          fifoTarget.enq(V);
        end
      else
        begin
          bufferURead.readReq(addrUV);
          fifoTarget.enq(U);
        end

      inLoadOutOfBounds.enq({reqdata.horOutOfBounds,(reqdata.hor==0 ? 0 : 1)});

      $display( "Trace BufferControl: interChromaReq %h %h %h %h %h", reqdata.refIdx, slot, addrBase, addr, addrUV);
   endrule

   function Action sendLoadResp(FrameBufferData data);
      action
      if(inLoadOutOfBounds.first() == 2'b10)
	 inLoadRespQ.send(tagged IPLoadResp ({data[7:0],data[7:0],data[7:0],data[7:0]}));
      else if(inLoadOutOfBounds.first() == 2'b11)
	 inLoadRespQ.send(tagged IPLoadResp ({data[31:24],data[31:24],data[31:24],data[31:24]}));
      else
	 inLoadRespQ.send(tagged IPLoadResp data);
      inLoadOutOfBounds.deq();
      endaction
   endfunction 
    
   rule interRespY (fifoTarget.first() == Y);
      let data <- bufferYRead.readRsp();
      fifoTarget.deq();
      sendLoadResp(data);
      $display( "Trace BufferControl: interResp Y %h %h", inLoadOutOfBounds.first(), data);
   endrule

   rule interRespU (fifoTarget.first() == U);
      let data <- bufferURead.readRsp();
      fifoTarget.deq();
      sendLoadResp(data);
      $display( "Trace BufferControl: interResp U %h %h", inLoadOutOfBounds.first(), data);
   endrule

   rule interRespV (fifoTarget.first() == V);
      let data <- bufferVRead.readRsp();
      fifoTarget.deq();
      sendLoadResp(data);
      $display( "Trace BufferControl: interResp V %h %h", inLoadOutOfBounds.first(), data);
   endrule

endmodule

