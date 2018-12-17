import Ehr::*;
import Vector::*;

interface Fifo#(numeric type n, type t);
  method Bool notFull;
  method Action enq(t x);
  method Bool notEmpty;
  method Action deq;
  method t first;
  method Action clear;
endinterface

// A bypass FIFO implementation
// notFull < enq < {notEmpty, first} < deq < clear
module mkBypassFifo(Fifo#(1, t)) provisos(Bits#(t, tSz));
  Ehr#(2, t) data <- mkEhr(?);
  Ehr#(3, Bool) full <- mkEhr(False);

  method Bool notFull = !full[0];

  method Action enq(t x) if(!full[0]);
    data[0] <= x;
    full[0] <= True;
  endmethod

  method Bool notEmpty = full[1];

  method Action deq if(full[1]);
    full[1] <= False;
  endmethod

  method t first if(full[1]);
    return data[1];
  endmethod

  method Action clear;
    full[2] <= False;
  endmethod
endmodule

// (* synthesize *)
// module mkBypassFifo_Synth(Fifo#(1, int));
//    let _f <- mkBypassFifo;
//    return _f;
// endmodule

//////////////////////////////////////////////////////////////////////

// A Conflict free implementation of n element FIFO
// {notEmpty, first} < deq < clear < canonicalize
// notFull < enq < clear < canonicalize
// deq conflict free with enq
// canonicalize has no effect after clear anyway

module mkCFFifo(Fifo#(n, t)) provisos(Bits#(t, tSz), 
				      Add#(n, 1, n1), 
				      Log#(n1, sz), 
				      Add#(sz, 1, sz1));
  Integer ni = valueOf(n);
  Bit#(sz1) nb = fromInteger(ni);
  Bit#(sz1) n2 = 2*nb;
  Vector#(n, Reg#(t)) data <- replicateM(mkRegU);
  Ehr#(3, Bit#(sz1)) enqP <- mkEhr(0);
  Ehr#(3, Bit#(sz1)) deqP <- mkEhr(0);
  Ehr#(3, Bool) enqEn <- mkEhr(True);
  Ehr#(3, Bool) deqEn <- mkEhr(False);
  Ehr#(2, t)                 tempData <- mkEhr(?);
  Ehr#(2, Maybe#(Bit#(sz1))) tempEnqP <- mkEhr(Invalid);

  rule canonicalize;
    Bit#(sz1) cnt = enqP[2] >= deqP[2]? enqP[2] - deqP[2]: 
                                   (enqP[2]%nb + nb) - deqP[2]%nb;
    if(!enqEn[2] && cnt != nb) enqEn[2] <= True;
    if(!deqEn[2] && cnt != 0) deqEn[2] <= True;

    if(isValid(tempEnqP[1]))
    begin
      data[validValue(tempEnqP[1])] <= tempData[1];
      tempEnqP[1] <= Invalid;
    end
  endrule

  method Bool notFull = enqEn[0];

  method Action enq(t x) if(enqEn[0]);
    tempData[0] <= x;
    tempEnqP[0] <= Valid (enqP[0]%nb);
    enqP[0] <= (enqP[0] + 1)%n2;
    enqEn[0] <= False;
  endmethod

  method Bool notEmpty = deqEn[0];

  method Action deq();// if(deqEn[0]);
    deqP[0] <= (deqP[0] + 1)%n2;
    deqEn[0] <= False;
  endmethod

  method t first();//if(deqEn[0]);
    return data[deqP[0]%nb];
  endmethod

  method Action clear;
    enqP[1] <= 0;
    deqP[1] <= 0;
    enqEn[1] <= True;
    deqEn[1] <= False;
  endmethod
endmodule

// (* synthesize *)
// module mkCFFifo_Synth(Fifo#(4, int));
//    let _f <- mkCFFifo;
//    return _f;
// endmodule

//////////////////////////////////////////////////////////////////////


// A pipelined implementation of n element FIFO
// {notEmpty, first} < deq < notFull < enq < clear

module mkPipelineFifo(Fifo#(n, t)) provisos(Bits#(t, tSz), 
					    Add#(n, 1, n1), 
					    Log#(n1, sz), 
					    Add#(sz, 1, sz1));
  Integer ni = valueOf(n);
  Bit#(sz1) nb = fromInteger(ni);
  Bit#(sz1) n2 = 2*nb;
  Vector#(n, Reg#(t)) data <- replicateM(mkRegU);
  Ehr#(3, Bit#(sz1)) enqP <- mkEhr(0);
  Ehr#(2, Bit#(sz1)) deqP <- mkEhr(0);

  Bit#(sz1) cnt0 = enqP[0] >= deqP[0]? enqP[0] - deqP[0]:
                                       (enqP[0]%nb + nb) - deqP[0]%nb;
  Bit#(sz1) cnt1 = enqP[0] >= deqP[1]? enqP[0] - deqP[1]:
                                       (enqP[0]%nb + nb) - deqP[1]%nb;

  method Bool notFull = cnt1 < nb;

  method Action enq(t x) if(cnt1 < nb);
    enqP[0] <= (enqP[0] + 1)%n2;
    data[enqP[0]%nb] <= x;
  endmethod

  method Bool notEmpty = cnt0 != 0;

  method Action deq if(cnt0 != 0);
    deqP[0] <= (deqP[0] + 1)%n2;
  endmethod

  method t first if(cnt0 != 0);
    return data[deqP[0]%nb];
  endmethod

  method Action clear;
    enqP[2] <= 0;
    deqP[1] <= 0;
  endmethod
endmodule

// (* synthesize *)
// module mkPipelineFifo_Synth(Fifo#(4, int));
//    let _f <- mkPipelineFifo;
//    return _f;
// endmodule




//////////////////////////////////////////////////////////////////////
// Searchable FIFO has an extra search method
//////////////////////////////////////////////////////////////////////
interface SFifo#(numeric type n, type t, type st);
  method Bool notFull;
  method Action enq(t x);
  method Bool notEmpty;
  method Action deq;
  method Bool search(st s);
  method t first;
  method Action clear;
endinterface

// search is conflict-free with {enq, deq, first, notFull, notEmpty}
// search <  clear < canonicalize
module mkCFSFifo#(function Bool isFound(t v, st k))
		     (SFifo#(n, t, st)) 
		     provisos(Bits#(t, tSz), 
			Add#(n, 1, n1), 
			Log#(n1, sz), 
			Add#(sz, 1, sz1));
  Integer ni = valueOf(n);
  Bit#(sz1) nb = fromInteger(ni);
  Bit#(sz1) n2 = 2*nb;
  Vector#(n, Reg#(t)) data <- replicateM(mkRegU);
  Ehr#(3, Bit#(sz1)) enqP <- mkEhr(0);
  Ehr#(3, Bit#(sz1)) deqP <- mkEhr(0);
  Ehr#(3, Bool) enqEn <- mkEhr(True);
  Ehr#(3, Bool) deqEn <- mkEhr(False);
  Ehr#(2, t)                 tempData <- mkEhr(?);
  Ehr#(2, Maybe#(Bit#(sz1))) tempEnqP <- mkEhr(Invalid);
  Ehr#(2, Maybe#(Bit#(sz1))) tempDeqP <- mkEhr(Invalid);

  Bit#(sz1) cnt0 = enqP[0] >= deqP[0]? enqP[0] - deqP[0]: 
                                 (enqP[0]%nb + nb) - deqP[0]%nb;
  Bit#(sz1) cnt2 = enqP[2] >= deqP[2]? enqP[2] - deqP[2]: 
                                 (enqP[2]%nb + nb) - deqP[2]%nb;
  rule canonicalize;
    if(!enqEn[2] && cnt2 != nb) enqEn[2] <= True;
    if(!deqEn[2] && cnt2 != 0) deqEn[2] <= True;

    if(isValid(tempEnqP[1]))
    begin
      data[validValue(tempEnqP[1])] <= tempData[1];
      tempEnqP[1] <= Invalid;
    end

    if(isValid(tempDeqP[1]))
    begin
      deqP[0] <= validValue(tempDeqP[1]);
      tempDeqP[1] <= Invalid;
    end
  endrule

  method Bool notFull = enqEn[0];

  method Action enq(t x) if(enqEn[0]);
    tempData[0] <= x;
    tempEnqP[0] <= Valid (enqP[0]%nb);
    enqP[0] <= (enqP[0] + 1)%n2;
    enqEn[0] <= False;
  endmethod

  method Bool notEmpty = deqEn[0];

  method Action deq if(deqEn[0]);
    tempDeqP[0] <= Valid ((deqP[0] + 1)%n2);
    deqEn[0] <= False;
  endmethod

  method t first if(deqEn[0]);
    return data[deqP[0]%nb];
  endmethod

  method Bool search(st s);
    Bool ret = False;
    for(Bit#(sz1) i = 0; i < nb; i = i + 1)
    begin
      let ptr = (deqP[0] + i)%nb;
      if(isFound(data[ptr], s) && i < cnt0)
        ret = True;
    end
    return ret;
  endmethod

  method Action clear;
    enqP[1] <= 0;
    deqP[1] <= 0;
    enqEn[1] <= True;
    deqEn[1] <= False;
  endmethod
endmodule

// {notEmpty, first} < deq < search
// search CF {enq, notFull}
// search < clear
module mkPipelineSFifo#(function Bool isFound(t v, st k))(SFifo#(n, t, st)) provisos(Bits#(t, tSz), Add#(n, 1, n1), Log#(n1, sz), Add#(sz, 1, sz1), Bits#(st, stz));
  Integer ni = valueOf(n);
  Bit#(sz1) nb = fromInteger(ni);
  Bit#(sz1) n2 = 2*nb;
  Vector#(n, Reg#(t)) data <- replicateM(mkRegU);
  Ehr#(3, Bit#(sz1)) enqP <- mkEhr(0);
  Ehr#(2, Bit#(sz1)) deqP <- mkEhr(0);

  Bit#(sz1) cnt0 = enqP[0] >= deqP[0]? enqP[0] - deqP[0]:
                                       (enqP[0]%nb + nb) - deqP[0]%nb;
  Bit#(sz1) cnt1 = enqP[0] >= deqP[1]? enqP[0] - deqP[1]:
                                       (enqP[0]%nb + nb) - deqP[1]%nb;

  method Bool notFull = cnt1 < nb;

  method Action enq(t x) if(cnt1 < nb);
    enqP[0] <= (enqP[0] + 1)%n2;
    data[enqP[0]%nb] <= x;
  endmethod

  method Bool notEmpty = cnt0 != 0;

  method Action deq if(cnt0 != 0);
    deqP[0] <= (deqP[0] + 1)%n2;
  endmethod

  method t first if(cnt0 != 0);
    return data[deqP[0]%nb];
  endmethod

  method Bool search(st s);
    Bool ret = False;
    for(Bit#(sz1) i = 0; i < nb; i = i + 1)
    begin
      let ptr = (deqP[1] + i)%nb;
      if(isFound(data[ptr], s) && i < cnt1)
        ret = True;
    end
    return ret;
  endmethod

  method Action clear;
    enqP[2] <= 0;
    deqP[1] <= 0;
  endmethod
endmodule

// Searchable Count FIFO has an extra search method which returns the count of the number of elements found
interface SCountFifo#(numeric type n, type t, type st);
  method Bool notFull;
  method Action enq(t x);
  method Bool notEmpty;
  method Action deq;
  method Bit#(TLog#(TAdd#(n, 1))) search(st s);
  method t first;
  method Action clear;
endinterface

// search is conflict-free with {enq, deq, first, notFull, notEmpty}
// search <  clear < canonicalize
module mkCFSCountFifo#(function Bool isFound(t v, st k))(SCountFifo#(n, t, st)) provisos(Bits#(t, tSz), Add#(n, 1, n1), Log#(n1, sz), Add#(sz, 1, sz1));
  Integer ni = valueOf(n);
  Bit#(sz1) nb = fromInteger(ni);
  Bit#(sz1) n2 = 2*nb;
  Vector#(n, Reg#(t)) data <- replicateM(mkRegU);
  Ehr#(3, Bit#(sz1)) enqP <- mkEhr(0);
  Ehr#(3, Bit#(sz1)) deqP <- mkEhr(0);
  Ehr#(3, Bool) enqEn <- mkEhr(True);
  Ehr#(3, Bool) deqEn <- mkEhr(False);
  Ehr#(2, t)                 tempData <- mkEhr(?);
  Ehr#(2, Maybe#(Bit#(sz1))) tempEnqP <- mkEhr(Invalid);
  Ehr#(2, Maybe#(Bit#(sz1))) tempDeqP <- mkEhr(Invalid);

  Bit#(sz1) cnt0 = enqP[0] >= deqP[0]? enqP[0] - deqP[0]: 
                                 (enqP[0]%nb + nb) - deqP[0]%nb;
  Bit#(sz1) cnt2 = enqP[2] >= deqP[2]? enqP[2] - deqP[2]: 
                                 (enqP[2]%nb + nb) - deqP[2]%nb;
  rule canonicalize;
    if(!enqEn[2] && cnt2 != nb) enqEn[2] <= True;
    if(!deqEn[2] && cnt2 != 0) deqEn[2] <= True;

    if(isValid(tempEnqP[1]))
    begin
      data[validValue(tempEnqP[1])] <= tempData[1];
      tempEnqP[1] <= Invalid;
    end

    if(isValid(tempDeqP[1]))
    begin
      deqP[0] <= validValue(tempDeqP[1]);
      tempDeqP[1] <= Invalid;
    end
  endrule

  method Bool notFull = enqEn[0];

  method Action enq(t x) if(enqEn[0]);
    tempData[0] <= x;
    tempEnqP[0] <= Valid (enqP[0]%nb);
    enqP[0] <= (enqP[0] + 1)%n2;
    enqEn[0] <= False;
  endmethod

  method Bool notEmpty = deqEn[0];

  method Action deq if(deqEn[0]);
    tempDeqP[0] <= Valid ((deqP[0] + 1)%n2);
    deqEn[0] <= False;
  endmethod

  method t first if(deqEn[0]);
    return data[deqP[0]%nb];
  endmethod

  method Bit#(TLog#(TAdd#(n, 1))) search(st s);
    Bit#(TLog#(TAdd#(n, 1))) ret = 0;
    for(Bit#(sz1) i = 0; i < nb; i = i + 1)
    begin
      let ptr = (deqP[0] + i)%nb;
      if(isFound(data[ptr], s) && i < cnt0)
        ret = ret + 1;
    end
    return ret;
  endmethod

  method Action clear;
    enqP[1] <= 0;
    deqP[1] <= 0;
    enqEn[1] <= True;
    deqEn[1] <= False;
  endmethod
endmodule
