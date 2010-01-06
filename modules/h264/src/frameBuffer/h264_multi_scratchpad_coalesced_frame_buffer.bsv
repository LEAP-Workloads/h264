*******************************************************************
* Awb module specification
********************************************************************

%AWB_START

%name H264 multi scratchpad frame buffer
%desc multi scratchpad based memory
%provides h264_frame_buffer

%attributes h264

%param SYNTH_BOUNDARY mkFrameBuffer "synth boundary names"

* I get the feeling that I'll want to split some of this out eventually
%sources -t BSV  -v PUBLIC IFrameBuffer.bsv mkFrameBufferCoalescedMultiScratchpad.bsv  
%public mkFrameBufferScratchpad.dic

%AWB_END