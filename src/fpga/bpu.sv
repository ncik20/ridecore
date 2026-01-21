`include "constants.vh"
`default_nettype none
module branch_predictor
(
    input wire 			            clk,
    input wire 			            reset,
    input wire  [`ADDR_LEN-1:0] 	pc,
    output wire                     predict_cond,
    output wire [`ADDR_LEN-1:0]     npc,

    input wire 			            btbpht_we,
    input wire  [`ADDR_LEN-1:0] 	btbpht_pc,
    input wire  [`ADDR_LEN-1:0]     btb_jmpdst,
    input wire  [11:0]              pc_fetch_info,
    input wire  [2:0]               combranch_type,
    input wire 			            pht_wcond,
    // input wire  [`SPECTAG_LEN-1:0]  mpft_valid,
    input wire  [`GSH_BHR_LEN-1:0]  pht_bhr,
    input wire 			            prmiss,
    // input wire 			            prsuccess,
    input wire  [`SPECTAG_LEN-1:0]  prtag,
    output wire [`GSH_BHR_LEN-1:0]  bhr,
    input wire  [`SPECTAG_LEN-1:0]  spectagnow,
    output wire [29:0]              ras_backup,
    output wire [3:0]               rasPtr_backup,
    input wire  [29:0]              prmiss_ras,
    input wire  [3:0]               prmiss_rasPtr,
    input wire  [`GSH_BHR_LEN-1:0]  prmiss_bhr,
    output wire                     hit_bht,
    output wire                     pr_cond
   );

   wire 			        hit;
   wire 			        is_jmp;
   wire 			        have_br_jmp;
   // wire                     pr_cond;
   wire [`ADDR_LEN-1:0] 	pred_pc;

   assign predict_cond = ~hit ? pr_cond :
                                is_jmp ? 1'b1 : (pr_cond & have_br_jmp);
   assign npc = (hit && predict_cond) ? pred_pc :
        (pc[3:2] == 2'b00) ? (pc + 16) :
        (pc[3:2] == 2'b01) ? (pc + 12) :
        (pc[3:2] == 2'b10) ? (pc + 8) : (pc + 4);

   // assign hit_bht = hit && ~is_jmp && have_br_jmp;
   assign hit_bht = hit && have_br_jmp;

   btb brtbl(
	     .clk(clk),
	     .reset(reset),
	     .pc(pc),
	     .hit(hit),
	     .is_jmp(is_jmp),
	     .have_br_jmp(have_br_jmp),
	     .jmpaddr(pred_pc),
	     // .we(btbpht_we),
         // 只有在跳转的情况下才写BTB
         .we(pht_wcond && btbpht_we),
	     .jmpsrc(btbpht_pc),
	     .jmpdst(btb_jmpdst),
         .pc_fetch_info(pc_fetch_info),
	     // .invalid2(invalid2)
         // .invalid2(pc_invalid2)
         .ras_backup(ras_backup),
         .rasPtr_backup(rasPtr_backup),
         .prmiss(prmiss),
         .prmiss_ras(prmiss_ras),
         .prmiss_rasPtr(prmiss_rasPtr)
	     );

   gshare_predictor gsh
     (
      .clk(clk),
      .reset(reset),
      .pc(pc),
      // ~is_jmp：排除有效的跳转指令是jal或jalr的情况
      // have_br_jmp：排除有效指令无branch或者无条件跳转指令的情况
	  .is_jmp(is_jmp),
      .hit_bht(hit_bht),
      .predict_cond(pr_cond),
      // .we(btbpht_we),
      // commit的是branch指令，才需要更新pht
      // .we(btbpht_we && (combranch_type == 3'd1)),
      .we(btbpht_we),
      .wcond(pht_wcond),
      // .went(btbpht_pc[2+:`GSH_BHR_LEN] ^ pht_bhr),
      .went(btbpht_pc[4+:`GSH_BHR_LEN] ^ pht_bhr),
      // .mpft_valid(mpft_valid),
      .prmiss(prmiss),
      // .prsuccess(prsuccess),
      .prtag(prtag),
      .prmiss_bhr(prmiss_bhr),
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
