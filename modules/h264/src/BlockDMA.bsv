interface DMA#(type data);
  method Action input(data);
  method ActionValue#(data) output();
endinterface

typedef DMA#(data) BlockDMA#(type data, numeric type horizontal, numeric type vertical);

typedef BlockDMA#(data,horizontal,vertical) BlockToLineDMA#(type data, numeric type horizontal, numeric type vertical, numeric type );