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
// H264 Main Module
//----------------------------------------------------------------------
//
//



`include "hasim_common.bsh"
`include "soft_connections.bsh"

import H264Types::*;
import IH264::*;
import INalUnwrap::*;
import IEntropyDec::*;
import IInverseTrans::*;
import IPrediction::*;
import IDeblockFilter::*;
import IBufferControl::*;
import IDecoupledClient::*;
import mkNalUnwrap::*;
import mkBufferControl::*;

 
import Connectable::*;
import GetPut::*;
import ClientServer::*;

//(* synthesize *)
module [HASIM_MODULE] mkH264( IH264 );

   // Instantiate the modules

   INalUnwrap     nalunwrap     <- mkNalUnwrap();


   // The Deblocking data pipeline connections. Memory pipeline exists elsewhere.   
    

   // Internal connections
   //   mkConnection( prediction.mem_client_buffer, buffercontrol.inter_server );

   //mkConnection( nalunwrap.ioout, entropydec.ioin );
   //mkConnection( entropydec.ioout_InverseTrans, inversetrans.ioin );
   //mkConnection( entropydec.ioout, prediction.ioin );
   //mkConnection( inversetrans.ioout, prediction.ioin_InverseTrans );
   //mkConnection(prediction.ioout, deblockfilter.ioin);
   //mkConnection( deblockfilter.ioout, buffercontrol.ioin);   

   // SOft Connections to Prediction
   Connection_Send#(MemResp#(68)) intraMemRespQTX <- mkConnection_Send("mkPrediction_intraMemRespQ");
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,2),68)) intraMemReqQRX <- mkConnection_Receive("mkPrediction_intraMemReqQ");
   Connection_Send#(MemResp#(32)) interMemRespQTX <- mkConnection_Send("mkPrediction_interMemRespQ");
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,2),32)) interMemReqQRX <- mkConnection_Receive("mkPrediction_interMemReqQ");
  

   // Soft Connection to Deblock 
   Connection_Send#(MemResp#(13)) parameterMemRespQTX <- mkConnection_Send("mkDeblocking_parameterMemRespQ");
   Connection_Receive#(MemReq#(PicWidthSz,13)) parameterMemReqQRX <- mkConnection_Receive("mkDeblocking_parameterMemReqQ");
   
   Connection_Send#(MemResp#(32)) dataMemRespQTX <- mkConnection_Send("mkDeblocking_dataMemRespQ");
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,5),32)) dataMemStoreReqQRX <- mkConnection_Receive("mkDeblocking_dataMemStoreReqQ");  
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,5),32)) dataMemLoadReqQRX <- mkConnection_Receive("mkDeblocking_dataMemLoadReqQ");
  

   //Soft Connection to Entropy
   Connection_Send#(MemResp#(20)) calcncMemRespQTX <- mkConnection_Send("mkCalc_nc_MemRespQ");
   Connection_Receive#(MemReq#(TAdd#(PicWidthSz,1),20)) calcncMemReqQRX <- mkConnection_Receive("mkCalc_nc_MemReqQ");

   Connection_Receive#(BufferControlOT) outfifoRX <- mkConnection_Receive("bufferControl_outfifo");

   // Interface to input generator
   interface ioin = nalunwrap.ioin;


   // Memory interfaces
   interface mem_clientED          = interface  Client#(MemReq#(TAdd#(PicWidthSz,1),20),MemResp#(20));
                                       interface request = connectionToGet(calcncMemReqQRX);
                                       interface response = connectionToPut(calcncMemRespQTX);
                                     endinterface; 
   interface mem_clientP_intra     = interface Client#(MemReq#(TAdd#(PicWidthSz,2),68),MemResp#(68));
                                       interface request = connectionToGet(intraMemReqQRX);
                                       interface response = connectionToPut(intraMemRespQTX);
                                     endinterface; 


 
   interface mem_clientP_inter     = interface Client#(MemReq#(TAdd#(PicWidthSz,2),32),MemResp#(32));
                                       interface request = connectionToGet(interMemReqQRX);
                                       interface response = connectionToPut(interMemRespQTX);
                                     endinterface;
 

   interface mem_clientD_data      = interface IDecoupledClient#(MemReq#(TAdd#(PicWidthSz,5),32),MemResp#(32));
                                       interface request_load = connectionToGet(dataMemLoadReqQRX);
                                       interface request_store = connectionToGet(dataMemStoreReqQRX);
                                       interface response = connectionToPut(dataMemRespQTX);
                                     endinterface;
 

   interface mem_clientD_parameter = interface Client#(MemReq#(PicWidthSz,13),MemResp#(13));

                                     endinterface;
//   interface buffer_client_load1   = buffercontrol.buffer_client_load1;
//   interface buffer_client_load2   = buffercontrol.buffer_client_load2;
//   interface buffer_client_store   = buffercontrol.buffer_client_store;

   // Interface for output 
   
   interface ioout =  connectionToGet(outfifoRX);
      
endmodule


