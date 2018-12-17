/*
PacketToFlit module
*/
import FShow::*;
import CommonTypes::*;
import Fifo_guarded::*; //for pipleind n-elemenst fifos
import SpecialFIFOs::*; //for pipelined standard fifos (1-elements)
import FIFOF::*;
import Vector::*;
import Cntr::*;




import Tilelink_Types::*;
import Tilelink :: *;
`include "defined_parameters.bsv"

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

interface PacketToFlit#(numeric type nofNodes, 
			numeric type fltSz, 
			numeric type numVC);
   // put the packet into the unit, will be invoked by clinet
   method Action enq( Packet#(nofNodes, `PADDR, `Reg_width, 4) packet);
   // read a topmost flit of a unit, will invoked by VCFiFo
   method Flit_t#(nofNodes, fltSz, numVC) first();
   // remove the topmost flit and put the next one (if any) instead
   method Action deq();
   // true if the unit has any flits in it
   method Bool notEmpty();
   // true if the unit can accept more packets from a client
   method Bool notFull();
endinterface

module mkPacketToFlit#(parameter Integer nodeId)
   (PacketToFlit#(nofNodes, fltSz, numVC));
   
   //some ints i'm using here
   Integer flitFifoSize = valueOf(NofFlitsInPacket_t#(fltSz));
   
   Integer pktCountLim  = valueOf(TSub#(TExp#(PacketIdSize_t), 1));
   Integer fltCountLim  = flitFifoSize - 1;// for packets Ch_a,Ch_b,Ch_c
   Integer fltCountLim1  = 4;// for packets Ch_d
   Integer fltCountLim2  = 0;// for packets Ch_e
   
   
   Integer vcCountLim   = valueOf(numVC) - 1;
   
   //fifos
   FIFOF#(Packet#(nofNodes, `PADDR, `Reg_width, 4)) packetFifo <- mkPipelineFIFOF;
   Fifo_guarded#(NofFlitsInPacket_t#(fltSz),
	 Flit_t#(nofNodes, fltSz, numVC)) flitFifo <- mkPipelineFifo;
   //counters
   Cntr#(PacketId_t)       pktCount <- mkCntr(pktCountLim);
   
   Cntr#(FlitId_t#(fltSz)) fltCount <- mkCntr(fltCountLim);
   
   Cntr#(VcId_t#(numVC))    vcCount <- mkCntr(vcCountLim);

   /******************************************************************
    * This rule is activezed when we have a packet in a packetFifo.
    * Then every cycle we will enque a flit out of the arrived packet
    * into the flitFifo
    *****************************************************************/
   rule enqFlit if (packetFifo.notEmpty && flitFifo.notFull);
      
      Flit_t#(nofNodes, fltSz, numVC) flit = ?;
      
      Tilelink#(`PADDR, `Reg_width, 4) packet = packetFifo.first.msg;
       
      FlitPayload_t#(fltSz) flitsArr[flitFifoSize];
      
      //split the packet vector into vector of flits
      for( Integer i = 0; i < flitFifoSize; i = i + 1 ) begin
       	 flitsArr[i] =pack(packet)[ (i+1)*valueOf(fltSz) - 1 : i*valueOf(fltSz)];
      end
      
      flit.src = fromInteger(nodeId);
      flit.dest  = packetFifo.first.peer;
      flit.fltId = fltCount.getCount;
      
      flit.pktId = pktCount.getCount;
      
      if(packet matches tagged Ch_a .a)
      flit.vcId  = 0;
      //else if(packet matches tagged C_b .b)
      //flit.vcId  = 1;
      //else if(packet matches tagged C_c .c)
      //flit.vcId  = 2;
      else if(packet matches tagged Ch_d_ring .d)
      flit.vcId  = 1;
      //else if(packet matches tagged C_e .e)
      //flit.vcId  = 4;
      
      //flit.vcId  = vcCount.getCount;
      flit.data  = flitsArr[fltCount.getCount]; //choose the appropriate flit

      flit.valid = False;

      flitFifo.enq(flit);
      
      
     /* if(packet matches tagged C_a .a)
      begin 
      if (fltCount.getCount == fromInteger(fltCountLim)) begin
	 pktCount.increment;
	 //vcCount.increment;
	 packetFifo.deq;
      end  //flits of the same packet are allocated to same VC/
      end
      
      else if(packet matches tagged C_b .b)
      begin 
      if (fltCount.getCount == fromInteger(fltCountLim)) begin
	 pktCount.increment;
	 //vcCount.increment;
	 packetFifo.deq;
      end  //flits of the same packet are allocated to same VC/
      end
      
      else if(packet matches tagged C_c .c)
      begin 
      if (fltCount.getCount == fromInteger(fltCountLim)) begin
	 pktCount.increment;
	 //vcCount.increment;
	 packetFifo.deq;
      end  //flits of the same packet are allocated to same VC/
      end
      
      else if(packet matches tagged C_d .d)
      begin 
      //if (fltCount1.getCount == fromInteger(fltCountLim1)) begin
      if (fltCount.getCount == fromInteger(fltCountLim)) begin
	 pktCount.increment;
	 //vcCount.increment;
	 packetFifo.deq;
      end  //flits of the same packet are allocated to same VC/
      end
      else if(packet matches tagged C_e .e)
      begin 
      //if (fltCount2.getCount == fromInteger(fltCountLim2)) begin
      if (fltCount.getCount == fromInteger(fltCountLim)) begin
	 pktCount.increment;
	 //vcCount.increment;
	 packetFifo.deq;
      end  //flits of the same packet are allocated to same VC/
      end*/
      
      
      
      //it's a last flit of a pkt
    /*  if (fltCount.getCount == fromInteger(fltCountLim)) begin
	pktCount.increment;
	 //vcCount.increment;
	 packetFifo.deq;
      end  //flits of the same packet are allocated to same VC/*/
      
      if (fltCount.getCount == fromInteger(fltCountLim)) 
      begin
	 pktCount.increment;
	 //ct <= (ct + 1);
   $display("All flits of the packet %0d has been sent... Packet is being dequeued... Packet count is incremented....", pktCount.getCount);
	 //vcCount.increment;
	 packetFifo.deq;
      end
      
     fltCount.increment;
     
     
     
     /* if(packet matches tagged C_a .a) 
      fltCount.increment;
      else if(packet matches tagged C_b .b)
      fltCount.increment;
      else if(packet matches tagged C_c .c) 
      fltCount.increment; 
      else if(packet matches tagged C_d .d)
      fltCount.increment;
      //fltCount1.increment;
      else
      fltCount.increment;
      //fltCount2.increment;
      
      */
   endrule
   
   ///////////////////////////////////////////////////////////////////
   /// methods implementation
   ///////////////////////////////////////////////////////////////////
   method Action enq(Packet#(nofNodes,`PADDR, `Reg_width, 4) packet) if (packetFifo.notFull);
//      $display("@%4t p2f: enq packet ", $time, fshow(packet));
      packetFifo.enq(packet);
   endmethod
   
   method Action deq() if (flitFifo.notEmpty);
//      $display("@%4t p2f: deq flit ", $time, fshow(flitFifo.first));
      flitFifo.deq;
   endmethod
   
   method Flit_t#(nofNodes,fltSz,numVC) first = flitFifo.first;
      
   method Bool notEmpty = flitFifo.notEmpty;
   
   method Bool notFull  = packetFifo.notFull;

   

endmodule

