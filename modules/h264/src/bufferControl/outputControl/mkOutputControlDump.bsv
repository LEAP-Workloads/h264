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
  FIFO#(FieldType) fifoTarget <- mkSizedFIFO(8);
  FIFO#(FrameBufferData) dataFIFO <- mkSizedFIFO(8);


  

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
                            if(`DEBUG_OUTPUT_CONTROL == 1)
                              begin    
                                $display("OutputControl Begin Slot: %d", slot);     
                              end

                            // XXX Fix this shit at some point. We should use the notion of a "maximum frame size" constant.  Then we won't need frameinmb in this calculation. 
                            Bit#(FrameBufferSz) addr <- calculateAddrBase(slot);
                            outAddrBase <= addr;
                          
                        end

      tagged SPSpic_width_in_mbs .width: 
        begin
	  infifo.deq();
          picWidth <= width;
          outfifo.send(tagged SPSpic_width_in_mbs width);
       end

      tagged SPSpic_height_in_map_units .height:
        begin
          infifo.deq();
          picHeight <= height.height;
          frameinmb <= height.area;
          if(`DEBUG_OUTPUT_CONTROL == 1)
            begin     
              $display("OutputControl: height: %d width: %d area: %d", height.height, picWidth, height.area);
            end

          outfifo.send(tagged SPSpic_height_in_map_units height.height);
        end

      default: 
        begin 
          $display("Unexpected token in OutputControl");
          $finish;
        end
    endcase
  endrule

  rule outputingReqY (infifo.first matches tagged Slot .outSlot &&& outprocess ==Y);
    FrameBufferAddrLuma addr = truncateLSB(outAddrBase)+zeroExtend(outReqCount);
    if(`DEBUG_OUTPUT_CONTROL == 1)
      begin    
        $display( "TRACE OutputControl: outputingReq Y %h %d %h %h", outAddrBase, outReqCount, addr, frameinmb); 
      end

    dataFIFO.enq(0);
    if(outReqCount + 1 == {1'b0,frameinmb,6'b000000})
      begin
        outprocess <= U;
        outReqCount <= 0;
      end
    else
      begin
        outReqCount <= outReqCount+1;
      end
    fifoTarget.enq(Y);
  endrule
   
  rule outputingReqU (infifo.first matches tagged Slot .outSlot &&& outprocess ==U);
    FrameBufferAddrChroma addr = truncateLSB(outAddrBase)+zeroExtend(outReqCount);
    if(`DEBUG_OUTPUT_CONTROL == 1)
      begin    
        $display( "TRACE OutputControl: outputingReq U %h %d %h", outAddrBase, outReqCount, addr);
      end

    dataFIFO.enq(0);
    if(outReqCount + 1 == {3'b000,frameinmb,4'b0000})
      begin
        outprocess <= V;
        outReqCount <= 0;
      end
    else
      begin
        outReqCount <= outReqCount+1;
      end

    fifoTarget.enq(U);
  endrule

  rule outputingReqV (infifo.first matches tagged Slot .outSlot &&& outprocess ==V);
    FrameBufferAddrChroma addr = truncateLSB(outAddrBase)+zeroExtend(outReqCount);
    if(`DEBUG_OUTPUT_CONTROL == 1)
      begin    
        $display( "TRACE OutputControl: outputingReq V %h %d %h", outAddrBase, outReqCount, addr);
      end

    dataFIFO.enq(0);
    fifoTarget.enq(V);
    if(outReqCount + 1 == {3'b000,frameinmb,4'b0000})
      begin
        outprocess <= OutstandingRequests;
        outReqCount <= 0;
      end
    else
      begin
        outReqCount <= outReqCount+1;
      end 
  endrule


  rule outputingRespY(fifoTarget.first() == Y);
    dataFIFO.deq;
    if(`DEBUG_OUTPUT_CONTROL == 1)
      begin    
        $display( "TRACE OutputControl: Resp Received Y %h", outRespCount);  
      end

    outfifo.send(tagged YUV (dataFIFO.first));
    outRespCount <= outRespCount+1;
    fifoTarget.deq;
  endrule

  rule outputingRespU(fifoTarget.first() == U);
    dataFIFO.deq;

    if(`DEBUG_OUTPUT_CONTROL == 1)
      begin    
        $display( "TRACE OutputControl: Resp Received U %h", outRespCount);
      end

    outfifo.send(tagged YUV (dataFIFO.first));
    outRespCount <= outRespCount+1;
    fifoTarget.deq;
  endrule
   
  rule outputingRespV(fifoTarget.first() == V);
    dataFIFO.deq;
    if(`DEBUG_OUTPUT_CONTROL == 1)
      begin    
        $display( "TRACE OutputControl: Resp Received V %h", outRespCount);
      end

    outfifo.send(tagged YUV (dataFIFO.first()));
    outRespCount <= outRespCount+1;
    fifoTarget.deq;
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