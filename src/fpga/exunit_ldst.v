`include "constants.vh"
`include "alu_ops.vh"
//`default_nettype none

module exunit_ldst
  (
   input wire 			 clk,
   input wire 			 reset,
   input wire [`DATA_LEN-1:0] 	    ex_src1,
   input wire [`DATA_LEN-1:0] 	    ex_src2,
   input wire [`ADDR_LEN-1:0] 	    pc,
   input wire [`DATA_LEN-1:0] 	    imm,
   input wire [`MEM_TYPE_WIDTH-1:0] funct3, 
   input wire                       dstval,
   input wire [`SPECTAG_LEN-1:0]    spectag,
   input wire 			            specbit,
   input wire 			            issue,
   input wire 			            prmiss,
   input wire [`SPECTAG_LEN-1:0]    spectagfix,
   input wire [`RRF_SEL-1:0] 	    rrftag,
   output wire [`DATA_LEN-1:0] 	    result,
   output wire 			            rrf_we,
   output wire 			            rob_we, //set finish
   output wire [`RRF_SEL-1:0] 	    wrrftag,
   output wire 			            kill_speculative,
   output wire 			            busy_next,
   //Signal dcache
   input wire                       cache_busy,
   input wire[1:0]                  cache_done,
   //output reg                       cache_req,
   //Signal StoreBuf
   output wire 			            stfin,
   //Store
   output wire 			            memoccupy_ld,
   input wire 			            fullsb,
   output wire [`DATA_LEN-1:0] 	    storedata,
   output wire [`ADDR_LEN-1:0] 	    storeaddr,
   //Load
   input wire 			            hitsb,
   input wire [`MEM_TYPE_WIDTH-1:0] ldfunct3,
   output wire [`ADDR_LEN-1:0] 	    ldaddr,
   input wire [`DATA_LEN-1:0] 	    lddatasb,
   input wire [4*`DATA_LEN-1:0] 	lddatamem
   );

   reg 				        busy;
   wire 			        clearbusy;
   wire [`ADDR_LEN-1:0]     effaddr;
   wire                     killspec1;
   wire                     must_read_mem;
   wire                     sb_ld_ok;
   wire                     ld_ok;
   wire                     ld_io;
   wire [7:0]               result_lb;
   wire [15:0]              result_lh;
   wire [`ADDR_LEN-1:0]     result_lw;
   wire [`ADDR_LEN-1:0]     mem_data;
   
   //LATCH
   reg 				                dstval_latch;
   reg                              ld_io_latch;
   reg [`MEM_TYPE_WIDTH-1:0]        funct3_latch;
   reg [`RRF_SEL-1:0] 		        rrftag_latch;
   reg 				                specbit_latch;
   reg [`SPECTAG_LEN-1:0] 	        spectag_latch;
   reg [`DATA_LEN-1:0] 		        lddatasb_latch;
   reg [`DATA_LEN-1:0] 		        lddatamem_latch;
   reg [`MEM_TYPE_WIDTH-1:0]        ldfunct3_latch;
   reg 				                hitsb_latch;
   reg 				                insnvalid_latch; // ldst exec is done

   // assign clearbusy = (killspec1 || dstval || (~dstval && ~fullsb)) ? 1'b1 : 1'b0;

   assign must_read_mem = (funct3 == 3'b010 && ldfunct3 != 3'b010) ||
       ((funct3 == 3'b001 || funct3 == 3'b101) && ldfunct3 == 3'b000) || ld_io;

   assign sb_ld_ok = hitsb && ~must_read_mem;
   assign ld_ok = dstval && (sb_ld_ok || cache_done[0]);
   assign clearbusy = (killspec1 || ld_ok || (~dstval && ~fullsb)) ? 1'b1 : 1'b0;
   assign killspec1 = ((spectag & spectagfix) != 0) && specbit && prmiss;
   assign kill_speculative = ((spectag_latch & spectagfix) != 0) && specbit_latch && prmiss;

   assign result_lb = (hitsb_latch && ~ld_io_latch) ? lddatasb_latch[7:0] : lddatamem_latch[7:0];

   assign result_lh = (~hitsb_latch || ld_io_latch) ? lddatamem_latch[15:0] :
       (ldfunct3_latch == 3'b000) ? {lddatamem_latch[15:8], lddatasb_latch[7:0]} :
       lddatasb_latch[15:0];

   assign result_lw = (~hitsb_latch || ld_io_latch) ? lddatamem_latch :
       (ldfunct3_latch == 3'b000) ? {lddatamem_latch[31:8], lddatasb_latch[7:0]} :
       (ldfunct3_latch == 3'b001) ? {lddatamem_latch[31:16], lddatasb_latch[15:0]} :
       lddatasb_latch;

   assign result = (funct3_latch == 3'b000) ? {{24{result_lb[7]}}, result_lb} :
       (funct3_latch == 3'b100) ? {24'h0, result_lb} :
       (funct3_latch == 3'b001) ? {{16{result_lh[15]}}, result_lh} :
       (funct3_latch == 3'b101) ? {16'h0, result_lh} : result_lw;

   assign rrf_we = dstval_latch & insnvalid_latch;
   assign rob_we = insnvalid_latch;
   assign wrrftag = rrftag_latch;
   assign busy_next = clearbusy ? 1'b0 : busy;
   assign stfin = ~killspec1 & busy & ~dstval;
   // load的时候，写dmem，可能因为storebuffer的valid置0导致找不到，从dmem取，又因为store的值还未写入dmem，导致load取到旧值
   // 非load写dmem，也是以写dmem只需1个cycle为前提，实际写下级存储，要考虑大于1cycle的情况
   assign memoccupy_ld = ~killspec1 & busy & dstval & ~sb_ld_ok;
   assign storedata = ex_src2;
   assign storeaddr = effaddr;
   assign ldaddr = effaddr;
   assign effaddr = ex_src1 + imm;
   assign ld_io = ldaddr[30]; //ldaddr >= 32'h4000_0000
   assign mem_data = ld_io ? lddatamem[31-: 32] :
       (ldaddr[3:2] == 2'b00) ? lddatamem[31-: 32] :
       (ldaddr[3:2] == 2'b01) ? lddatamem[63-: 32] :
       (ldaddr[3:2] == 2'b10) ? lddatamem[95-: 32] : lddatamem[127-:32];

   always @ (posedge clk) begin
      if (reset | killspec1 | ~busy | (~dstval & fullsb)) begin
	 dstval_latch <= 0;
     ld_io_latch <= 0;
     funct3_latch <= 0;
	 rrftag_latch <= 0;
	 specbit_latch <= 0;
	 spectag_latch <= 0;
	 lddatasb_latch <= 0;
     lddatamem_latch <= 0;
     ldfunct3_latch <= 0;
	 hitsb_latch <= 0;
	 insnvalid_latch <= 0;
      end else begin
	 dstval_latch <= dstval;
     ld_io_latch <= ld_io;
     funct3_latch <= funct3;
	 rrftag_latch <= rrftag;
	 specbit_latch <= specbit;
	 spectag_latch <= spectag;
	 lddatasb_latch <= lddatasb;
     lddatamem_latch <= mem_data;
     ldfunct3_latch <= ldfunct3;
	 hitsb_latch <= hitsb;
	 insnvalid_latch <= ~killspec1 & ((busy & ld_ok) |
					  (busy & ~dstval & ~fullsb));
	 // insnvalid_latch <= ~killspec1 & ((busy & dstval) |
	 //				  (busy & ~dstval & ~fullsb));                  
      end
   end // always @ (posedge clk)

   always @ (posedge clk) begin
      if (reset | killspec1) begin
        busy <= 0;
      end else begin
        busy <= issue | busy_next;
      end

      //if (memoccupy_ld) cache_req <= 1'b1;
      //else cache_req <= 1'b0;
   end

endmodule // exunit_ldst

//`default_nettype none
