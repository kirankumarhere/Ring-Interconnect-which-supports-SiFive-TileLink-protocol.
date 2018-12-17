package Connections;

import Ring :: *;
import RingNode :: *;
import CommonTypes :: *;
import StmtFSM :: *;
import FShow :: *;
import Fifo :: *;
import Vector :: *;

import core::*;
import Tilelink_Types :: *;
import Tilelink :: *;
import Memory_tilelink :: *;

import Connectable :: *;

`include "defined_parameters.bsv"

typedef 3 Num_masters;

typedef 2 Num_slaves;




(*synthesize*)

 module mkConnections(Empty);
 
 Vector#(4, Ifc_core_AXI4) cores <- replicateM(mkcore_AXI4('h1000)); // cores created..
 
 //Ifc_core_AXI4 cores[4];
 
 Vector#(4,Memory_IFC#(`SDRAMMemBase,`Addr_space)) mems <- replicateM(mkMemory("code.mem.MSB","code.mem.LSB","MainMEM"));
 
 //Memory_IFC#(`SDRAMMemBase,`Addr_space) mems[4] ;
 
 Ring#(8, Num_masters, Num_slaves) ring <- mkRing(); // ring nodes created..
 
 
 Integer i = 0;
 

 //connecting the cores to the routers..
 
 for (i = 0; i < 4; i = i+1) 
 begin
 
 mkConnection(cores[i].imem_master, ring.getNode(fromInteger(i)).get_master(0));
 
 mkConnection(cores[i].dmem_master_wr, ring.getNode(fromInteger(i)).get_master(1));
 
 mkConnection(cores[i].dmem_master_rd, ring.getNode(fromInteger(i)).get_master(2));
 
 end
 
 
 
//connecting the memories to the routers...
 
 for (i = 0; i < 4; i = i+1)
 begin

 mkConnection(ring.getNode(fromInteger(i+4)).get_slave(0), mems[i].main_mem_wr_slave); //write_slave..
 
 mkConnection(ring.getNode(fromInteger(i+4)).get_slave(1), mems[i].main_mem_rd_slave); //read_slave..
 
 end
 
 endmodule
 
 endpackage
