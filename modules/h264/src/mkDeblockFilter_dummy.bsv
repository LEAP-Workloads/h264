
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
// Deblocking Filter
//----------------------------------------------------------------------
//
//

`include "soft_connections.bsh"

`include "h264_types.bsh"
`include "h264_decoder_types.bsh"
`include "h264_memory_unit.bsh"


import FIFO::*;
import Vector::*;

import Connectable::*;
import GetPut::*;
import ClientServer::*;




//-----------------------------------------------------------
// Local Datatypes
//-----------------------------------------------------------




//-----------------------------------------------------------
// Helper functions




//-----------------------------------------------------------
// Deblocking Filter Module
//-----------------------------------------------------------


module [CONNECTED_MODULE] mkDeblockFilter ();

   Connection_Receive#(PredictionOT) infifo <- mkConnection_Receive("mkDeblocking_infifo");
   Connection_Send#(DeblockFilterOT) outfifo <- mkConnection_Send("mkDeblocking_outfifo");  
  
   Reg#(Bit#(1)) chromaFlag    <- mkReg(0);
   Reg#(Bit#(4)) blockNum      <- mkReg(0);
   Reg#(Bit#(4)) pixelNum      <- mkReg(0);

   Reg#(Bit#(PicWidthSz))  picWidth  <- mkReg(maxPicWidthInMB);
   Reg#(Bit#(PicHeightSz)) picHeight <- mkReg(0);
   Reg#(Bit#(PicAreaSz))   firstMb   <- mkReg(0);
   Reg#(Bit#(PicAreaSz))   currMb    <- mkReg(0);
   Reg#(Bit#(PicAreaSz))   currMbHor <- mkReg(0);//horizontal position of currMb
   Reg#(Bit#(PicHeightSz)) currMbVer <- mkReg(0);//vertical position of currMb

   Vector#(3,Reg#(Bit#(8)))   tempinput  <- replicateM(mkRegU);

   Reg#(Bool) endOfFrame <- mkReg(False);


   //-----------------------------------------------------------
   // Rules
   
   rule passing (currMbHor<zeroExtend(picWidth) && !endOfFrame);
      //$display( "Trace Deblocking Filter: passing infifo packed %h", pack(infifo.receive()));
      case (infifo.receive()) matches
        tagged EDOT .edot:
          case (edot) matches
            tagged NewUnit . xdata :
              begin
                infifo.deq();
                outfifo.send(tagged EDOT edot);
	      end
            tagged SPSpic_width_in_mbs .xdata :
              begin
                infifo.deq();
                outfifo.send(tagged EDOT edot);
                picWidth <= xdata;
                end
            tagged SPSpic_height_in_map_units .xdata :
              begin
                infifo.deq();
                outfifo.send(tagged EDOT edot);
                picHeight <= xdata;
              end
            tagged SHfirst_mb_in_slice .xdata :
              begin
                infifo.deq();
                outfifo.send(tagged EDOT edot);
                firstMb   <= xdata;
                currMb    <= xdata;
                currMbHor <= xdata;
                currMbVer <= 0;
              end
            tagged EndOfFile :
              begin
                infifo.deq();
                outfifo.send(tagged EDOT edot);
                $display( "ccl5: EndOfFile reached");
              end
            default:
              begin
                infifo.deq();
                outfifo.send(tagged EDOT edot);
              end
         endcase


            tagged PBoutput .xdata :
              begin
                infifo.deq();
                Bit#(2) blockHor = {blockNum[2],blockNum[0]};
                Bit#(2) blockVer = {blockNum[3],blockNum[1]};
                Bit#(2) pixelHor = {pixelNum[1],pixelNum[0]};
                Bit#(2) pixelVer = {pixelNum[3],pixelNum[2]};
                Bit#(PicWidthSz) currMbHorT = truncate(currMbHor);
                Bit#(32) pixelq = {xdata[3],xdata[2],xdata[1],xdata[0]};
                if(chromaFlag==0)
	          outfifo.send(tagged DFBLuma {ver:{currMbVer,blockVer,pixelVer},hor:{currMbHorT,blockHor},data:pixelq});
                else
                  outfifo.send(tagged DFBChroma {uv:blockHor[1],ver:{currMbVer,blockVer[0],pixelVer},hor:{currMbHorT,blockHor[0]},data:pixelq});
         
                if(pixelNum == 12)
                  begin
                    pixelNum <= 0;
                    if(blockNum == 15)
                      begin
                        blockNum <= 0;
                        chromaFlag <= 1;
                      end
                    else if(blockNum==7 && chromaFlag==1) 
                      begin
                        blockNum <= 0;
                        chromaFlag <= 0;
                        currMb <= currMb+1;
                        currMbHor <= currMbHor+1;
                        if(currMbVer==picHeight-1 && currMbHor==zeroExtend(picWidth-1))
                           endOfFrame <= True;
                      end
                    else
                      blockNum <= blockNum+1;
                  end
                else
                  pixelNum <= pixelNum+4;
 
                //$display( "Trace Deblocking Filter: passing PBoutput %h %h %h %h", blockNum, pixelNum, pixelHor, xdata);
            end

            default: // Drop on the floor
              begin
                infifo.deq();
                //outfifo.send(tagged EDOT infifo.receive());
              end

     endcase
  endrule


   rule currMbHorUpdate( !(currMbHor<zeroExtend(picWidth)) && !endOfFrame);
      Bit#(PicAreaSz) temp = zeroExtend(picWidth);
      if((currMbHor >> 3) >= temp)
	 begin
	    currMbHor <= currMbHor - (temp << 3);
	    currMbVer <= currMbVer + 8;
	 end
      else
	 begin
	    currMbHor <= currMbHor - temp;
	    currMbVer <= currMbVer + 1;
	 end
      //$display( "Trace Deblocking Filter: currMbHorUpdate %h %h", currMbHor, currMbVer);
   endrule


   rule outputEndOfFrame(endOfFrame);
      outfifo.send(tagged EndOfFrame);
      endOfFrame <= False;
      //$display( "Trace Deblocking Filter: outputEndOfFrame %h", pack(infifo.receive()));
   endrule
   
endmodule

