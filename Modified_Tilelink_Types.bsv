/*
Copyright (c) 2013, IIT Madras
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

*  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
*  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
*  Neither the name of IIT Madras  nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
*/

package Tilelink_Types;

`include "defined_parameters.bsv"
import GetPut ::*;
import FIFO ::*;
import SpecialFIFOs ::*;
import Connectable ::*;

`define TILEUH

Integer v_lane_width = valueOf(`LANE_WIDTH);

typedef enum {	Get_data=0
				,GetWrap=1
				,PutPartialData=2
				,PutFullData=3
				,ArithmeticData=4
				,LogicalData=5
				,Intent=6				
`ifdef TILEUC
				,Acquire=7
`endif
} Opcode deriving(Bits, Eq, FShow);			
			
typedef enum {	AccessAck
				,AccessAckData
				,HintAck
`ifdef TILEUC
				,Grant
				,GrantData
`endif
} D_Opcode deriving(Bits, Eq, FShow);			

typedef enum { Min,
			   Max,
			   MinU,
			   MaxU,
			   ADD 
} Param_arith deriving(Bits, Eq, FShow);

typedef enum { Min,
			   Max,
			   MinU,
			   MaxU,
			   ADD 
} Param_logical deriving(Bits, Eq, FShow);

typedef Bit#(3) Param;
typedef Bit#(4) Data_size; //In bytes
//typedef Bit#(2) M_source;
typedef Bit#(6) M_source;
typedef Bit#(5) S_sink;
typedef Bit#(`PADDR) Address_width;
typedef Bit#(`LANE_WIDTH) Mask;
typedef Bit#(TMul#(8,`LANE_WIDTH)) Data;

/* The A-channel is responsible for the master requests. The channel is A is split in control section(c) 
data section(d) where the read masters only use control section and write masters use both. For the slave side
where it receives the request has the channel A intact.
*/
typedef struct { 
		Opcode 			     a_opcode;                 //The opcode specifies if write or read requests
		Param  			     a_param;                  //Has the encodings for atomic transfers
		Bit#(z) 			 a_size;                   //The transfer size in 2^a_size bytes. The burst is calculated from here. if this is >3 then its a burst
		M_source 		     a_source;                 //Master ID
		Bit#(a)	 			 a_address;                //Address for the request
} A_channel_control#(numeric type a, numeric type z)  deriving(Bits, Eq, FShow);
		
typedef struct { 
		Bit#(TDiv#(w,8)) 			 a_mask;           //8x(bytes in data lane) 1 bit mask for each byte 
		Bit#(w)						 a_data;			//data for the request	
} A_channel_data#(numeric type w) deriving(Bits, Eq, FShow);

typedef struct { 
		Opcode 			     a_opcode;
		Param  			     a_param;
		Bit#(z)				 a_size;
		M_source 		     a_source;
		Bit#(a)				 a_address;
		Bit#(TDiv#(w,8))	 a_mask;
		Bit#(w)				 a_data;	
} A_channel#(numeric type a, numeric type w, numeric type z) deriving(Bits, Eq, FShow); //size is 116 bits..(8+z+a+w+(w/8))..


//cache-coherence channels
typedef struct {                                        
		Opcode 			     b_opcode;
		Param  			     b_param;
		Bit#(z)				 b_size;
		M_source 		     b_source;
		Bit#(a)				 b_address;
		Bit#(TDiv#(w,8))	 b_mask;
		Bit#(w)				 b_data;	
} B_channel#(numeric type a, numeric type w, numeric type z) deriving(Bits, Eq, FShow);

//cache-coherence channels
typedef struct { 
		Opcode 			     c_opcode;
		Param  			     c_param;
		Bit#(z)				 c_size;
		M_source 		     c_source;
		Bit#(a)				 c_address;
		Bit#(w)				 c_data;	
		Bool				 c_client_error;
} C_channel#(numeric type a, numeric type w, numeric type z) deriving(Bits, Eq);

//The channel D is responsible for the slave responses. It has the master ids and slave ids carried through the channel
typedef struct { 
		D_Opcode		d_opcode;                     //Opcode encodings for response with data or just ack
		Param  			d_param;
		Bit#(z)			d_size;
		M_source 		d_source;
		S_sink			d_sink;
		Bit#(w)			d_data;	
		Bool			d_error;
} D_channel#(numeric type w, numeric type z) deriving(Bits, Eq, FShow); //13+w+z...= 81

