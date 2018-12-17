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

package Memory_tilelink;
	/*====== Project imports ====*/
	import defined_types::*;
	`include "defined_parameters.bsv"
	import Tilelink_Types   :: *;
	import tilelink_addr_generator::*;
	/*==== Package imports ======*/
  	import BRAMCore :: *;
	import DReg::*;
	import BUtils::*;
	import GetPut ::*;
	/*============================*/

	//interface Memory_slave_wr_link;
	//	interface  Put#(A_channel) wr_mem_slave_xactor_req;
	//	interface  Get#(D_channel) wr_mem_slave_xactor_resp;
	//endinterface
	//interface Memory_slave_rd_link;
	//	interface  Put#(A_channel) rd_mem_slave_xactor_req;
	//	interface  Get#(D_channel) rd_mem_slave_xactor_resp;
	//endinterface
	interface Memory_IFC#(numeric type base_address, numeric type mem_size);
		interface Ifc_fabric_side_slave_link#(`PADDR, `Reg_width, 4) main_mem_wr_slave;
		interface Ifc_fabric_side_slave_link#(`PADDR, `Reg_width, 4) main_mem_rd_slave;
	endinterface
	typedef enum{Idle,HandleBurst} Mem_state deriving(Bits,Eq);
	module mkMemory #(parameter String mem_init_file1 `ifdef RV64 , parameter String mem_init_file2 `endif  ,parameter String module_name) (Memory_IFC#(base_address,mem_size));
		
		BRAM_DUAL_PORT_BE#(Bit#(TSub#(mem_size,2)),Bit#(32),4) dmemMSB <- mkBRAMCore2BELoad(valueOf(TExp#(TSub#(mem_size,2))),False,mem_init_file1,False);
		BRAM_DUAL_PORT_BE#(Bit#(TSub#(mem_size,2)),Bit#(32),4) dmemLSB <- mkBRAMCore2BELoad(valueOf(TExp#(TSub#(mem_size,2))),False,mem_init_file2,False);
	
		Ifc_Slave_link#(`PADDR, `Reg_width, 4)  wr_s_xactor <- mkSlaveXactor(True, True);
		Ifc_Slave_link#(`PADDR, `Reg_width, 4)  rd_s_xactor <- mkSlaveXactor(True, True);
	
		Reg#(Mem_state) rd_state <-mkReg(Idle);
		Reg#(Mem_state) wr_state <-mkReg(Idle);
		Reg#(Bit#(12)) rg_readburst_counter<-mkReg(0);
		Reg#(Bit#(12)) rg_wr_burst_counter<-mkReg(0);
		Reg#(A_channel#(`PADDR, `Reg_width, 4)) rg_read_packet <-mkReg(?);														   // hold the read packet during bursts
		Reg#(Bit#(`PADDR)) rg_write_packet<-mkReg(?); // hold the write packer during bursts
	
		rule rl_wr_respond(wr_state==Idle);
	      let aw <- wr_s_xactor.core_side.xactor_request.get;
			Bit#(TSub#(mem_size,2)) index_address=(aw.a_address-fromInteger(valueOf(base_address)))[valueOf(mem_size)-1:`byte_offset+1];
			dmemLSB.b.put(aw.a_mask[3:0],index_address,truncate(aw.a_data));
			dmemMSB.b.put(aw.a_mask[7:4],index_address,truncateLSB(aw.a_data));
			let b = D_channel { d_opcode : AccessAck, d_param : 0, d_size : aw.a_size, d_source : aw.a_source, d_sink : ?, d_data : ?, d_error : False};  
			if(aw.a_size>3) begin
				Data_size beat_blocks = aw.a_size - 3;
				Bit#(12) burst_counter = 1;
				burst_counter = burst_counter << beat_blocks;
				rg_wr_burst_counter <= burst_counter-1;
				wr_state<=HandleBurst;
				let {size, new_address}=burst_address_generator(aw.a_opcode, aw.a_mask, aw.a_address, aw.a_size);
				aw.a_address=new_address;
				rg_write_packet<=new_address;
			end
			else
		     	wr_s_xactor.core_side.xactor_response.put(b);
			`ifdef verbose $display($time,"\t",module_name,":\t Recieved Write Request for Index Address: %h data: %h strb: %b",index_address, aw.a_data,aw.a_mask);  `endif
		endrule
	
		rule rl_wr_burst_response(wr_state==HandleBurst);
	      	let w  <- wr_s_xactor.core_side.xactor_request.get;
			let b = D_channel { d_opcode : AccessAck, d_param : 0, d_size : w.a_size, d_source : w.a_source, d_sink : ?, d_data : ?, d_error : False};  
			if(rg_wr_burst_counter==1) begin
				wr_state<=Idle;
				wr_s_xactor.core_side.xactor_response.put (b);
			end
			else begin
				rg_wr_burst_counter <= rg_wr_burst_counter - 1;
				Bit#(TSub#(mem_size,2)) index_address=(rg_write_packet-fromInteger(valueOf(base_address)))[valueOf(mem_size)-1:`byte_offset+1];
				dmemLSB.b.put(w.a_mask[3:0],index_address,truncate(w.a_data));
				dmemMSB.b.put(w.a_mask[7:4],index_address,truncateLSB(w.a_data));
				let {size, new_address} =burst_address_generator(w.a_opcode, w.a_mask, rg_write_packet, w.a_size);
				rg_write_packet<=new_address;
			end
			`ifdef verbose $display($time,"\t",module_name,":\t BURST Write Request for Address: %h data: %h strb: %b",rg_write_packet,w.a_address,w.a_mask);  `endif
		endrule
		
		rule rl_rd_request(rd_state==Idle);
			let ar<- rd_s_xactor.core_side.xactor_request.get;
			let {mask, address} = tuple2(ar.a_mask, ar.a_address); 
			ar.a_mask = mask;
			ar.a_address = address;
			rg_read_packet<= ar;
			Bit#(TSub#(mem_size,2)) index_address=(ar.a_address-fromInteger(valueOf(base_address)))[valueOf(mem_size)-1:`byte_offset+1];
			dmemLSB.a.put(0,index_address,?);
			dmemMSB.a.put(0,index_address,?);
			Data_size beat_blocks = ar.a_size - 3;
			Bit#(12) burst_counter = 1;
			burst_counter = burst_counter << beat_blocks;
			rg_readburst_counter <= burst_counter-1;
			rd_state<=HandleBurst;
			`ifdef verbose $display($time,"\t",module_name,"\t Recieved Read Request for Address: %h Index Address: %h",ar.a_address,index_address);  `endif
		endrule
	
		rule rl_rd_response(rd_state==HandleBurst);
		   	Bit#(`Reg_width) data0 = {dmemMSB.a.read(),dmemLSB.a.read()};
			$display("raw data %h", data0);
			let ar = rg_read_packet;
			let mask = ar.a_mask;
			let addr = ar.a_address;
			let {size, address} = burst_address_generator(ar.a_opcode, mask, addr, ar.a_size);	
	       	let r = D_channel {d_opcode : AccessAckData, d_param : 0, d_size: size, d_source : ar.a_source, 
																		d_data : data0,  d_error: False};
			Bit#(TMul#(`LANE_WIDTH,2)) mask_double = zeroExtend(mask);
			mask_double = mask_double << size;
			mask = mask_double[2*v_lane_width-1: v_lane_width] | mask_double[v_lane_width-1:0]; // this is for the wrap
			ar.a_mask = mask;
			ar.a_address = address;
			if(size[0]==1) begin
				if(addr[2:0] == 0)
					r.d_data = duplicate(data0[7:0]);
				else if(addr[2:0] == 1)
					r.d_data = duplicate(data0[15:8]);
				else if(addr[2:0] == 2)
					r.d_data = duplicate(data0[23:16]);
				else if(addr[2:0] == 3)
					r.d_data = duplicate(data0[31:24]);
				else if(addr[2:0] == 4)
					r.d_data = duplicate(data0[39:32]);
				else if(addr[2:0] == 5)
					r.d_data = duplicate(data0[47:40]);
				else if(addr[2:0] == 6)
					r.d_data = duplicate(data0[55:48]);
				else if(addr[2:0] == 7)
					r.d_data = duplicate(data0[63:56]);
			end
			else if(size[1]==1) begin
				if(addr[2:0] == 0)
					r.d_data = duplicate(data0[15:0]);
				else if(addr[2:0] == 2)
					r.d_data = duplicate(data0[31:16]);
				else if(addr[2:0] == 4)
					r.d_data = duplicate(data0[47:32]);
				else if(addr[2:0] == 6)
					r.d_data = duplicate(data0[63:48]);
			end
			else if(size[2]==1) begin
				if(addr[2:0] == 0)
					r.d_data = duplicate(data0[31:0]);
				else if(addr[2:0] == 4)
					r.d_data = duplicate(data0[63:32]);
			end
	       	rd_s_xactor.core_side.xactor_response.put(r);
			Bit#(TSub#(mem_size,2)) index_address=(address-fromInteger(valueOf(base_address)))[valueOf(mem_size)-1:`byte_offset+1];
			if(rg_readburst_counter==0)begin
				rd_state<=Idle;
			end
			else begin
				dmemLSB.a.put(0,index_address,?);
				dmemMSB.a.put(0,index_address,?);
				rg_readburst_counter<=rg_readburst_counter-1;
			end
			rg_read_packet <= ar;
			Bit#(64) new_data=r.d_data;
			`ifdef verbose $display($time,"\t",module_name,"\t Responding Read Request with CurrAddr: %h Data: %8h BurstCounter: %d NextAddress: %h",addr,new_data,rg_readburst_counter,address);  `endif
	   endrule
	
		interface main_mem_wr_slave = wr_s_xactor.fabric_side;
		interface main_mem_rd_slave = rd_s_xactor.fabric_side;
	endmodule
endpackage
