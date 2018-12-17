import FShow::*;
import CommonTypes::*;

import PacketToFlit::*;
import VcFifo::*;
import CrossBar::*;
import FlitToPacket::*;
import Vector ::*;

import Tilelink_Types :: *;
import Tilelink :: *;
`include "defined_parameters.bsv"

///////////////////////////////////////////////////////////////////////////////
// Important note: all following types should be power of 2 otherwise
//  synth tool fails :(

// number of packets assembled in flit-to-packet sub module
typedef 8 NofAssembeldPackets_t; 

// size of a PACKET_FIFO that stores the assembled packets ready to be fetched
//  by client
typedef 4 NofWaitingPkts_t;	  

// after DropTimeout_t cycles a packet will be dropped from PACKET_FIFO if it
//  wasn't fetched by user.
typedef 16 DropTimeout_t;

////////////////////////////////////////////////////////////////////////////////
// This interface defines a ring node's functionality as seen by the client.
//  Up ring direction denotes the direction of increasing nodeIds (0,1,2..N-1)
//  Donw ring direction is opposite to Up ring i.e. decresing nodeId (...,2,1,0)
// 
// IMPORTANT NOTE: 
//  Original interface didn't define how ring node communicate with peer ring
//  nodes. Thus we have to add interface methods to define the communication 
//  of ring node with upper and lower ring nodes.
////////////////////////////////////////////////////////////////////////////////
interface RingNode#(numeric type nofNodes, 
		    numeric type fltSz, 
		    numeric type numVC, 
		    numeric type num_masters,
		    numeric type num_slaves);

   // send a payload to node destination
   method Action enq(Packet#(nofNodes, `PADDR, `Reg_width, 4) packet);

   // read the first incoming message
   method Packet#(nofNodes, `PADDR, `Reg_width, 4) first();

   // dequeue the first incoming message
  // method Action deq();

   // get the endpoint's ID
   method Bit#(TLog#(nofNodes)) nodeID();
   
   //ADDED methods for communicating with upper & lower ring node

   // enque flit arriving from upper ring node
   method Action putUp(Flit_t#(nofNodes, fltSz, numVC) flit);
   
   // enque flit arriving from lower ring node
   method Action putDn(Flit_t#(nofNodes, fltSz, numVC) flit);
   
   // deque flit from upper ring node
   method ActionValue#(Flit_t#(nofNodes, fltSz, numVC)) getUp(); 

   // deque flit from lower ring node
   method ActionValue#(Flit_t#(nofNodes, fltSz, numVC)) getDn();
      
   method Bool notEmpty();
   method Bool notFull();
   
   method Ifc_master_tilelink_core_side#(`PADDR, `Reg_width, 4) get_master(Bit#(2) master_id);
   method Ifc_slave_tilelink_core_side#(`PADDR, `Reg_width, 4) get_slave(Bit#(1) slave_id);
   
endinterface


////////////////////////////////////////////////////////////////////////////////
// RingNode implementing module:
//  nodeId parameter is used to specify node's IDs.
////////////////////////////////////////////////////////////////////////////////
module mkRingNode#(parameter Integer nodeId) (RingNode#(nofNodes, fltSz, numVC, num_masters, num_slaves))
provisos(Mul#(TDiv#(PayloadSz, fltSz), fltSz, PayloadSz),Add#(unused, 2, TLog#(nofNodes)));


   Integer dropTimeout = valueOf(DropTimeout_t);
   
   //////////////////////////////////////////////////////////////////////
   // instantiation of internal modules:
   //////////////////////////////////////////////////////////////////////
   Reg#(Bit#(TLog#(nofNodes))) mem_count <- mkReg(0);
   
   Integer nofVCs = valueOf(numVC);
   
   PacketToFlit#(nofNodes, fltSz, numVC) packetToFlit <- mkPacketToFlit(nodeId);
   // flits from client
   VcFifo#(nofNodes, fltSz, numVC)  clientVcFifo <- mkVcFifo; 
   // flits from upper ring node
   VcFifo#(nofNodes, fltSz, numVC)  upRingVcFifo <- mkVcFifo; 
   // flits from lower ring node
   VcFifo#(nofNodes, fltSz, numVC) downRingVcFifo <- mkVcFifo;
   
   ThreeCrossBar#(nofNodes, Flit_t#(nofNodes, fltSz, numVC)) crossbar
    <- mkRingNodeCrossBar(nodeId);
   
   FlitToPacket#(nofNodes, fltSz, numVC, NofAssembeldPackets_t,
		 NofWaitingPkts_t) flitToPacket <- mkFlitToPacket(dropTimeout);
		 
   // Transactors facing masters...
   Vector#(num_masters, Ifc_Master_tilelink#(`PADDR, `Reg_width, 4)) xactors_masters <- replicateM(mkMasterFabric);

   // Transactors facing slaves...
   Vector#(num_slaves, Ifc_Slave_tilelink#(`PADDR, `Reg_width, 4)) xactors_slaves <- replicateM(mkSlaveFabric);		 

   //////////////////////////////////////////////////////////////////////
   // rules:
   //////////////////////////////////////////////////////////////////////
   
   (* descending_urgency="slave_response, master_request" *)
   
   rule master_request(xactors_masters[2].fabric_side_request.fabric_a_channel_valid || xactors_masters[1].fabric_side_request.fabric_a_channel_valid || xactors_masters[0].fabric_side_request.fabric_a_channel_valid);
   
   A_channel#(`PADDR, `Reg_width, 4) req = ?;
   
   //Bit#(3) l = 0; //slave link where the req has to be enqueued to(on the destination node)...
   
   if(xactors_masters[2].fabric_side_request.fabric_a_channel_valid) //d_mem read
   begin   
   
   req = xactors_masters[2].fabric_side_request.fabric_a_channel; 
   
   xactors_masters[2].fabric_side_request.fabric_a_channel_ready(True);
   
   req.a_source = (2 + fromInteger(nodeId*3));
   
   $display("req from dmem_read master..");
 //  l = 1; //slave's read link..
   
   end
   
   else if(xactors_masters[1].fabric_side_request.fabric_a_channel_valid) //d_mem write
   begin   
   
   req = xactors_masters[1].fabric_side_request.fabric_a_channel; 
   
   xactors_masters[1].fabric_side_request.fabric_a_channel_ready(True);
   
   req.a_source = (1 + fromInteger(nodeId*3));
   
    $display("req from dmem_write master..");
 //  l = 0; //slave's write link..
   
   end
   
   else if(xactors_masters[0].fabric_side_request.fabric_a_channel_valid) //i_mem
   begin
   
   req = xactors_masters[0].fabric_side_request.fabric_a_channel; 
   
   xactors_masters[0].fabric_side_request.fabric_a_channel_ready(True);
   
 //  l = 1; //slave's read link..
   
   req.a_source = fromInteger(nodeId*3);
   
   $display("req from i_mem master..");
   
   end
 
   
   
   Tilelink#(`PADDR, `Reg_width, 4) m = tagged Ch_a req;
   
   Packet#(nofNodes, `PADDR, `Reg_width, 4) p;
   
   p = Packet{peer: (4+mem_count), msg : m}; //packet destination as given as node 4....
   
   packetToFlit.enq(p);
   
   $display("@%4t rn%1d: enqueued a_channel request with a_source id : %0d                  ", $time, nodeId, req.a_source, fshow(p));
   
   if(mem_count == 3)
   mem_count <= 0;
   else
   mem_count <= mem_count + 1;
   
   
   endrule
   
   
   rule slave_response(xactors_slaves[1].fabric_side_response.fabric_d_channel_valid || xactors_slaves[0].fabric_side_response.fabric_d_channel_valid);
   
   D_channel#(`Reg_width, 4) resp = ?;
   
   if(xactors_slaves[1].fabric_side_response.fabric_d_channel_valid) //main_mem_rd_slave
   begin   
   
   resp = xactors_slaves[1].fabric_side_response.fabric_d_channel; 
   xactors_slaves[1].fabric_side_response.fabric_d_channel_ready(True);
   
   resp.d_sink = (1 + fromInteger(nodeId*2));
   
   
   end
   
   else if(xactors_slaves[0].fabric_side_response.fabric_d_channel_valid) //main_mem_wr_slave
   begin   
   
   resp = xactors_slaves[0].fabric_side_response.fabric_d_channel; 
   xactors_slaves[0].fabric_side_response.fabric_d_channel_ready(True);
   
   resp.d_sink = fromInteger(nodeId*2);
   end
   
   D_channel_ring#(`Reg_width, 4) resp_ring = ?;
   
   resp_ring.dummy = 0;
   resp_ring.d_opcode = resp.d_opcode;                     //Opcode encodings for response with data or just ack
   resp_ring.d_param = resp.d_param;
   resp_ring.d_size = resp.d_size;
   resp_ring.d_source = resp.d_source;
   resp_ring.d_sink = resp.d_sink;
   resp_ring.d_data = resp.d_data;	
   resp_ring.d_error = resp.d_error;
   
   
   Tilelink#(`PADDR, `Reg_width, 4) m = tagged Ch_d_ring resp_ring;
   
   Packet#(nofNodes, `PADDR, `Reg_width, 4) p;
   
   M_source d = resp.d_source;
   
   Bit#(TLog#(nofNodes)) dest = 0;
   
   if(d < 3)
   dest = 0;
   else if(d < 6)
   dest = 1;
   else if(d < 9)
   dest = 2;
   else if(d < 12)
   dest = 3;
   
   p = Packet{peer: dest, msg : m};
   
   packetToFlit.enq(p);
   
   $display("@%4t rn%1d: enqueued d_channel response...to be routed to %0d...  ", $time, nodeId,dest,fshow(p));
   
   endrule


   rule fromPacket2FlitToVCFifo;
      let flit = packetToFlit.first;
      $display("@%4t rn%1d: packetToFlit   -> clientVcFifo ", 
	       $time, nodeId, fshow(flit));
      packetToFlit.deq();
      clientVcFifo.put(flit);
   endrule


   (* fire_when_enabled *)
   rule fromClientVCFifoToCrossbar(clientVcFifo.notempty);
    let flit <- clientVcFifo.get();
    
    if(flit.valid == True)
    begin
      $display("@%4t rn%1d: clientVcFifo   -> crossbar     ", 
	       $time, nodeId, fshow(flit));
      flit.valid = False;
             
      crossbar.putPort1(flit.dest, flit);
    end
    else
    $display("dropped packet _ rule fromClientVCFifoToCrossbar..");  
    
   endrule
   
   
   (* fire_when_enabled *)
   rule fromUpVCFifoToCrossbar(upRingVcFifo.notempty);
      let flit <- upRingVcFifo.get();
      
     if(flit.valid == True)
      begin
      $display("@%4t rn%1d: upRingVcFifo   -> crossbar     ",
	       $time, nodeId, fshow(flit));
      flit.valid = False;       
      
      crossbar.putPort0(flit.dest, flit);
      end
      else
      $display("dropped packet _ rule fromUpVCFifoToCrossbar..");  
      
   endrule

 
   (* fire_when_enabled *)
   rule fromDownVCFifoToCrossbar( downRingVcFifo.notempty);
      let flit <- downRingVcFifo.get();
      
      if(flit.valid == True)
      begin
      $display("@%4t rn%1d: downRingVcFifo -> crossbar     ", 
	       $time, nodeId, fshow(flit));
	       
      flit.valid = False; 	       
      crossbar.putPort2(flit.dest, flit);
      end
      else 
      $display("dropped packet _ rule fromDownVCFifoToCrossbar..");
      
   endrule
   
   
   rule fromCrossbarToFlitToPacket;
      let flit <- crossbar.getPortSelf();
      $display("@%4t rn%1d: crossbar       -> flitToPacket ", 
	       $time, nodeId, fshow(flit));
      flitToPacket.enq(flit);
   endrule
   
   
   rule deq_routed_packet(flitToPacket.notEmpty);
   
   $display("@%4t rn%1d: deq packet                     ", 
	       $time, nodeId, fshow(flitToPacket.first));
	       
	       //we have to do put func for the ch_a and ch_d types here..
	       
	       Packet#(nofNodes, `PADDR, `Reg_width, 4) get_p = flitToPacket.first;
	       
	       Tilelink#(`PADDR, `Reg_width, 4) get_p_msg = get_p.msg;
	       
	       
	       if(get_p_msg matches tagged Ch_a .a)
	       begin
	       
	        if(a.a_source == 1 || a.a_source == 4 || a.a_source == 7 || a.a_source == 10 || a.a_source == 13)
	        begin
	       
	        if(xactors_slaves[0].fabric_side_request.fabric_a_channel_ready)//ready...
	        begin
	        xactors_slaves[0].fabric_side_request.fabric_a_channel(a); //slave's A-channel req..
	        flitToPacket.deq();
	        end
	       
	        end
	        else
	        begin
	       
                if(xactors_slaves[1].fabric_side_request.fabric_a_channel_ready)//ready...
                begin	       
	        xactors_slaves[1].fabric_side_request.fabric_a_channel(a); //slave's A-channel req..
	        flitToPacket.deq();
	        end
	       
	        end
	       
	       end
	       
	       else if(get_p_msg matches tagged Ch_d_ring .dr)
	       begin
	       
	        D_channel#(`Reg_width, 4) d = ?;
	        
	        d.d_opcode = dr.d_opcode;
	        d.d_param = dr.d_param;
	        d.d_size = dr.d_size;
	        d.d_source = dr.d_source;
	        d.d_sink = dr.d_sink;
	        d.d_data = dr.d_data;
	        d.d_error = dr.d_error;
	        
                M_source master_link;
                
                master_link = (d.d_source - fromInteger(nodeId*3));
	       
	       if(xactors_masters[master_link].fabric_side_response.fabric_d_channel_ready)  
	        begin
	        xactors_masters[master_link].fabric_side_response.fabric_d_channel(d); //this packet is sent and invalidated inside master_fabric code...so that the fabric_d_channel_ready becomes true for sending the next packet..
	        
	        flitToPacket.deq();
	        
	        end
	       
	       end
   
   endrule
   
   //////////////////////////////////////////////////////////////////////
   // methods:
   //////////////////////////////////////////////////////////////////////
 /*  
   method Action enq(Packet#(nofNodes) packet);
      $display("@%4t rn%1d: enq packet                     ", 
	       $time, nodeId, fshow(packet));
      packetToFlit.enq(packet);
   endmethod*/
   
   

   // read the first incoming message
   method Packet#(nofNodes, `PADDR, `Reg_width, 4) first = flitToPacket.first;
      
   // dequeue the first incoming message
   
   /*
   method Action deq();
      $display("@%4t rn%1d: deq packet                     ", 
	       $time, nodeId, fshow(flitToPacket.first));

      flitToPacket.deq();
   endmethod*/


   // get the endpoint's ID
   method Bit#(TLog#(nofNodes)) nodeID();
      return fromInteger(nodeId);
   endmethod

   method Action putUp(Flit_t#(nofNodes, fltSz, numVC) flit);
      $display("@%4t rn%1d: putUp flit                     ",
	       $time, nodeId, fshow(flit));
      upRingVcFifo.put(flit);
   endmethod

   method Action putDn(Flit_t#(nofNodes, fltSz, numVC) flit);
      $display("@%4t rn%1d: enqDn flit                     ",
	       $time, nodeId, fshow(flit));
      downRingVcFifo.put(flit);
   endmethod
   
   // deque flit from upper ring node
   method ActionValue#(Flit_t#(nofNodes, fltSz, numVC)) getUp(); 
      let flit <- crossbar.getPortUp();
      return flit;
   endmethod

   // deque flit from lower ring node
   method ActionValue#(Flit_t#(nofNodes, fltSz, numVC)) getDn();
      let flit <- crossbar.getPortDn();
      return flit;
   endmethod
   

   method Bool notEmpty = flitToPacket.notEmpty;
   method Bool notFull  = packetToFlit.notFull;
   
   
   method Ifc_master_tilelink_core_side#(`PADDR, `Reg_width, 4) get_master(Bit#(2) master_id);
   
   return xactors_masters[master_id].v_from_masters;
   
   endmethod 
   
   
   method Ifc_slave_tilelink_core_side#(`PADDR, `Reg_width, 4) get_slave(Bit#(1) slave_id);
   
   return xactors_slaves[slave_id].v_to_slaves;
   
   endmethod 
   
endmodule

