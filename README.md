# Ring-Interconnect-which-supports-SiFive-TileLink-protocol.

Ring interconnect in Bluespec SystemVerilog which supports SiFive TileLink protocol(The specification is attached as a pdf file alongwith the code for reference). 

Stages of the router:
Fetches the TileLink protocol packet from the Client node;
Persorms Packet to Flits conversion; 
Takes care of Route Computation, Virtual Channel allocation, Switch Allocation, Switch and Link Traversal for the flit (which helps the flit to reach the destination router from the source router); 
Performs recombination of the Flits into a TileLink packet at the destination node router;
Packet delivery from destination router to the destination client.

Compiled the interconnect’s code with the recently fabricated India’s first microprocessor’s(SHAKTI 64-bit C-class) code{Link: https://bitbucket.org/casl/c-class/src/daca4f5c4c058c5f07768eb930411df1e7f5d632?at=master}. 
Successfully simulated the interconnect in Bluesim environment by generating requests for the cores from Automatic Assembly Program Generator(AAPG). 
Check the attached image Block_Diagram.png for better understanding.