typedef struct { 
		S_sink					 d_sink;
} E_channel deriving(Bits, Eq);

typedef struct {Bit#(35)                dummy;
		D_Opcode		d_opcode;                     //Opcode encodings for response with data or just ack
		Param  			d_param;
		Bit#(z)			d_size;
		M_source 		d_source;
		S_sink			d_sink;
		Bit#(w)			d_data;	
		Bool			d_error;
} D_channel_ring#(numeric type w, numeric type z) deriving(Bits, Eq, FShow); //13+w+z...= 81


typedef union tagged {
A_channel_control#(a, z) Ch_a_control;
A_channel_data#(w)  Ch_a_data;
A_channel#(a, w, z) Ch_a;
D_channel#(w, z) Ch_d;

D_channel_ring#(w, z) Ch_d_ring;

} Tilelink#(numeric type a, numeric type w, numeric type z) deriving(Bits, Eq, FShow);




interface Ifc_core_side_master_link#(numeric type a, numeric type w, numeric type z);

	//Towards the master
	interface Put#(A_channel_data#(w)) master_request_data;
	interface Put#(A_channel_control#(a,z)) master_request_control;
	interface Get#(D_channel#(w,z)) master_response;

endinterface

interface Ifc_fabric_side_master_link#(numeric type a, numeric type w, numeric type z);

	//Towards the fabric
	interface Get#(A_channel_data#(w)) fabric_request_data;
	interface Get#(A_channel_control#(a,z)) fabric_request_control;
	interface Put#(D_channel#(w,z)) fabric_response;

endinterface

//--------------------------------------Master Xactor--------------------------------------//
/* This is a xactor interface which connects core and master side of the fabric*/
interface Ifc_Master_link#(numeric type a, numeric type w, numeric type z);

interface Ifc_core_side_master_link#(a,w,z) core_side;
interface Ifc_fabric_side_master_link#(a,w,z) fabric_side;

endinterface

/* Master transactor - should be instantiated in the core side and the fabric side interface of
of the xactor should be exposed out of the core*/
module mkMasterXactor#(Bool xactor_guarded, Bool fabric_guarded)(Ifc_Master_link#(a,w,z));

//Created a pipelined version that will have a critical path all along the bus. If we want to break the path we can 
//we should trade if off with area using the 2-sized FIFO 
`ifdef TILELINK_LIGHT
	FIFOF#(A_channel_control#(a,z)) ff_xactor_request_c <- mkGFIFOF(xactor_guarded, fabric_guarded); //control split of A-channel
	FIFOF#(A_channel_data#(w)) ff_xactor_request_d <- mkGFIFOF(xactor_guarded, fabric_guarded);   //data split of A-channel
	FIFOF#(D_channel#(w,z)) ff_xactor_response <- mkGFIFOF(xactor_guarded, fabric_guarded); //response channel D-channel exposed out
`else
	FIFO#(A_channel_control#(a,z)) ff_xactor_request_c <- mkSizedFIFO(2);
	FIFO#(A_channel_data#(w)) ff_xactor_request_d <- mkSizedFIFO(2);
	FIFO#(D_channel#(w,z)) ff_xactor_response <- mkSizedFIFO(2);
