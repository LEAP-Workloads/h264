
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
// Memory for Entropy Decoder
//----------------------------------------------------------------------
//
//
//

`include "asim/provides/platform_services.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/soft_connections.bsh"
`include "asim/provides/h264_types.bsh"

import RegFile::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;


//----------------------------------------------------------------------
// Main module
//----------------------------------------------------------------------

typedef Empty IMemEDConnection#(numeric type index_size, numeric type data_size);

module [CONNECTED_MODULE] mkMemEDConnection#(String reqQName, String respQName) (IMemEDConnection#(index_size,data_size))
   provisos (Bits#(MemReq#(index_size,data_size),mReqLen),
	     Bits#(MemResp#(data_size),mRespLen)/*,
             Transmittable#(MemResp#(data_size)),
             Transmittable#(MemReq#(index_size,data_size))*/);

  //-----------------------------------------------------------
  // State

   RegFile#(Bit#(index_size),Bit#(data_size)) rfile <- mkRegFileFull();
   
   Connection_Send#(MemResp#(data_size)) respQ <- mkConnection_Send(respQName);
   Connection_Receive#(MemReq#(index_size,data_size)) reqQ <- mkConnection_Receive(reqQName);

   rule storing ( reqQ.receive() matches tagged StoreReq { addr:.addrt,data:.datat} );
      rfile.upd(addrt,datat);
      reqQ.deq(); 
   endrule

   rule reading ( reqQ.receive() matches tagged LoadReq .addrt );
      respQ.send( tagged LoadResp (rfile.sub(addrt)) );
      reqQ.deq();
   endrule
   
endmodule

