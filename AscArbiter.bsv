package AscArbiter;

import Vector::*;
import BUtils::*;
import Connectable::*;

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

interface ArbiterClient_IFC;
   method Action request();
   method Action lock();
   method Bool grant();
endinterface

interface ArbiterRequest_IFC;
   method Bool request();
   method Bool lock();
   method Action grant();
endinterface

interface Arbiter_IFC#(numeric type count);
   interface Vector#(count, ArbiterClient_IFC) clients;
   method    Bit#(TLog#(count))                grant_id;
endinterface


module mkAscArbiter(Arbiter_IFC#(count));

   let icount = valueOf(count);

   Wire#(Vector#(count, Bool)) grant_vector   <- mkBypassWire;
   Wire#(Bit#(TLog#(count)))   grant_id_wire  <- mkBypassWire;
   Vector#(count, PulseWire) request_vector <- replicateM(mkPulseWire);

   rule every (True);

      // calculate the grant_vector
      Vector#(count, Bool) zow = replicate(False);
      Vector#(count, Bool) grant_vector_local = replicate(False);
      Bit#(TLog#(count)) grant_id_local = 0;

      Bool found = False;

     //   for (Integer x = (2 * icount - 1); x >= 0; x = x - 1)
      
      for (Integer x = (icount - 1); x >= 0; x = x - 1)
	 begin

	    Integer y = (x % icount);

	    let a_request = request_vector[y];
	    zow[y] = a_request;

	    if (!found && a_request)
	       begin
		  grant_vector_local[y] = True;
		  grant_id_local        = fromInteger(y);
		  found = True;
	       end
	 end

      // Update the RWire
      grant_vector  <= grant_vector_local;
      grant_id_wire <= grant_id_local;
      
      //  $display("(%5d)   request vector: %4b", $time, zow);
      //  $display("(%5d)     Grant vector: %4b", $time, grant_vector_local);
      // $display("(%5d)     Grant-id: %0d", $time, grant_id_local);

   endrule

   // Now create the vector of interfaces
   Vector#(count, ArbiterClient_IFC) client_vector = newVector;

   for (Integer x = 0; x < icount; x = x + 1)

      client_vector[x] = (interface ArbiterClient_IFC

			     method Action request();
				request_vector[x].send();
			     endmethod

			     method Action lock();
				dummyAction;
			     endmethod

			     method grant();
				return grant_vector[x];
			     endmethod
			  endinterface);

   interface clients = client_vector;
   method    grant_id = grant_id_wire;
endmodule

endpackage
