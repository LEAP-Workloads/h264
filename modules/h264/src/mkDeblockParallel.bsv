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

`include "h264_decoder_types_parallel.bsh"
`include "h264_types.bsh"
`include "h264_memory_unit.bsh"
`include "h264_deblocking_luma.bsh"
`include "h264_deblocking_chroma.bsh"

import GetPut::*;
import ClientServer::*;
import FIFOF::*;
import FIFO::*;
import IDeblockFilter::*;
import Connectable::*;
import FShow::*;

module [CONNECTED_MODULE] mkDeblockFilter ();
   // probably want to drill this through at some point...


   Connection_Receive#(DeblockFilterOT) outfifoLuma <- mkConnection_Receive("mkDeblocking_outfifoLuma");
   Connection_Receive#(DeblockFilterOT) outfifoChroma <- mkConnection_Receive("mkDeblocking_outfifoChroma");
  
   // I feel like this should split at some point as well.
   Connection_Send#(DeblockFilterOT) outputFIFO <- mkConnection_Send("mkDeblocking_outfifo");  
  
  Reg#(Bit#(16)) counter <- mkReg(0);

  Empty deblockfilterluma <- mkDeblockFilterLuma();
  Empty deblockfilterchroma <- mkDeblockFilterChroma(); 
    
   rule countUp;
     counter <= counter + 1;
   endrule

   rule chromaHead (counter == 0);
     $display("Deblock Parallel Chroma Output: ", fshow(outfifoChroma.receive));
   endrule

   rule lumaHead (counter == 0);
     $display("Deblock Parallel Luma Output: ", fshow(outfifoLuma.receive));
   endrule

   rule outMatch (outfifoLuma.receive == outfifoChroma.receive);
      outfifoLuma.deq;
      outfifoChroma.deq;
      outputFIFO.send(outfifoLuma.receive);   
   endrule
   
   rule outLuma(outfifoLuma.receive matches tagged DFBLuma .data);
      outfifoLuma.deq;
      outputFIFO.send(outfifoLuma.receive);      
   endrule
	
   rule outChroma(outfifoChroma.receive matches tagged DFBChroma .data);
      outfifoChroma.deq;
      outputFIFO.send(outfifoChroma.receive);      
   endrule
 
  //These rules might be useful for a dummy filter of some sort...
 /*
   rule inChroma;
      infifoChroma.deq;
      case (infifoChroma.receive) matches
        tagged  PBoutput .xdata: begin 
           match {.chromaFlag, .vec} = xdata;   
           if(chromaFlag == Chroma)
              begin 
                 deblockfilterchroma.ioin.put(infifoChroma.receive);
              end
	   else
	      begin
		 $display("PARDEBLOCK ERROR! passing luma data to chroma filter");
                 $finish;
	      end
        end
       
	 default:   begin
		       deblockfilterchroma.ioin.put(infifoChroma.receive);
                    end
      endcase  
   endrule

   rule inLuma;
      infifoLuma.deq;
      case (infifoLuma.receive) matches
        tagged  PBoutput .xdata: begin 
           match {.chromaFlag, .vec} = xdata;   
           if(chromaFlag == Luma)
              begin
		 
                 deblockfilterluma.ioin.put(infifoLuma.receive);
              end
	   else
	      begin
		 $display("PARDEBLOCK ERROR! passing chroma data to luma filter");
                 $finish;
	      end
        end
       
	 default:   begin
                       deblockfilterluma.ioin.put(infifoLuma.receive);
                    end
      endcase  
   endrule   */

endmodule
