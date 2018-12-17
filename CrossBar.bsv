import CommonTypes::*;
import FIFOF::*;
import SpecialFIFOs::*; //for pipe-lined standard fifos (1-elements)
import RWire::*;
import Vector::*;
import FShow::*;


typedef enum {Up, Down}              Direction_t deriving ( Bits, Eq );
typedef enum {UpPort, DownPort, SelfPort} Port_t deriving ( Bits, Eq );

typedef struct {
   Vector#(2, Direction_t) level; /* each 2Xbar mux will use it's
				     level direction*/
   } RoutPath_t deriving( Bits, Eq );

typedef struct {
   RoutPath_t  path;
   t           data;
   } RoutRequest_t#(type t) deriving ( Bits, Eq );

//////////////////////////////////////////////////////////////////////
// override of the representation methods:
instance FShow#(Direction_t);
   function Fmt fshow (Direction_t d);
      case (d)
	 Up:   return fshow("Up");
	 Down: return fshow("Dn");
      endcase
   endfunction
endinstance

instance FShow#(RoutPath_t);
   function Fmt fshow (RoutPath_t path);
      return $format("<", fshow(path.level[0]), 
		     ",", fshow(path.level[1]), ">");
   endfunction
endinstance

instance FShow#(RoutRequest_t#(t)) provisos (Bits#(t, tSz), FShow#(t));
   function Fmt fshow (RoutRequest_t#(t) req);
      return $format("<", fshow(req.path), 
		     ",", fshow(req.data),">");
   endfunction
endinstance

////////////////////////////////////////////////////////////////////////////////
// Defines interface to 2 ports full crossbar. Ports named 'Up' and 'Dn' (Down)
////////////////////////////////////////////////////////////////////////////////
interface TwoCrossBar#(type t);
   method Action putPortUp(RoutRequest_t#(t) req);
   method Action putPortDn(RoutRequest_t#(t) req);
   method ActionValue#(RoutRequest_t#(t)) getPortUp;
   method ActionValue#(RoutRequest_t#(t)) getPortDn;
endinterface



////////////////////////////////////////////////////////////////////////////////
// Full crossbar router with 2 input ports and 2 output ports.
//  l (stands for level) is a parameter that tells the mux at what sate it's
//  instantiated i.e. using this module one may implement N-to-N full crossbar
//  module using N routing stages (or levels)
////////////////////////////////////////////////////////////////////////////////
module mkTwoCrossBar#(parameter Integer l) 
   (TwoCrossBar#(t)) provisos(Bits#(t, tSz));
   
   //staging flops of route requests when arrive/leaving the unit
   FIFOF#(RoutRequest_t#(t)) outPortUp <- mkPipelineFIFOF;
   FIFOF#(RoutRequest_t#(t)) outPortDn <- mkPipelineFIFOF;
   FIFOF#(RoutRequest_t#(t))  inPortUp <- mkPipelineFIFOF;
   FIFOF#(RoutRequest_t#(t))  inPortDn <- mkPipelineFIFOF;
   
   RWire#(RoutRequest_t#(t)) wireInUpReq <- mkRWire();
   RWire#(RoutRequest_t#(t)) wireInDnReq <- mkRWire();
   
   PulseWire flag_up <- mkPulseWire();
   PulseWire flag_dn <- mkPulseWire();
   
   // will be used to implement RR conflict resolution
   Reg#(Direction_t) portSelect <- mkReg(Up);
   
    rule processInPortUp if(inPortUp.notEmpty);
      wireInUpReq.wset(inPortUp.first);
      flag_up.send();
     // $display("firing process_in_port_up...");
      inPortUp.deq;
   endrule
   
   rule processInPortDn if(inPortDn.notEmpty);
      wireInDnReq.wset(inPortDn.first);
      flag_dn.send();
     // $display("firing process_in_port_dn...");
      inPortDn.deq;
   endrule
   
   
   // process the request from both input ports
   rule processRequests(flag_up || flag_dn);
      case (tuple2 (wireInUpReq.wget(), wireInDnReq.wget())) matches
	 {tagged Invalid ,tagged Invalid }: 
		noAction;
	 {tagged Valid .u,tagged Invalid }: 
		begin 
		   if( u.path.level[l] == Up ) outPortUp.enq(u);
		   else                        outPortDn.enq(u);

		end
	 {tagged Invalid ,tagged Valid .d}: 
		begin 
		   if( d.path.level[l] == Up ) outPortUp.enq(d);
		   else                        outPortDn.enq(d);
		   
		end
	 {tagged Valid .u,tagged Valid .d}: 
		begin
		   case(tuple2(u.path.level[l],
			       d.path.level[l])) matches
		      {tagged Up,   tagged Up  }: 
				       begin
                                       Direction_t portSel = portSelect;
                                       
	                               bit select = pack(portSelect);
	                               portSelect <= unpack(~select);
				       
					  if(portSel == Up) begin
					     outPortUp.enq(u);
					     
					     //d req is stalled
					  end
					  else begin//portSelect==Down
					     outPortUp.enq(d);
					     
					     //u req is stalled
					  end
				       end
		      {tagged Up,   tagged Down}: 
				       begin
					  outPortUp.enq(u);
					  outPortDn.enq(d);
				       end
		      {tagged Down, tagged Up}: 
				       begin
					  outPortUp.enq(d);
					  outPortDn.enq(u);
				       end
		      {tagged Down, tagged Down}: 
				       begin
				        
				        Direction_t portSel = portSelect;
                                       
	                                bit select = pack(portSelect);
	                                portSelect <= unpack(~select);
				       
					  if(portSel == Up) begin
					     outPortDn.enq(u);
					  end
					  else begin//portSelect==Down
					     outPortDn.enq(d);
					  end
				       end
		   endcase
		end
      endcase
      
   endrule
   
   
   method Action putPortUp(RoutRequest_t#(t) req);
      inPortUp.enq(req);
   endmethod
   
   method Action putPortDn(RoutRequest_t#(t) req);
      inPortDn.enq(req);
   endmethod
   
   method ActionValue#(RoutRequest_t#(t)) getPortUp;
      let res = outPortUp.first;
      outPortUp.deq;
      return res;
   endmethod

   method ActionValue#(RoutRequest_t#(t)) getPortDn;
      let res = outPortDn.first;
      outPortDn.deq;
      return res;
   endmethod
   
endmodule
   
   
   
////////////////////////////////////////////////////////////////////////////////
// Implements the routing table that decides where to route the 
//  current packed based on give-nodeId and the destinationId (filed
//  in the flit).
// The whole idea in this module is that it should be optimized
//  by synt' tool into a look-up table 
////////////////////////////////////////////////////////////////////////////////
interface RoutingTable#(numeric type nofNodes);
   method RoutPath_t getRoutPath(Address_t#(nofNodes) dest);
endinterface


module mkRoutingTable#(parameter Integer nodeId)
   (RoutingTable#(nofNodes));

   Integer n   = valueOf(nofNodes);
   Integer n_h = ( n%2==1 ) ? n/2 : (n-1)/2;
   
   Vector#(nofNodes, Port_t) routeTbl = replicate(SelfPort);
   
   Integer idx = 1;
   for( Integer i = 0 ; i < n/2; i = i + 1, idx = idx + 1 ) 
      routeTbl[idx] = UpPort;
   for( Integer i = 0 ; i < n_h; i = i + 1, idx = idx + 1 )
      routeTbl[idx] = DownPort;
   
   routeTbl = rotateBy( routeTbl, fromInteger(nodeId) ); //each node has its own routing table..
   
   
   //this method returns the output port required to route to the destination node..
   method RoutPath_t getRoutPath(Address_t#(nofNodes) dest);
      RoutPath_t path = ?;
      case( routeTbl[dest] ) 
	 UpPort   : begin 
		       path.level[0] = Up; 
		       path.level[1] = Up;
		    end
	 DownPort : begin 
		       path.level[0] = Up;   
		       path.level[1] = Down;
		    end
	 SelfPort : begin 
		       path.level[0] = Down;
		       path.level[1] = Up;
		    end
      endcase
      return path;
   endmethod
endmodule

////////////////////////////////////////////////////////////////////////////////
// This is a full cross bar (fxb) routing module that can rout any
//  data (payload) from any of its input ports (0,1,2) to any of its
//  output ports (Up, Dn, Self). Routing is based on the destination
//  address (appears explicitly in the put method) and the address
//  of a given node (where this module is instantiated)
////////////////////////////////////////////////////////////////////////////////
interface ThreeCrossBar#(numeric type nofNodes, type t);
   method Action putPort0(Address_t#(nofNodes) destAddr, t data);
   method Action putPort1(Address_t#(nofNodes) destAddr, t data);
   method Action putPort2(Address_t#(nofNodes) destAddr, t data);
   method ActionValue#(t) getPortUp;
   method ActionValue#(t) getPortDn;
   method ActionValue#(t) getPortSelf;
endinterface



module mkRingNodeCrossBar#(parameter Integer nodeId) 
   (ThreeCrossBar#(nofNodes, t)) provisos(Bits#(t, tSz),
					  FShow#(t));
   
   //instantiate routing table:
   RoutingTable#(nofNodes) routingTbl <- mkRoutingTable(nodeId);
   
   //instantiate a grid of 4 2xb routing modules:
   TwoCrossBar#(t) level0Up <- mkTwoCrossBar(0);
   TwoCrossBar#(t) level0Dn <- mkTwoCrossBar(0);
   TwoCrossBar#(t) level1Up <- mkTwoCrossBar(1);
   TwoCrossBar#(t) level1Dn <- mkTwoCrossBar(1);
   
   
   //Level-0 is the first pair of vertical crossbars...level-1 is the next pair... 
   rule rowUpToRowUp; //from level0-up out up to level1-up input up
      let data <- level0Up.getPortUp;
      level1Up.putPortUp(data);
   endrule
   
   rule rowUpToRowDn; //from level0-up out dn to level1-dn input up
      let data <- level0Up.getPortDn;
      level1Dn.putPortUp(data);
   endrule
   
   rule rowDnToRowUp;
      let data <- level0Dn.getPortUp;
      level1Up.putPortDn(data);
   endrule
   
   rule rowDnToRowDn;
      let data <- level0Dn.getPortDn;
      level1Dn.putPortDn(data);
   endrule
   
   /*This checker verifies there is no packet routed to down port
    * of level1-down crossbar */
  /* rule fatal;
      let data <- level1Dn.getPortDn;
      $display("Error @%t in %m assertion fail level1Dn.PortDn",
	       " isn't empty [", data, "] as expected");
      $finish;
   endrule*/
   
   method Action putPort0(Address_t#(nofNodes) destAddr, t data);
      let path = routingTbl.getRoutPath(destAddr);
      RoutRequest_t#(t) req = RoutRequest_t{path:path, data: data};
      level0Up.putPortUp(req); //level0_Up(port Up) is the first i/p port of the 2Xb in the first row....
      //$display("putPort0: ", fshow(req));
   endmethod
   
   method Action putPort1(Address_t#(nofNodes) destAddr, t data);
      let path = routingTbl.getRoutPath(destAddr);
      RoutRequest_t#(t) req = RoutRequest_t{path:path, data: data};
      level0Up.putPortDn(req); //level0_Up(port Down) is the second i/p port of the 2Xb in the first row....
    // $display("putPort1: ", fshow(req));
   endmethod
   
   method Action putPort2(Address_t#(nofNodes) destAddr, t data);
      let path = routingTbl.getRoutPath(destAddr);
      RoutRequest_t#(t) req = RoutRequest_t{path:path, data: data};
      level0Dn.putPortUp(req); //level1_Down(port Up) is the first i/p port of the 2Xb in the second row....
     // $display("putPort2: ", fshow(req));
   endmethod
   
   method ActionValue#(t) getPortUp;  
      let res <- level1Up.getPortUp;
      return res.data;
   endmethod

   method ActionValue#(t) getPortDn;  
      let res <- level1Up.getPortDn;
      return res.data;
   endmethod
   
   method ActionValue#(t) getPortSelf;
      let res <- level1Dn.getPortUp;
      return res.data;
   endmethod

endmodule

