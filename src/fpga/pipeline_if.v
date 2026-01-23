`include "constants.vh"
`default_nettype none
module pipeline_if
  (
   input wire 			  clk,
   input wire 			  reset,
   input wire [`ADDR_LEN-1:0] 	    pc,
   output wire                      predict_cond,
   output wire [`ADDR_LEN-1:0]      npc,
   input wire 			            btbpht_we,
   input wire [`ADDR_LEN-1:0] 	    btbpht_pc,
   input wire [`ADDR_LEN-1:0] 	    btb_jmpdst,
   input wire [11:0]                btb_instype,
   input wire 			            pht_wcond,
   input wire [`SPECTAG_LEN-1:0]    mpft_valid,
   input wire [`GSH_BHR_LEN-1:0]    pht_bhr,
   input wire 			            prmiss,
   input wire 			            prsuccess,
   input wire [`SPECTAG_LEN-1:0]    prtag,
   output wire [`GSH_BHR_LEN-1:0]   bhr,
   input wire [`SPECTAG_LEN-1:0]    spectagnow
   );

   wire 			        hit;
   wire 			        is_jmp;
   wire 			        have_br_jmp;
   wire                     pr_cond;
   wire [`ADDR_LEN-1:0] 	pred_pc;

   wire hit_bht = hit && have_br_jmp;

   assign predict_cond = ~hit ? pr_cond :
                                is_jmp ? 1'b1 : (pr_cond & have_br_jmp);
   assign npc = (hit && predict_cond) ? pred_pc :
        (pc[3:2] == 2'b00) ? (pc + 16) :
        (pc[3:2] == 2'b01) ? (pc + 12) :
        (pc[3:2] == 2'b10) ? (pc + 8) : (pc + 4);

/*   
   imem instmem(
		.clk(~clk),
		.addr(pc[12:4]),
		.data(idata)
		);
*/
   /*
   imem_outa instmem(
		     .pc(pc[31:4]),
		     .idata(idata)
		     );

   select_logic sellog(
		       .sel(cpu_res_pc[3:2]),
		       .idata(idata),
		       .inst1(inst1),
		       .inst2(inst2),
		       .invalid(invalid2)
		       );
   */
   btb brtbl(
	     .clk(clk),
	     .reset(reset),
	     .pc(pc),
	     .hit(hit),
	     .is_jmp(is_jmp),
	     .have_br_jmp(have_br_jmp),
	     .jmpaddr(pred_pc),
	     .we(btbpht_we),
	     .jmpsrc(btbpht_pc),
	     .jmpdst(btb_jmpdst),
	     //.invalid2(invalid2)
         //.invalid2(pc_invalid2)
         .instype(btb_instype)
         );

   gshare_predictor gsh
     (
      .clk(clk),
      .reset(reset),
      .pc(pc),
	  .is_jmp(is_jmp),
      .hit_bht(hit_bht),
      .predict_cond(pr_cond),
      .we(btbpht_we),
      .wcond(pht_wcond),
      // .went(btbpht_pc[2+:`GSH_BHR_LEN] ^ pht_bhr),
      .went(btbpht_pc[4+:`GSH_BHR_LEN] ^ pht_bhr),
      .mpft_valid(mpft_valid),
      .prmiss(prmiss),
      .prsuccess(prsuccess),
      .prtag(prtag),
      .bhr_master(bhr),
      .spectagnow(spectagnow)
      );
   
endmodule // pipeline_pc


module select_logic
  (
   input wire [1:0] 		sel,
   input wire [4*`INSN_LEN-1:0] idata,
   output reg [`INSN_LEN-1:0] 	inst1,
   output reg [`INSN_LEN-1:0] 	inst2,
   output wire 			invalid
   );

   //assign invalid = (sel[0] == 1'b1);
   assign invalid = (sel == 2'b11);

   
   always @ (*) begin
      inst1 = `INSN_LEN'h0;
      inst2 = `INSN_LEN'h0;
      
      case(sel)
	2'b00 : begin
	   inst1 = idata[31:0];
	   inst2 = idata[63:32];
	end
	2'b01 : begin
	   inst1 = idata[63:32];
	   inst2 = idata[95:64];
	end
	2'b10 : begin
	   inst1 = idata[95:64];
	   inst2 = idata[127:96];
	end
	2'b11 : begin
	   inst1 = idata[127:96];
	   inst2 = idata[31:0];
	end
      endcase // case (sel)
   end
   
endmodule // select_logic

`default_nettype wire
