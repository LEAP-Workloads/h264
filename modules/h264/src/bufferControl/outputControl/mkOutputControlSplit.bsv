import FIFO::*;

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/scratchpad_memory.bsh"
`include "asim/provides/librl_bsv_base.bsh"

`include "asim/provides/processor_library.bsh"

`include "asim/provides/h264_decoder_types.bsh"
`include "asim/provides/h264_types.bsh"


module [CONNECTED_MODULE] mkOutputControl#(MEMORY_READER_IFC#(FrameBufferAddrLuma, FrameBufferData) bufferY,
                                           MEMORY_READER_IFC#(FrameBufferAddrChroma, FrameBufferData) bufferU,
                                           MEMORY_READER_IFC#(FrameBufferAddrChroma, FrameBufferData) bufferV)  (OutputControl);

   Connection_Send#(BufferControlOT) outfifo <- mkConnection_Send("bufferControl_outfifo");

  // function to crack frame in mb
  function Bool checkSlot(SlotNum slot, OutputControlType outputControl);
    return (outputControl matches tagged Slot .slotControl?slot==slotControl:False);
  endfunction                          
   
  Reg#(Bit#(PicWidthSz))  picWidth  <- mkReg(maxPicWidthInMB);
  Reg#(Bit#(PicHeightSz)) picHeight <- mkReg(0);
  Reg#(Outprocess) outprocess <- mkReg(Idle);
  Reg#(Bit#(FrameBufferSz)) outAddrBase <- mkReg(0);
  Reg#(Bit#(TAdd#(PicAreaSz,7))) outReqCount <- mkReg(0);
  Reg#(Bit#(TAdd#(PicAreaSz,7))) outRespCount <- mkReg(0);
  Reg#(SlotNum) slotNum <- mkReg(0);
  Reg#(Bit#(PicAreaSz)) frameinmb <- mkReg(0);

  SFIFO#(OutputControlType,SlotNum) infifo <- mkSFIFO(checkSlot);
  FIFO#(FieldType) fifoTarget <- mkSizedFIFO(32);

  // what I really want here is to be able to send tags around...
  // By which I mean tagging the input and output controls  
  // but that is a different optimization for a different day  

  rule idling(outprocess == Idle);
    // As is the style we allow metadata changes only when not processing
    case (infifo.first) matches 
      tagged EndOfFile : begin
                           $display("OutputControl EndOfFile");     
                           outfifo.send(tagged EndOfFile);
                           infifo.deq;
                         end
      tagged Slot .slot : begin
                            outprocess <= Y;
                            $display("OutputControl Begin Slot: %d", slot);     
                            // XXX Fix this shit at some point. We should use the notion of a "maximum frame size" constant.  Then we won't need frameinmb in this calculation. 
                            outAddrBase <= (zeroExtend(slot)*zeroExtend(frameinmb)*3)<<5;
                          
                        end

      tagged SPSpic_width_in_mbs .width: 
        begin
	  infifo.deq();
          picWidth <= width;
          outfifo.send(tagged SPSpic_width_in_mbs width);
       end

      tagged SPSpic_height_in_map_units .hieght:
        begin
          infifo.deq();
          picHeight <= hieght;
          frameinmb <= zeroExtend(picWidth)*zeroExtend(hieght);
          outfifo.send(tagged SPSpic_height_in_map_units hieght);
        end

      default: 
        begin 
          $display("Unexpected token in OutputControl");
          $finish;
        end
    endcase
  endrule

  rule outputingReqY (infifo.first matches tagged Slot .outSlot &&& outprocess ==Y);
    $display( "TRACE OutputControl: outputingReq Y %h %h %h", outAddrBase, outReqCount, (outAddrBase+zeroExtend(outReqCount)));
    bufferY.readReq(truncateLSB(outAddrBase)+zeroExtend(outReqCount));
    if(outReqCount == {1'b0,frameinmb,6'b000000}-1)
      outprocess <= U;
    outReqCount <= outReqCount+1;
    fifoTarget.enq(Y);
  endrule
   
  rule outputingReqU (infifo.first matches tagged Slot .outSlot &&& outprocess ==U);
    $display( "TRACE OutputControl: outputingReq U %h %h %h", outAddrBase, outReqCount, (outAddrBase+zeroExtend(outReqCount)));
    bufferU.readReq(truncateLSB(outAddrBase)+zeroExtend(outReqCount));
    if(outReqCount == {1'b0,frameinmb,6'b000000}+{3'b000,frameinmb,4'b0000}-1)
      outprocess <= V;
    fifoTarget.enq(U);
    outReqCount <= outReqCount+1;
  endrule

  rule outputingReqV (infifo.first matches tagged Slot .outSlot &&& outprocess ==V);
    $display( "TRACE OutputControl: outputingReq V %h %h %h", outAddrBase, outReqCount, (outAddrBase+zeroExtend(outReqCount)));
    bufferV.readReq(truncateLSB(outAddrBase)+zeroExtend(outReqCount));
    fifoTarget.enq(V);
    if(outReqCount == {1'b0,frameinmb,6'b000000}+{2'b00,frameinmb,5'b00000}-1)
      outprocess <= OutstandingRequests;
    outReqCount <= outReqCount+1;
  endrule




   rule outputingRespY(fifoTarget.first() == Y);
     let xdata <- bufferY.readRsp();
     $display( "TRACE OutputControl: Resp Received %h", outRespCount);  
     outfifo.send(tagged YUV xdata);
     outRespCount <= outRespCount+1;
   endrule

   rule outputingRespU(fifoTarget.first() == U);
     let xdata <- bufferU.readRsp();
     $display( "TRACE OutputControl: Resp Received %h", outRespCount);
     outfifo.send(tagged YUV xdata);
     outRespCount <= outRespCount+1;
   endrule
   
   rule outputingRespV(fifoTarget.first() == V);
     let xdata <- bufferV.readRsp();
     $display( "TRACE OutputControl: Resp Received %h", outRespCount);
     outfifo.send(tagged YUV xdata);
     outRespCount <= outRespCount+1;
   endrule


   rule sendEndOfFrame (outRespCount ==  {1'b0,frameinmb,6'b000000}+{2'b00,frameinmb,5'b00000} && (outprocess == OutstandingRequests));
     outRespCount <= 0;
     outReqCount <= 0;
     outprocess <= Idle;
     infifo.deq;
     outfifo.send(tagged EndOfFrame);
     $display("OutputControl EndOfFrame total data: %d", outRespCount);     
   endrule

  method enq = infifo.enq;
  method find = infifo.find;
  method notEmpty = infifo.notEmpty;

endmodule