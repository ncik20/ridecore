`include "constants.vh"
`default_nettype none
module reorderbuf
  (
   input wire 			  clk,
   input wire 			  reset,
   input wire             irq_flush,
   //Write Signal
   input wire 			  dp1,
   input wire [`RRF_SEL-1:0] 	  dp1_addr,
   input wire [`ADDR_LEN-1:0] 	  pc_dp1,
   input wire 			  storebit_dp1,
   input wire [3:0]  	  csrbit_dp1,
   input wire 			  dstvalid_dp1,
   input wire [`REG_SEL-1:0] 	  dst_dp1,
   input wire [`GSH_BHR_LEN-1:0]  bhr_dp1,
   input wire 			  isbranch_dp1,
   input wire [11:0]      instype_dp1,
   input wire 			  dp2,
   input wire [`RRF_SEL-1:0] 	  dp2_addr,
   input wire [`ADDR_LEN-1:0] 	  pc_dp2,
   input wire 			  storebit_dp2,
   input wire [3:0]		  csrbit_dp2,
   input wire 			  dstvalid_dp2,
   input wire [`REG_SEL-1:0] 	  dst_dp2,
   input wire [`GSH_BHR_LEN-1:0]  bhr_dp2,
   input wire 			  isbranch_dp2,
   input wire [11:0]      instype_dp2,
   input wire 			  exfin_alu1,
   input wire [`RRF_SEL-1:0] 	  exfin_alu1_addr,
   input wire 			  exfin_alu2,
   input wire [`RRF_SEL-1:0] 	  exfin_alu2_addr,
   input wire 			  exfin_mul,
   input wire [`RRF_SEL-1:0] 	  exfin_mul_addr,
   input wire 			  exfin_csr,
   input wire [`RRF_SEL-1:0] 	  exfin_csr_addr,
   input wire 			  exfin_ldst,
   input wire [`RRF_SEL-1:0] 	  exfin_ldst_addr,
   input wire 			  exfin_branch,
   input wire [`RRF_SEL-1:0] 	  exfin_branch_addr,
   input wire 			  exfin_branch_brcond,
   input wire [`ADDR_LEN-1:0] 	  exfin_branch_jmpaddr, 
   input wire                    dbg_step_running,
  
   output reg [`RRF_SEL-1:0] 	  comptr_latch,
   output wire [`RRF_SEL-1:0] 	  comptr_latch2,
   output wire [1:0] 		      comnum,
   output wire 			          stcommit,
   output wire 			          csrcommit,
   output wire                    retcommit,
   output wire                    dretcommit,
   output wire 			          arfwe1,
   output wire 			          arfwe2,
   output wire [`REG_SEL-1:0] 	  dstarf1,
   output wire [`REG_SEL-1:0] 	  dstarf2,
   output wire [`ADDR_LEN-1:0] 	  pc_comcsr,
   output wire [`ADDR_LEN-1:0] 	  pc_combranch,
   output wire [`GSH_BHR_LEN-1:0] bhr_combranch,
   output reg 			          brcond_combranch,
   output wire [`ADDR_LEN-1:0] 	  jmpaddr_combranch,
   output wire [11:0] 	          instype_combranch,
   output wire 			          combranch,
   output wire [`ADDR_LEN-1:0] 	  irq_jmpaddr,
   output wire [`ADDR_LEN-1:0] 	  dbg_step_jmpaddr,
   // output reg  [`ADDR_LEN-1:0] 	  mepc,
   input wire  [`RRF_SEL-1:0] 	  dispatchptr,
   input wire  [`RRF_SEL:0]	      rrf_freenum,
   input wire 			          prmiss
   );

   reg  [`RRF_SEL-1:0] 	      comptr;
   wire [`RRF_SEL-1:0] 	      comptr2;

   wire [`RRF_SEL-1:0] 	      comptr_addr;
   wire [`RRF_SEL-1:0] 	      comptr_addr2;

   reg  [`ADDR_LEN-1:0] 	  last_commit_jmpaddr;
   reg  [`ADDR_LEN-1:0] 	  last_commit_inst_pc;

   reg  [`RRF_NUM-1:0] 		  finish;
   reg  [`RRF_NUM-1:0] 		  storebit;
   reg  [`RRF_NUM-1:0] 		  dstvalid;
   reg  [`RRF_NUM-1:0] 		  brcond;
   reg  [`RRF_NUM-1:0] 		  isbranch;

   wire [`ADDR_LEN-1:0] 	  inst_pc1;
   wire [11:0]         		  instype1;
   wire [`ADDR_LEN-1:0] 	  jmpaddr1;
   wire [`REG_SEL-1:0] 		  dst1;
   wire [`GSH_BHR_LEN-1:0] 	  bhr1;
   wire [3:0]         		  csrbit1;

   wire [`ADDR_LEN-1:0] 	  inst_pc2;
   wire [11:0]         		  instype2;
   wire [`ADDR_LEN-1:0] 	  jmpaddr2;
   wire [`REG_SEL-1:0] 		  dst2;
   wire [`GSH_BHR_LEN-1:0] 	  bhr2;
   wire [3:0]         		  csrbit2;

   reg                        arfwe1_latch;
   reg                        arfwe2_latch;
   reg                        stcommit_latch;
   reg                        combranch_latch;
   reg                        combranch1_latch;

   reg  			          commit1_latch;
   reg  			          commit2_latch;
   wire 			          commit1;
   wire 			          commit2;
   wire [`RRF_SEL-1:0]        next_comptr;
   // wire [`ADDR_LEN-1:0] 	  irq_jmpaddr;


   // wire hidp_comptr = (comptr_latch > comptr) ? 1'b1 : 1'b0;
   // wire [1:0] last_commit_count = ({hidp_comptr, comptr} - {1'b0, comptr_latch});

   assign comptr2 = comptr + 1;
   assign comptr_latch2 = comptr_latch + 1;

   assign comptr_addr = prmiss ? comptr_latch : comptr;
   assign comptr_addr2 = comptr_addr + 1;
   
   wire   hidp = (comptr > dispatchptr) || (rrf_freenum == 0) ? 1'b1 : 1'b0;
   wire   com_en1 = ({hidp, dispatchptr} - {1'b0, comptr}) > 0 ? 1'b1 : 1'b0;
   wire   com_en2 = ({hidp, dispatchptr} - {1'b0, comptr}) > 1 ? 1'b1 : 1'b0;

   assign commit1 = com_en1 & finish[comptr];

   wire   combranch1 = ~prmiss & commit1 & isbranch[comptr];
   wire   stcommit1 = ~prmiss & commit1 & storebit[comptr];

   assign commit2 = ~dbg_step_running & ~combranch1 & ~stcommit1 &
                    commit1 & com_en2 & finish[comptr2];
   assign next_comptr = comptr + commit1 + commit2;

   wire nocom = ~prmiss && ~irq_flush;

   always @ (posedge clk) begin
      if (reset) begin
         last_commit_jmpaddr <= 0;
         last_commit_inst_pc <= 0;
      end

      if (reset || irq_flush) begin
         comptr <= 0;
         comptr_latch <= 0;

         commit1_latch <= 0;
         commit2_latch <= 0;

         arfwe1_latch <= 0;
         arfwe2_latch <= 0;

         stcommit_latch <= 0;
         combranch_latch <= 0;
         brcond_combranch <= 0;
         combranch1_latch <= 0;

      // 为什么prmiss，就不执行commit？
      // 似乎没有理由，prmiss前的指令，应该可以commit
      // 之后的指令，包括产生prmiss的分支指令，在本cycle，finish都是0，也不可能commit
      // commit会更新arf的busy位，同时如果发生prmiss，则会恢复busy位，所以不能
      // 执行commit
      end else if (~prmiss) begin
         comptr <= next_comptr;
         comptr_latch <= comptr;

         commit1_latch <= commit1;
         commit2_latch <= commit2;

         arfwe1_latch <= commit1 && dstvalid[comptr];
         arfwe2_latch <= commit2 && dstvalid[comptr2];

         stcommit_latch <= stcommit1 || (commit2 && storebit[comptr2]);
         combranch_latch <= combranch1 || (commit2 && isbranch[comptr2]);
         brcond_combranch <= combranch1 ? brcond[comptr] : brcond[comptr2];
         combranch1_latch <= combranch1;

          if (comnum == 2'd1) begin
             last_commit_jmpaddr <= jmpaddr1;
             last_commit_inst_pc <= inst_pc1;
          end else if (comnum == 2'd2) begin
             last_commit_jmpaddr <= jmpaddr2;
             last_commit_inst_pc <= inst_pc2;
          end
      end
/*
      // last_commit_count=0说明没有commit，所以无需latch
      if (last_commit_count == 2'd1) begin
         last_commit_jmpaddr <= jmpaddr1;
         last_commit_inst_pc <= inst_pc1;
      end else if (last_commit_count == 2'd2) begin
         last_commit_jmpaddr <= jmpaddr2;
         last_commit_inst_pc <= inst_pc2;
      end
*/
   end

/*
   always @ (posedge clk) begin
      if (reset) begin
          commit1_latch <= 0;
          commit2_latch <= 0;

          arfwe1_latch <= 0;
          arfwe2_latch <= 0;

          stcommit_latch <= 0;
          combranch_latch <= 0;
          brcond_combranch <= 0;
          combranch1_latch <= 0;
      end
      else if (~prmiss) begin
          commit1_latch <= commit1;
          commit2_latch <= commit2;

          arfwe1_latch <= commit1 && dstvalid[comptr];
          arfwe2_latch <= commit2 && dstvalid[comptr2];

          stcommit_latch <= stcommit1 || (commit2 && storebit[comptr2]);
          combranch_latch <= combranch1 || (commit2 && isbranch[comptr2]);
          brcond_combranch <= combranch1 ? brcond[comptr] : brcond[comptr2];
          combranch1_latch <= combranch1;
      end
   end
*/
   assign comnum = {1'b0, commit1_latch} + {1'b0, commit2_latch};
   assign stcommit = stcommit_latch && nocom;
   assign csrcommit = ((commit1_latch && csrbit1[3] && !csrbit1[2]) ||
		               (commit2_latch && csrbit2[3] && !csrbit2[2])) && nocom;
   assign pc_comcsr = (commit1_latch && csrbit1[3] && !csrbit1[2]) ? inst_pc1 : inst_pc2;
   assign arfwe1 = arfwe1_latch && nocom;
   assign arfwe2 = arfwe2_latch && nocom;
   // assign dstarf1 = dst[comptr];
   // assign dstarf2 = dst[comptr2];
   assign combranch = combranch_latch && nocom;
   assign retcommit = combranch && ((csrbit1 == 4'b1110) || (csrbit2 == 4'b1110));
   assign dretcommit = combranch && ((csrbit1 == 4'b1101) || (csrbit2 == 4'b1101));
   assign pc_combranch = combranch1_latch ? inst_pc1 : inst_pc2;
   assign bhr_combranch = combranch1_latch ? bhr1 : bhr2;
   // assign brcond_combranch = combranch1 ? brcond[comptr] : brcond[comptr2];
   assign jmpaddr_combranch = combranch1_latch ? jmpaddr1 : jmpaddr2;
   assign instype_combranch = combranch1_latch ? instype1 : instype2;

   // next_comptr-1是最后一条commit的指令，如果是分支且跳转，那返回地址应
   // 该是跳转地址，否则就返回下一条commit指令的pc
   // 原设想是，在确认irq的cycle，原本在该cycle可以commit的指令，可以执行
   // commit，但这样似乎有问题，最后暂时还是在确认irq的cycle，取消所有在流水线的指令
//   assign irq_jmpaddr = (isbranch[comptr-1] && brcond[comptr-1]) ? 
//       jmpaddr[comptr-1] : (inst_pc[comptr-1]+4);

   wire [`RRF_SEL-1:0]  comptr_last = comptr_latch - 1;
   wire 			    isbranch_last = isbranch[comptr_last];
   wire 			    brcond_last = brcond[comptr_last];
   wire [`ADDR_LEN-1:0] last_commit_inst_pc_p4 = last_commit_inst_pc + 4;
   assign               irq_jmpaddr = (isbranch_last && brcond_last) ? last_commit_jmpaddr :
                                                                       last_commit_inst_pc_p4;

   wire [`ADDR_LEN-1:0] dbg_step_inst_pc = commit2_latch ? inst_pc2 : inst_pc1;
   wire [`ADDR_LEN-1:0] dbg_step_jmpaddr_raw = commit2_latch ? jmpaddr2 : jmpaddr1;
   wire                 dbg_step_isbranch = commit2_latch ? isbranch[comptr_latch2] :
                                                            isbranch[comptr_latch];
   wire                 dbg_step_brcond = commit2_latch ? brcond[comptr_latch2] :
                                                         brcond[comptr_latch];
   assign               dbg_step_jmpaddr = (dbg_step_isbranch && dbg_step_brcond) ?
                                           dbg_step_jmpaddr_raw : (dbg_step_inst_pc + 4);
 
   always @ (posedge clk) begin
      if (reset || irq_flush) begin
         finish <= 0;
         brcond <= 0;
      end else begin
         if (dp1)
           finish[dp1_addr] <= 1'b0;
         if (dp2)
           finish[dp2_addr] <= 1'b0;
         if (exfin_alu1)
           finish[exfin_alu1_addr] <= 1'b1;
         if (exfin_alu2)
           finish[exfin_alu2_addr] <= 1'b1;
         if (exfin_mul)
           finish[exfin_mul_addr] <= 1'b1;
         if (exfin_csr)
           finish[exfin_csr_addr] <= 1'b1;
         if (exfin_ldst)
           finish[exfin_ldst_addr] <= 1'b1;
         if (exfin_branch) begin
            finish[exfin_branch_addr] <= 1'b1;
            brcond[exfin_branch_addr] <= exfin_branch_brcond;
            //jmpaddr[exfin_branch_addr] <= exfin_branch_jmpaddr;
         end
      end
   end // always @ (posedge clk)

   always @ (posedge clk) begin
      if (dp1) begin
         isbranch[dp1_addr] <= isbranch_dp1;
         storebit[dp1_addr] <= storebit_dp1;
         //csrbit[dp1_addr] <= csrbit_dp1;
         dstvalid[dp1_addr] <= dstvalid_dp1;
         //dst[dp1_addr] <= dst_dp1;
         //bhr[dp1_addr] <= bhr_dp1;
         //inst_pc[dp1_addr] <= pc_dp1;
         //instype[dp1_addr] <= instype_dp1;
      end
      if (dp2) begin
         isbranch[dp2_addr] <= isbranch_dp2;
         storebit[dp2_addr] <= storebit_dp2;
         //csrbit[dp2_addr] <= csrbit_dp2;
         dstvalid[dp2_addr] <= dstvalid_dp2;
         //dst[dp2_addr] <= dst_dp2;
         //bhr[dp2_addr] <= bhr_dp2;
         //inst_pc[dp2_addr] <= pc_dp2;
         //instype[dp2_addr] <= instype_dp2;
      end
/*
      if (irq_flush) begin
        mepc <= irq_jmpaddr;
      end
*/
   end

   ram_sync_2r2w_2bank #(
    .BRAM_ADDR_WIDTH    (`RRF_SEL),
	.BRAM_DATA_WIDTH    (`ADDR_LEN),
	.DATA_DEPTH         (`RRF_NUM)
   ) jmpaddr (
    .clk                (clk),
    .raddr1             (comptr_addr),
    .raddr2             (comptr_addr2),
    .rdata1             (jmpaddr1),
    .rdata2             (jmpaddr2),
    .waddr1             (exfin_branch_addr),
    .waddr2             (0),
    .wdata1             (exfin_branch_jmpaddr),
    .wdata2             (0),
    .we1                (exfin_branch),
    .we2                (0)
   );

   ram_sync_2r2w_2bank #(
    .BRAM_ADDR_WIDTH    (`RRF_SEL),
	.BRAM_DATA_WIDTH    (`ADDR_LEN),
	.DATA_DEPTH         (`RRF_NUM)
   ) inst_pc (
    .clk                (clk),
    .raddr1             (comptr_addr),
    .raddr2             (comptr_addr2),
    .rdata1             (inst_pc1),
    .rdata2             (inst_pc2),
    .waddr1             (dp1_addr),
    .waddr2             (dp2_addr),
    .wdata1             (pc_dp1),
    .wdata2             (pc_dp2),
    .we1                (dp1),
    .we2                (dp2)
   );

   ram_sync_2r2w_2bank #(
    .BRAM_ADDR_WIDTH    (`RRF_SEL),
	.BRAM_DATA_WIDTH    (12),
	.DATA_DEPTH         (`RRF_NUM)
   ) instype (
    .clk                (clk),
    .raddr1             (comptr_addr),
    .raddr2             (comptr_addr2),
    .rdata1             (instype1),
    .rdata2             (instype2),
    .waddr1             (dp1_addr),
    .waddr2             (dp2_addr),
    .wdata1             (instype_dp1),
    .wdata2             (instype_dp2),
    .we1                (dp1),
    .we2                (dp2)
   );

   ram_sync_2r2w_2bank #(
    .BRAM_ADDR_WIDTH    (`RRF_SEL),
	.BRAM_DATA_WIDTH    (`REG_SEL),
	.DATA_DEPTH         (`RRF_NUM)
   ) dst (
    .clk                (clk),
    .raddr1             (comptr_addr),
    .raddr2             (comptr_addr2),
    .rdata1             (dstarf1),
    .rdata2             (dstarf2),
    .waddr1             (dp1_addr),
    .waddr2             (dp2_addr),
    .wdata1             (dst_dp1),
    .wdata2             (dst_dp2),
    .we1                (dp1),
    .we2                (dp2)
   );

   ram_sync_2r2w_2bank #(
    .BRAM_ADDR_WIDTH    (`RRF_SEL),
	.BRAM_DATA_WIDTH    (`GSH_BHR_LEN),
	.DATA_DEPTH         (`RRF_NUM)
   ) bhr (
    .clk                (clk),
    .raddr1             (comptr_addr),
    .raddr2             (comptr_addr2),
    .rdata1             (bhr1),
    .rdata2             (bhr2),
    .waddr1             (dp1_addr),
    .waddr2             (dp2_addr),
    .wdata1             (bhr_dp1),
    .wdata2             (bhr_dp2),
    .we1                (dp1),
    .we2                (dp2)
   );

   ram_sync_2r2w_2bank #(
    .BRAM_ADDR_WIDTH    (`RRF_SEL),
	.BRAM_DATA_WIDTH    (4),
	.DATA_DEPTH         (`RRF_NUM)
   ) csrbit (
    .clk                (clk),
    .raddr1             (comptr_addr),
    .raddr2             (comptr_addr2),
    .rdata1             (csrbit1),
    .rdata2             (csrbit2),
    .waddr1             (dp1_addr),
    .waddr2             (dp2_addr),
    .wdata1             (csrbit_dp1),
    .wdata2             (csrbit_dp2),
    .we1                (dp1),
    .we2                (dp2)
   );

endmodule // reorderbuf
`default_nettype wire
