package Ring;

import Vector::*;
import FShow::*;
import CommonTypes::*;
import RingNode::*;


import Tilelink_Types :: *;
import Tilelink :: *;
//////////////////////////////////////////////////////////////////////
// IMPORTANT NOTE:
// The following types:
//   PayloadSz
//   Payload
//   Packet
// were moved to CommonTypes.bsv file. Otherwise they cause a circular 
// dependancy as explaned below:
// 1. RingNode should include Ring to know these types hence
//    RingNode->Ring
// 2. Ring should include RingNode cause it instantiates RingNodes to
//    form a ring :) thus: Ring->RingNode
// Now 1 and 2 form a circular include depandancy
//
//////////////////////////////////////////////////////////////////////

typedef 30 FlitSize_t; // size of a flit, have to satisfy the equation
		       //  (packet_size % flit_size == 0)		       
		       		       
		       
typedef 2 NumberOfVCs_t; // number of virtual channels in a system

//////////////////////////////////////////////////////////////////////
/// Ring interface. The parameter is the type used to specify node IDs.
//////////////////////////////////////////////////////////////////////


interface Ring#(numeric type nofNodes, numeric type num_masters, numeric type num_slaves);
   
   // get a specific endpoint in the ring. 
   method RingNode#(nofNodes, FlitSize_t, NumberOfVCs_t, num_masters, num_slaves) 
    getNode(Bit#(TLog#(nofNodes)) idx);

endinterface

//////////////////////////////////////////////////////////////////////
/// module implementation
//////////////////////////////////////////////////////////////////////
module mkRing(Ring#(nofNodes, num_masters, num_slaves)) provisos(Add#(unused, 2, TLog#(nofNodes)));

   
   Integer iNofNodes = valueOf(nofNodes);
   
   
   RingNode#(nofNodes, FlitSize_t, NumberOfVCs_t, num_masters, num_slaves) nodeVector[valueOf(nofNodes)];
   for (Integer i = 0; i < iNofNodes; i = i + 1) begin
      nodeVector[i]<-mkRingNode(i); // create all ring nodes
   end
   
   // connect all nodes to form a ring ///////////////////////////////
   for (Integer i = 0; i < iNofNodes; i = i+1) begin
	 
      let curNode = nodeVector[i];
      let nextNode = nodeVector[(i+1)%iNofNodes];
      
      rule putFlitToNext;
	 let flit <- curNode.getUp();
	 $display("@%4t rn%1d: sending flit to Up-Ring ...    ", 
	    $time, i, fshow(flit));
	   nextNode.putDn(flit);
	   
	/* let flit <- curNode.checkUp();
	     
	 if(nextNode.ful(2,flit.vcId) == True)   
	 $display("DownRingFifo of next Node is FULL...");
	 else
	 begin
	 $display("DownRingFifo of next Node is still not FULL...");
	 
	 $display("@%4t rn%1d: sending flit to Up-Ring...    ", 
	 $time, i, fshow(flit));
	 
	 nextNode.putDn(flit);
	 end*/
	 

      endrule
      
      rule getFlitFromNext;
	 let flit <- nextNode.getDn();
	 $display("@%4t rn%1d: getting flit from Up-Ring ...  ", 
	    $time, i, fshow(flit));
	 curNode.putUp(flit);
	 
	/* let flit <- curNode.checkDn();
	 
	 if(nextNode.ful(1,flit.vcId) == True) 
	 $display("UpRingFifo of next Node is FULL...");
	 else
	 begin
	 $display("UpRingFifo of next Node is still not FULL...");
	 
	 $display("@%4t rn%1d: sending flit to Down-Ring...", 
	 $time, i, fshow(flit));
	 
	 nextNode.putUp(flit);
	 end*/
	 
      endrule
   end
   
   //////////////////////////////////////////////////////////////////////
   method RingNode#(nofNodes, FlitSize_t, NumberOfVCs_t, num_masters, num_slaves) 
    getNode(Bit#(TLog#(nofNodes)) idx);
      return nodeVector[idx];
   endmethod
   
endmodule


endpackage
