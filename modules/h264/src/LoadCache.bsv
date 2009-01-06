//import Params::*;
import H264Types::*;
import FIFO::*;
import ClientServer::*;
import GetPut::*;
import RegFile::*;
import Vector::*;

typedef 10 CacheRows;
typedef 0 RowSize;

interface LoadCache;
   interface Client#(FrameBufferLoadReq,FrameBufferLoadResp) loadReqOut;   
   interface Server#(FrameBufferLoadReq,FrameBufferLoadResp) loadReqIn;
endinterface
       
module mkLoadCache#(String name) (LoadCache)
 provisos(Add#(RowSize,CacheRows, subtotal), 
          Add#(tagSize, TAdd#(CacheRows,RowSize), FrameBufferSz),
          Add#(RowSize, TAdd#(CacheRows,tagSize), FrameBufferSz)
);
   
   RegFile#(Bit#(CacheRows),Maybe#(Tuple2#(Bit#(TSub#(FrameBufferSz, TAdd#(CacheRows,RowSize))), Vector#(TExp#(RowSize),Bit#(32)))))  cache <- mkRegFileFull();


   FIFO#(FrameBufferLoadReq)  loadReqInQ  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespInQ <- mkFIFO();
   FIFO#(FrameBufferLoadReq)  loadReqOutQ  <- mkFIFO();
   FIFO#(FrameBufferLoadResp) loadRespOutQ <- mkFIFO();
   Reg#(Vector#(TExp#(RowSize),Bit#(32))) loadReg <- mkReg(replicate(0));
   Reg#(Bit#(TAdd#(RowSize,1))) reqCount <- mkReg(0);
   Reg#(Bit#(TAdd#(RowSize,1))) respCount <-mkReg(0);  
   Reg#(Bool) issuedReq <- mkReg(False);
   Reg#(Bit#(64)) hitCount <- mkReg(0);
   Reg#(Bit#(64)) missCount <- mkReg(0);
   Reg#(Bit#(64)) totalCycles <- mkReg(0);

   rule cycling;
     totalCycles <= totalCycles + 1;
      if(totalCycles % 10000 == 0)
	 begin
           $display("Cache %s: hits: %d misses: %d", name, hitCount, missCount);
	 end
   endrule

   rule makeReq (loadReqInQ.first() matches tagged FBLoadReq .addrt &&& reqCount > 0);
      match {.tag, .indexaggregate}  = split(addrt);
      Tuple2#(Bit#(CacheRows),Bit#(RowSize)) indextup = split(indexaggregate);
      match {.index, .blockindex} = indextup;
     
      reqCount <= reqCount - 1;
      Bit#(RowSize) rowindex =  truncate(reqCount - 1);
      loadReqOutQ.enq(tagged FBLoadReq ({tag, index, rowindex}));
   endrule

   rule makeResp(loadReqInQ.first() matches tagged FBLoadReq .addrt &&& respCount > 0);
          match {.tag, .indexaggregate}  = split(addrt);
          Tuple2#(Bit#(CacheRows),Bit#(RowSize)) indextup = split(indexaggregate);
          match {.index, .blockindex} = indextup;

      let updLoadReg = loadReg;
      respCount <= respCount - 1;
      loadRespOutQ.deq;

      if(loadRespOutQ.first matches tagged FBLoadResp .resp)
	begin
	   updLoadReg [respCount - 1]  = resp; 
           loadReg <= updLoadReg;       
	   if(respCount - 1 == 0)
	      begin
                cache.upd(index,tagged Valid tuple2(tag,updLoadReg)); 
	      end
	end

   endrule
   
   
   rule passing( loadReqInQ.first() matches tagged FBEndFrameSync );
      loadReqOutQ.enq(loadReqInQ.first);
      loadReqInQ.deq;
   endrule
   
   rule loading (loadReqInQ.first() matches tagged FBLoadReq .addrt &&& reqCount == 0 &&& respCount == 0 );
          match {.tag, .indexaggregate}  = split(addrt);
          Tuple2#(Bit#(CacheRows),Bit#(RowSize)) indextup = split(indexaggregate);
          match {.index, .blockindex} = indextup;
          
          if(cache.sub(index) matches tagged Valid .entry)
   	    begin
              match {.cacheTag, .payload} = entry;
	        if(tag == cacheTag)
	           begin
                     // Got a hit!
		     //$display("Cache %s got a response hit", name);       
                     hitCount <= hitCount + 1;
		     loadReqInQ.deq;
		     loadRespInQ.enq( tagged FBLoadResp (payload[blockindex]) );
	           end
	        else
	          begin
		    //$display("Cache %s issuing a request", name);    
                    // need to issue a request
		    reqCount <= fromInteger(valueof(TExp#(RowSize)));
		    respCount <= fromInteger(valueof(TExp#(RowSize))); 
		    missCount <= missCount + 1;
	          end
	    end
	else
           begin
	     reqCount <= fromInteger(valueof(TExp#(RowSize)));
             respCount <= fromInteger(valueof(TExp#(RowSize)));
             missCount <= missCount + 1;
   	   end	
   endrule
	 
   interface Server loadReqIn;
      interface Put request   = fifoToPut(loadReqInQ);
      interface Get response  = fifoToGet(loadRespInQ);
   endinterface
	 
  interface Client loadReqOut;
     interface Get request   = fifoToGet(loadReqOutQ);
     interface Put response  = fifoToPut(loadRespOutQ);
   endinterface

endmodule     

      
