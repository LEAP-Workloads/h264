
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

interface DMA#(type data);
  method Action input(data);
  method ActionValue#(data) output();
endinterface

typedef DMA#(data) BlockDMA#(type data, numeric type horizontal, numeric type vertical);

typedef BlockDMA#(data,horizontal,vertical) BlockToLineDMA#(type data, numeric type horizontal, numeric type vertical, numeric type dma_length);

// Probably some form of simple write request
typedef struct {
  index_t index;
  data_t data;
} OoOBlockAddr#(type data_t, type index_t);

typedef enum {
  Buffer1,
  Buffer2
} BufferTarget;


// This module requires that horizontal <= dma length
// We are probably making a power of 2 assumption here
module [HASIM_MODULE] mkBlockDMAOoO (BlockToLineDMA#(OoOBlockAddr#(data,Bit#(block_index_sz)),
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
  Reg#(Bit#(number_blocks_sz)) fillBlockIndex <- mkReg(0);
  Reg#(Bit#(block_index_sz))   fillElementCount <- mkReg(0);
  BufferTarget fillBuffer <- mkReg(Buffer1);


  // Drain state
  FIFOF#(BufferTarget) drainBuffer <- mkSizedFIFOF(2); // if this fifo is full, it means both buffers are full 
  Reg#(buffer_index_sz) drainElementCount <- mkReg(0);


   
 
  method Action input(data)  if(drainBuffer.notFull());

  endmethod

  method ActionValue#(data) output();
  
  endmethod

 

endmodule