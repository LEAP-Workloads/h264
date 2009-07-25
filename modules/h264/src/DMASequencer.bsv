
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

// Some design issues here.  How to handle the case in which we have leftover data - higher level required to pad us 
// out, I guess?  Simpler interface, but kinda ugly.

interface DMASequencer#(type data);
  method Action input(data);
  method ActionValue#(data) output();
endinterface

typedef DMASequencer#(data) BlockDMASequencer#(type data, numeric type horizontal, numeric type vertical);

typedef BlockDMASequencer#(data,horizontal,vertical) BlockToLineDMASequencer#(type data, numeric type horizontal, numeric type vertical, numeric type dma_length);

// Probably some form of simple write request
typedef struct {
  hor_index_t horIndex;
  ver_index_t verIndex;
  data_t data;
} OoOBlockAddr#(type data_t, type hor_index_t, type ver_index_t);

typedef enum {
  Buffer1,
  Buffer2
} BufferTarget;


// This module requires that horizontal <= dma length
// We are probably making a power of 2 assumption here
// Definitely not handling padding at this level. a wrapper ought to be built that knows how to 
// do the whole padding thing.


module [HASIM_MODULE] mkOoOBlockDMASequencer (BlockToLineDMA#(OoOBlockAddr#(data,
                                                                   Bit#(horizontal_sz),
                                                                   Bit#(vertical_sz)),
                                                     horizontal,
                                                     vertical, 
                                                     dma_length
                                     )) 
  provisos#(Bits#(data,data_sz),
            Mul#(horizontal,vertical,index),
            Div#(dma_length,horizontal, number_blocks),
            Mul#(number_blocks, horizontal, dma_length),
            Log#(horizontal, horizontal_sz_unsafe),
            Max#(1,horizontal_sz_unsafe,horizontal_sz), 
            Log#(dma_length, dma_length_unsafe),
            Max#(1,dma_length_sz_unsafe,dma_length_sz), 
            Log#(vertical, vertical_sz_unsafe),
            Max#(1,vertical_sz_unsafe,vertical_sz),
            Log#(number_blocks, number_blocks_sz_unsafe),
            Max#(1,number_blocks_sz_unsafe,number_blocks_sz),
            Add#(vertical_sz,dma_length_sz,buffer_index_sz),
            Add#(vertical_sz,horizontal_sz,block_index_sz),
            Add#(block_index_sz,number_blocks_sz,buffer_index_sz));

  // Grrr.. need some muls in here to guarantee alignment.  Oh well...

  MEMORY_IFC#(Bit#(,Bit#(32))  buffer1 <- mkBRAM();
  MEMORY_IFC#(Bit#(TAdd#(PicWidthSz,5)),Bit#(32))  buffer2 <- mkBRAM();
  
  // Fill state 
  Reg#(Bit#(number_blocks_sz)) fillBlockCount <- mkReg(0);
  Reg#(Bit#(dma_length_sz)) blockOffset <- mkReg(0);
  BufferTarget fillBuffer <- mkReg(Buffer1);


  // Drain state
  FIFOF#(BufferTarget) drainBufferReq <- mkSizedFIFOF(2); 
  FIFOF#(BufferTarget) drainBufferResp <- mkSizedFIFOF(2); // if this fifo is full, it means both buffers are full or processing 
  Reg#(buffer_index_sz) drainElementCount <- mkReg(0);
  FIFO#(data) outfifo <- mkFIFO;
  FIFO#(Bool) deqDrainBuffer <- mkSizedFIFO(2); 

  // Some useful constants
  let blockSize = fromInteger(valueof(horizontal) * valueof(vertical)); // probably have to round this up/down at some point.  
  let bufferSize = fromInteger(valueof(dma_length) * valueof(vertical)); // probably have to round this up/down at some point.  
  let horizontalSize = fromInteger(valueof(horizontal));
  let verticalSize = fromInteger(valueof(vertical));
  let dmaLength = fromInteger(valueof(dma_length));

  // may split this up at some point
  rule loadBuffer (drainBufferResp.notFull);
    let buffer = (fillBuffer == Buffer1)?buffer1:buffer2;
    if(fillBlockCount + 1 = blockSize) 
      begin
        if(blockOffset + horizontalLength == dmaLength)
          begin
            blockOffset <= 0;
            drainBufferReq.enq(fillBuffer);
            drainBufferResp.enq(fillBuffer);
            fillBuffer <= (fillBuffer==Buffer1)?Buffer2:Buffer1;
          end
        else
          begin
            blockOffset <= blockOffset + horizontalLength;
          end
        fillBlockCount <= 0;
      end      
    else
      begin
        fillBlockCount <= fillBlockCount + 1;
      end

   // the multiplication below might create an issue.
   buffer.write(zeroExtend(blockOffset) + 
               (fromInteger(dma_length) * zeroExtend(infifo.first.verIndex)) +
               zeroExtend(infifo.first.horIndex),infifo.first.data);

  endrule

  // Rules for draining the buffers    
  // I can proably condense the following four rules down to 2.
  rule drainBuffer1 (drainBufferReq.first == Buffer1);
    if(drainElementCount + 1 == bufferSize)
      begin
        drainBufferReq.deq;    
        deqDrainBuffer.enq(True);
      end
    else 
      begin
        drainElementCount <= drainElementCount + 1;
        deqDrainBuffer.enq(False);
      end

    buffer1.readReq(drainElementCount);
  endrule
 
  rule bramBuffer1Resp(drainBufferResp.first() == Buffer1);
    if(deqDrainBuffer.first()) 
      begin
        drainBufferResp.deq();  
      end
    
    deqDrainBuffer.deq();
    let resp <- buffer1.readResp;
    outfifo.enq(resp);
  endrule

  rule drainBuffer2 (drainBufferReq.first == Buffer2);
    if(drainElementCount + 1 == bufferSize)
      begin
        drainBufferReq.deq;
        deqDrainBuffer.enq(True);
      end
    else
      begin
        drainElementCount <= drainElementCount + 1;
        deqDrainBuffer.enq(False);
      end

    buffer2.readReq(drainElementCount);
  endrule

  rule bramBuffer2Resp(drainBufferResp.first() == Buffer2);
    if(deqDrainBuffer.first())
      begin
        drainBufferResp.deq();
      end
    
    deqDrainBuffer.deq();
    let resp <- buffer2.readResp;
    outfifo.enq(resp);
  endrule

  method Action input(BlockToLineDMA#(OoOBlockAddr#(data,Bit#(block_index_sz))) blockData);
    infifo.enq(blockData);
  endmethod
  
  method ActionValue#(data) output();
    outfifo.deq;
    return outfifo.first;
  endmethod

endmodule

// Create a wrapper to generate addresses - not every DMA will be sequential.  It may, for 
// example write to the same memory over and over again.  

