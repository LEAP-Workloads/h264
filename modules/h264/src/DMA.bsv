
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

import DMASequencer::*;


interface DMA#(type data_t, type addr_t);
  method Action inputData(data_t data);
  method ActionValue#(data_t) outputData();
  method Action inputAddr(addr_t addr);
  method ActionValue#(addr_t) outputAddr();
endinterface

typedef DMA#(data_t,addr_t) OoOBlockToLineDMA#(type data_t, 
                                               type addr_t, 
                                               numeric type horizontal, 
                                               numeric type vertical, 
                                               numeric type dma_length);

typedef struct {
  addr_t baseAddress;
  addr_t burstOffset;
} BlockToLineDMAAddr#(type addr_t) deriving (Bits,Eq);

module mkOoOBlockToLineDMA (OoOBlockToLineDMA#(OoOBlockAddr#(data,
                                                             Bit#(horizontal_sz),
                                                             Bit#(vertical_sz)),
                                               BlockToLineDMAAddr#(addr), 
                                               horizontal, 
                                               vertical, 
                                               dma_length))
   provisos(Bits#(data,data_sz),
 /*           Arith#(addr_t),*/
            Bits#(addr,addr_sz),
            Mul#(horizontal,vertical,index),
            Div#(dma_length,horizontal, number_blocks),
            Mul#(number_blocks, horizontal, dma_length),
            Log#(horizontal, horizontal_sz_unsafe),
            Max#(1,horizontal_sz_unsafe,horizontal_sz), 
            Log#(dma_length, dma_length_sz_unsafe),
            Max#(1,dma_length_sz_unsafe,dma_length_sz), 
            Log#(vertical, vertical_sz_unsafe),
            Max#(1,vertical_sz_unsafe,vertical_sz),
            Log#(number_blocks, number_blocks_sz_unsafe),
            Max#(1,number_blocks_sz_unsafe,number_blocks_sz),
            Add#(vertical_sz,dma_length_sz,buffer_index_sz),
            Add#(vertical_sz,horizontal_sz,block_index_sz),
            Add#(block_index_sz,number_blocks_sz,buffer_index_sz),
            Add#(xxx, horizontal_sz, buffer_index_sz));

   // probably need to assert that addr > dma_length, possibly also arith
  BlockToLineDMASequencer#(OoOBlockAddr#(data,Bit#(horizontal_sz),Bit#(vertical_sz)),
                  horizontal,
                  vertical, 
                  dma_length) dmaBlock <- mkOoOBlockDMASequencer;

  //Control state
  Reg#(Bool) idle <- mkReg(True);

  //State to generate the addresses, which will occur in row order
  Reg#(Bit#(vertical_sz)) burstCount <- mkReg(0);
  Reg#(Bit#(addr_sz)) burstOffset <- mkRegU; 
  Reg#(Bit#(addr_sz)) currentBurstOffset <- mkRegU; 
  Reg#(Bit#(addr_sz)) baseAddress <- mkRegU; 

  method inputData = dmaBlock.in;

  method outputData = dmaBlock.out;

  method Action inputAddr(BlockToLineDMAAddr#(addr) address) if(idle);
    idle <= False;
    burstOffset <= pack(address.burstOffset);
    baseAddress <= pack(address.baseAddress);
  endmethod

  method ActionValue#(BlockToLineDMAAddr#(addr)) outputAddr() if(!idle); 
    if(burstCount + 1 == fromInteger(valueof(vertical)))
      begin
        currentBurstOffset <= 0;
        idle <= True;  // We're making an assumption here about the underlying store
                       // which should be true.  That is, the store will guard against a data
                       // overwrite.
        burstCount <= 0;
      end
    else
      begin
        currentBurstOffset <= currentBurstOffset + burstOffset;
        burstCount <= burstCount + 1;
      end

    return BlockToLineDMAAddr{baseAddress: unpack(baseAddress+currentBurstOffset)};
  endmethod

endmodule

