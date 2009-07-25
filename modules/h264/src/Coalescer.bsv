
`include "soft_connections.bsh"
`include "hasim_common.bsh"
`include "asim/provides/librl_bsv_cache.bsh"

`include "h264_types.bsh"

import FIFO::*;
import Vector::*;

import Connectable::*;
import GetPut::*;
import ClientServer::*;
import RegFile::*;


// This module coalesces larger memory requests from smaller ones.


interface Coalescer#(type data, type addrIn, type addrOut)
 /* provisos(Bits#(addrOut,addrOutSz),
           Bits#(addrIn, addrInSz),
           Add#(addrOutSz,vecSize,addrInSz))*/;
  interface Put#(RL_DM_CACHE_STORE_REQ#(data,addrIn)) in;
/*  interface Get#(RL_DM_CACHE_STORE_REQ#(Vector#(TExp#(TSub#(SizeOf#(addrIn),
                                                            SizeOf#(addrOut))),data),addrOut)) out;*/
  interface Get#(RL_DM_CACHE_STORE_REQ#(Vector#(2,data),addrOut)) out;

endinterface

typedef  Coalescer#(data,addrIn, addrOut) SizedCoalescer#(type data,
                                                          type addrIn,
                                                          type addrOut,
                                                          numeric type size);

typedef Bit#(FrameBufferSz) BufferAddr;
typedef Bit#(TSub#(FrameBufferSz,1)) ContainerAddr;
typedef 256 N; // this may need to be a little larger.
// mask off low order bits.  
// may want input fifo here?
module mkCoalescerSimple (SizedCoalescer#(FrameBufferData,
                                          BufferAddr, 
                                          ContainerAddr,
                                          N))
   provisos(Add#(axx, TLog#(N), SizeOf#(ContainerAddr)));
  // no initialization is needed.  it is true that some false positives 
  // may occur, but these should be subsequently overwritten with correct 
  // data.  I think....

  RegFile#(Bit#(TLog#(N)),RL_DM_CACHE_STORE_REQ#(FrameBufferData,ContainerAddr)) buffer <- mkRegFileFull;
  FIFO#(RL_DM_CACHE_STORE_REQ#(Vector#(2,FrameBufferData),ContainerAddr)) outfifo <- mkSizedFIFO(2);  

  interface Put in;
    method Action put(RL_DM_CACHE_STORE_REQ#(FrameBufferData,BufferAddr) newReq);
       RL_DM_CACHE_STORE_REQ#(FrameBufferData,ContainerAddr) modReq =
            RL_DM_CACHE_STORE_REQ{addr:truncateLSB(newReq.addr),
                                  val:newReq.val}; 
       Bit#(TLog#(N)) tag = truncate(modReq.addr);  
       buffer.upd(tag, modReq);
       // and now for a tag check     
       // the following is more general than it needs to be
       let existingReq = buffer.sub(tag);
       if(existingReq.addr == modReq.addr)
         begin
           Vector#(2,FrameBufferData) outData = newVector;
           Bit#(1) index = truncate(newReq.val);
           outData[index] = modReq.val;
           outData[~index] = existingReq.val;
           outfifo.enq(RL_DM_CACHE_STORE_REQ{addr: modReq.addr,
                                             val: outData});
           $display("Coalescer outputs: %h to %h", outData, modReq.addr);
         end
       else
         begin
           $display("Coalescer tag match failure: %h != %h, tag: %d", 
                    existingReq.addr, modReq.addr, tag);
         end
    endmethod
  endinterface
    
  interface out = fifoToGet(outfifo);
endmodule