`endif

	Reg#(Bit#(z)) rg_burst_counter <- mkReg(0);
	Reg#(Bool) rg_burst[2] <- mkCReg(2,False);

// If it is a burst dont ask for address again. This rule about calculating the burst and control split of A-channel remains 
//constant till the burst finishes.
	rule rl_xactor_to_fabric_data;
		let req_addr = ff_xactor_request_c.first;
		Bit#(z) burst_size = 1;										  //The total number of bursts
		Bit#(z) transfer_size = req_addr.a_size;                        //This is the total transfer size including the bursts
		if(!rg_burst[0]) begin
			if(transfer_size > 3) begin
				rg_burst[0] <= True;
				transfer_size = transfer_size - 3;
				burst_size = burst_size << transfer_size;
				rg_burst_counter <= burst_size - 1;
			end
		end
		else begin
			rg_burst_counter <= rg_burst_counter - 1;                         
			if(rg_burst_counter==1)
				rg_burst[0] <= False;
		end

	endrule
	
	interface core_side = interface Ifc_core_side_master_link
		interface master_request_data = toPut(ff_xactor_request_d);
		interface master_request_control = toPut(ff_xactor_request_c);
		interface master_response = toGet(ff_xactor_response);
	endinterface;

	interface fabric_side = interface Ifc_fabric_side_master_link 
		interface fabric_request_control = interface Get    //Deque the control split of a channel if only burst is finished 
											 method ActionValue#(A_channel_control#(a,z)) get;  
												let req_addr = ff_xactor_request_c.first;
												if(!rg_burst[1])
													ff_xactor_request_c.deq;
												return req_addr;
											 endmethod
										   endinterface;
		interface fabric_request_data = toGet(ff_xactor_request_d);
		interface fabric_response = toPut(ff_xactor_response);
	endinterface;
	
endmodule

//------------------------------------------------------------------------------------------------------------------//


//------------------------------------------------------Slave Xactor------------------------------------------------//

//To be connected to slave side 
interface Ifc_core_side_slave_link#(numeric type a, numeric type w, numeric type z);
	interface Get#(A_channel#(a,w,z)) xactor_request;
	interface Put#(D_channel#(w,z)) xactor_response;
endinterface

//To be connected to fabric side
interface Ifc_fabric_side_slave_link#(numeric type a, numeric type w, numeric type z);
	//Doesn't need to have control and data signals separated as slaves get A_channel packet intact
	interface Put#(A_channel#(a,w,z)) fabric_request;
	interface Get#(D_channel#(w,z)) fabric_response;
endinterface

interface Ifc_Slave_link#(numeric type a, numeric type w, numeric type z);
	interface Ifc_core_side_slave_link#(a,w,z) core_side;
	interface Ifc_fabric_side_slave_link#(a,w,z) fabric_side;
endinterface

module mkSlaveXactor#(Bool xactor_guarded, Bool fabric_guarded)(Ifc_Slave_link#(a,w,z));

//Can choose between 2-sized FIFO and pipeline FIFO just like the master xactor
`ifdef TILELINK_LIGHT
	FIFOF#(A_channel#(a,w,z)) ff_xactor_request <- mkGFIFOF(xactor_guarded, fabric_guarded);
	FIFOF#(D_channel#(w,z)) ff_xactor_response <- mkGFIFOF(xactor_guarded, fabric_guarded);
`else
	FIFO#(A_channel#(a,w,z)) ff_xactor_request <- mkSizedFIFO(2);
	FIFO#(D_channel#(w,z)) ff_xactor_response <- mkSizedFIFO(2);
`endif

interface core_side = interface Ifc_core_side_slave_link;
	interface xactor_request = toGet(ff_xactor_request);
	interface xactor_response = toPut(ff_xactor_response);
endinterface;

interface fabric_side = interface Ifc_fabric_side_slave_link;
	interface fabric_request = toPut(ff_xactor_request);
	interface fabric_response = toGet(ff_xactor_response);
endinterface;

endmodule

//----------------------------------------------- Master Fabric -------------------------------------//

interface Ifc_Master_fabric_side_a_channel#(numeric type a, numeric type w, numeric type z);
	(* always_ready *)
	method A_channel#(a,w,z) fabric_a_channel;
	(* always_ready *)
	method Bool fabric_a_channel_valid;
	(* always_ready, always_enabled *)
	method Action fabric_a_channel_ready(Bool req_ready);
endinterface

