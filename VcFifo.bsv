import CommonTypes::*;
import Fifo::*;
import FShow::*;
import AscArbiter::*;
import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;

interface VcFifo#(numeric type nofNodes, 
		  numeric type fltSz, 
		  numeric type numVC);
   //put a flit into vc fifo
   method Action put(Flit_t#(nofNodes, fltSz, numVC) flit);

   //remove the topmost flit out of vc fifo
   method ActionValue#(Flit_t#(nofNodes, fltSz, numVC)) get();
   
   method Bool full(Bit#(TLog#(numVC)) vcId);
   
   method Bool notempty();
    
endinterface


module mkVcFifo(VcFifo#(nofNodes, fltSz, numVC))
 provisos(Log#(numVC, numVCSz));
   
   Integer nofVCs = valueOf(numVC);
   
   //vc fifos array.....
  
  Fifo#(NofFlitsInPacket_t#(fltSz), 
	 Flit_t#(nofNodes, fltSz, numVC)) vcFifoArr[nofVCs];
	 

//init loop to create all fifos
   for (Integer i = 0; i < nofVCs; i = i + 1) begin
      vcFifoArr[i]<-mkCFFifo;
   end
	 
	 
   Arbiter_IFC#(numVC) arbiter <- mkAscArbiter;

   /////////////////////////////////////////////////////////////////////
   /// rules
   /////////////////////////////////////////////////////////////////////
   for (Integer i=0; i < nofVCs; i = i + 1) begin
      //every non empty fifo bids the arbiter
      rule bid if ( vcFifoArr[i].notEmpty() );
	 arbiter.clients[i].request();
      endrule
   end
   
   
 /////////debugging////////
 /* rule disp_grant;
   
   if(vcFifoArr[0].notEmpty())
   $display("notEmpty_0");
   else
   $display("Empty_0");
   
   if(vcFifoArr[1].notEmpty())
   $display("notEmpty_1");
   else
   $display("Empty_1");
   
   //let winFifoId = arbiter.grant_id;
   //$display("grant_id: %0d",winFifoId);
   
   endrule*/
   
   ////////////////////////////////////////////////////////////////////
   
   // interface methods implementation 
   
   method Action put(Flit_t#(nofNodes, fltSz, numVC) flit);
      vcFifoArr[flit.vcId].enq(flit);
      $display("enq being done in VCFifo : %0d", flit.vcId);
      
   endmethod

   method ActionValue#(Flit_t#(nofNodes, fltSz, numVC)) get();
   
      //deque from current non empty fifo
      let winFifoId = arbiter.grant_id;
      
           
      $display("deq in VCFifo : %0d", winFifoId);
      let res = vcFifoArr[winFifoId].first;
      
      if(vcFifoArr[winFifoId].notEmpty)
      res.valid = True;
      else 
      res.valid = False;
      
      vcFifoArr[winFifoId].deq;
      return res;
      
      
   endmethod

   
   method Bool full(Bit#(TLog#(numVC)) vcId);
   
   return !(vcFifoArr[vcId].notFull);

   endmethod
   
   
   method Bool notempty();
   
   Bool flag = False;
   
   for(Integer i = 0; i < nofVCs; i = i+1)
   begin
    if(vcFifoArr[i].notEmpty)
    flag = True;
   end
   
   return flag;
    
   endmethod

endmodule
