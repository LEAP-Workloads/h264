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

`include "hasim_common.bsh"
`include "soft_connections.bsh"
`include "asim/provides/fpga_components.bsh"

`include "h264_types.bsh"
`include "h264_decoder_types.bsh"

import DMA::*;

module [CONNECTED_MODULE] mkFrameDMABlockOrder ();

   Connection_Receive#(DeblockFilterOT) infifo <- mkConnection_Receive("mkDeblocking_outfifo");  
   Connection_Send#(BufferControlOT) outfifo <- mkConnection_Send("bufferControl_outfifo");

   rule inputing ( !noMoreInput && !inputframedone );
      //$display( "Trace Buffer Control: passing infifo packed %h", pack(infifo.receive()));
      case (infifo.receive()) matches
	 tagged EDOT .indata :
	    begin
	       case (indata) matches
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
	       //$display( "TRACE Buffer Control: input Luma %0d %h %h", indata.mb, indata.pixel, indata.data);
	         Bit#(TAdd#(PicAreaSz,6)) addr = calculateLumaCoord(indata.hor,
                                                                    indata.ver);
               $display("TRACE BufferControl: Luma Store: addr:%h",addr);
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
               $display("TRACE BufferControl: Chroma Store: UV: %h addr:%h",indata.uv, addr);
	       //$display( "TRACE Buffer Control: input Chroma %0d %0h %h %h %h %h", indata.uv, indata.ver, indata.hor, indata.data, addr, (inAddrBase+zeroExtend(chromaOffset)+zeroExtend(vOffset)+zeroExtend(addr)));
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

endmodule