interface Ifc_Master_fabric_side_d_channel#(numeric type w, numeric type z);
	(* always_ready, always_enabled *)
	method Action fabric_d_channel(D_channel#(w,z) resp);
	(* always_ready *)
	method Bool fabric_d_channel_ready;
endinterface

	//Communication with the xactor
interface Ifc_master_tilelink_core_side#(numeric type a, numeric type w, numeric type z);
	interface Put#(A_channel_control#(a,z)) xactor_request_control;
	interface Put#(A_channel_data#(w)) xactor_request_data;
	interface Get#(D_channel#(w,z)) xactor_response;
endinterface

interface Ifc_Master_tilelink#(numeric type a, numeric type w, numeric type z);

	interface Ifc_master_tilelink_core_side#(a,w,z) v_from_masters;

	//communication with the fabric
	interface Ifc_Master_fabric_side_d_channel#(w,z) fabric_side_response;
	interface Ifc_Master_fabric_side_a_channel#(a,w,z) fabric_side_request;
endinterface

module mkMasterFabric(Ifc_Master_tilelink#(a,w,z));

    Reg#(A_channel_control#(a,z)) rg_a_channel_c[2] <- mkCReg(2, A_channel_control { a_opcode : ?,
												`ifdef TILEUH	 a_param  : ?, `endif
																 a_size : ?,
																 a_source : ?,
																 a_address :  ? });
    Reg#(Maybe#(A_channel_data#(w))) rg_a_channel_d[2] <- mkCReg(2, tagged Invalid);
    Reg#(Maybe#(D_channel#(w,z))) rg_d_channel[2] <- mkCReg(2, tagged Invalid);

	interface v_from_masters = interface Ifc_master_tilelink_core_side
		interface xactor_request_control = interface Put
												method Action put(A_channel_control#(a,z) req_control);
													rg_a_channel_c[0] <= req_control;
													`ifdef verbose $display($time, "\tTILELINK : Request from Xactor control signals", fshow(req_control)); `endif
												endmethod
										   endinterface;

		interface xactor_request_data = interface Put
												method Action put(A_channel_data#(w) req_data);
													rg_a_channel_d[0] <= tagged Valid req_data;
													`ifdef verbose $display($time, "\tTILELINK : Request from Xactor data signals", fshow(req_data)); `endif
												endmethod
										endinterface;
												
		interface xactor_response = interface Get;
												method ActionValue#(D_channel#(w,z)) get if(isValid(rg_d_channel[1]));
													let resp = validValue(rg_d_channel[1]);
													rg_d_channel[1] <= tagged Invalid;
													`ifdef verbose $display($time, "\tTILELINK : Response to Xactor data signals", fshow(resp)); `endif
													return resp;
												endmethod
										endinterface;
	endinterface;
												
	interface fabric_side_response = interface Ifc_Master_fabric_side_d_channel
										method Action fabric_d_channel(D_channel#(w,z) resp);
											rg_d_channel[0] <= tagged Valid resp; 
										endmethod
										method Bool fabric_d_channel_ready;
											return !isValid(rg_d_channel[0]);
										endmethod
									endinterface;

	//while sending it to the fabric the control section and the data section should be merged
	interface fabric_side_request = interface Ifc_Master_fabric_side_a_channel
										method A_channel#(a,w,z) fabric_a_channel;
											let req = A_channel {a_opcode : rg_a_channel_c[1].a_opcode,
														`ifdef TILEUH	a_param : rg_a_channel_c[1].a_param, `endif
																		a_size : rg_a_channel_c[1].a_size,
																		a_source : rg_a_channel_c[1].a_source,
																		a_address : rg_a_channel_c[1].a_address,
																		a_mask : validValue(rg_a_channel_d[1]).a_mask,
																		a_data : validValue(rg_a_channel_d[1]).a_data};
											return req;
										endmethod
										method Bool fabric_a_channel_valid;           //master valid signal to the fabric
											return isValid(rg_a_channel_d[1]);
										endmethod
										method Action fabric_a_channel_ready(Bool req_ready); //master ready signal to the fabric
											if(req_ready)
												rg_a_channel_d[1] <= tagged Invalid;
										endmethod
									endinterface;

endmodule


//----------------------------------------------- Slave Fabric -------------------------------------//

interface Ifc_slave_tilelink_core_side#(numeric type a, numeric type w, numeric type z);
	//communication with the xactors
	interface Get#(A_channel#(a,w,z)) xactor_request;
	interface Put#(D_channel#(w,z)) xactor_response;
endinterface
interface Ifc_Slave_fabric_side_a_channel#(numeric type a, numeric type w, numeric type z);
	(* always_ready, always_enabled *)
	method Action fabric_a_channel(A_channel#(a,w,z) req);
	(* always_ready *)
	method Bool fabric_a_channel_ready;
endinterface

interface Ifc_Slave_fabric_side_d_channel#(numeric type w, numeric type z);
	(* always_ready *)
	method D_channel#(w,z) fabric_d_channel;
	(* always_ready *)
	method Bool fabric_d_channel_valid;
	(* always_ready, always_enabled *)
	method Action fabric_d_channel_ready(Bool req_ready);
endinterface

interface Ifc_Slave_tilelink#(numeric type a, numeric type w, numeric type z);

	interface Ifc_slave_tilelink_core_side#(a,w,z) v_to_slaves;

	//communication with the fabric
	interface Ifc_Slave_fabric_side_d_channel#(w,z) fabric_side_response;
	interface Ifc_Slave_fabric_side_a_channel#(a,w,z) fabric_side_request;

endinterface

module mkSlaveFabric(Ifc_Slave_tilelink#(a,w,z));

    Reg#(Maybe#(A_channel#(a,w,z))) rg_a_channel[2] <- mkCReg(2, tagged Invalid);
    Reg#(Maybe#(D_channel#(w,z))) rg_d_channel[2] <- mkCReg(2, tagged Invalid);


	interface v_to_slaves = interface Ifc_slave_tilelink_core_side ;
		interface xactor_request = interface Get
												method ActionValue#(A_channel#(a,w,z)) get if(isValid(rg_a_channel[1]));
													let req = validValue(rg_a_channel[1]);
													rg_a_channel[1] <= tagged Invalid;
													`ifdef verbose $display($time, "\tTILELINK : Slave side request to Xactor ", fshow(req)); `endif
													return req;
												endmethod
										   endinterface;

		interface xactor_response = interface Put
												method Action put(D_channel#(w,z) resp) if(!isValid(rg_d_channel[0]));
													`ifdef verbose $display($time, "\tTILELINK : Slave side response from Xactor ", fshow(resp)); `endif
													rg_d_channel[0] <= tagged Valid resp;
												endmethod
										   endinterface;
	endinterface;
												

	interface fabric_side_response = interface Ifc_Slave_fabric_side_d_channel
										method D_channel#(w,z) fabric_d_channel;
											return validValue(rg_d_channel[1]);
										endmethod
										method Bool fabric_d_channel_valid;
											return isValid(rg_d_channel[1]);
										endmethod
					//if the beat has been exchanged the packet can be invalidated on the sending side	
										method Action fabric_d_channel_ready(Bool req_ready);
											if(req_ready)
												rg_d_channel[1] <= tagged Invalid;
										endmethod
									endinterface;

	interface fabric_side_request = interface Ifc_Slave_fabric_side_a_channel
					//if the beat has been exchanged the packet can be invalidated on the sending side	
										method Action fabric_a_channel(A_channel#(a,w,z) req);
											rg_a_channel[0] <= tagged Valid req;
										endmethod
										method Bool fabric_a_channel_ready; 
											return !isValid(rg_a_channel[0]);
										endmethod
									endinterface;
endmodule

instance Connectable#(Ifc_fabric_side_master_link#(a,w,z), Ifc_master_tilelink_core_side#(a,w,z));
	//connectables between master transactors and master side of fabric	
	module mkConnection#(Ifc_fabric_side_master_link#(a,w,z) xactor, Ifc_master_tilelink_core_side#(a,w,z) fabric)(Empty);
		rule rl_connect_control_request;
			let x <-  xactor.fabric_request_control.get;
			fabric.xactor_request_control.put(x); 
		endrule
		rule rl_connect_data_request;
			let x <-  xactor.fabric_request_data.get;
			fabric.xactor_request_data.put(x); 
		endrule
		rule rl_connect_data_response;
			let x <- fabric.xactor_response.get; 
			xactor.fabric_response.put(x);
		endrule
	endmodule

endinstance

instance Connectable#( Ifc_slave_tilelink_core_side#(a,w,z), Ifc_fabric_side_slave_link#(a,w,z));
	//connectables between slave transactors and slave side of fabric	
	module mkConnection#(Ifc_slave_tilelink_core_side#(a,w,z) fabric, Ifc_fabric_side_slave_link#(a,w,z) xactor)(Empty);
		
		rule rl_connect_request;
			let x <- fabric.xactor_request.get;
			xactor.fabric_request.put(x);
		endrule
		rule rl_connect_data_response;
			let x <- xactor.fabric_response.get;
			fabric.xactor_response.put(x);
		endrule
	endmodule

endinstance

endpackage
