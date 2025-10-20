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
   input wire [`INSN_LEN-1:0] 	  pc_dp1,
   input wire 			  storebit_dp1,
   input wire 			  csrbit_dp1,
   input wire 			  dstvalid_dp1,
   input wire [`REG_SEL-1:0] 	  dst_dp1,
   input wire [`GSH_BHR_LEN-1:0]  bhr_dp1,
   input wire 			  isbranch_dp1,
   input wire 			  dp2,
   input wire [`RRF_SEL-1:0] 	  dp2_addr,
   input wire [`INSN_LEN-1:0] 	  pc_dp2,
   input wire 			  storebit_dp2,
   input wire 			  csrbit_dp2,
   input wire 			  dstvalid_dp2,
   input wire [`REG_SEL-1:0] 	  dst_dp2,
   input wire [`GSH_BHR_LEN-1:0]  bhr_dp2,
   input wire 			  isbranch_dp2,
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
  
   output reg [`RRF_SEL-1:0] 	  comptr,
   output wire [`RRF_SEL-1:0] 	  comptr2,
   output wire [1:0] 		  comnum,
   output wire 			  stcommit,
   output wire 			  csrcommit,
   output wire 			  arfwe1,
   output wire 			  arfwe2,
   output wire [`REG_SEL-1:0] 	  dstarf1,
   output wire [`REG_SEL-1:0] 	  dstarf2,
   output wire [`ADDR_LEN-1:0] 	  pc_combranch,
   output wire [`GSH_BHR_LEN-1:0] bhr_combranch,
   output wire 			  brcond_combranch,
   output wire [`ADDR_LEN-1:0] 	  jmpaddr_combranch,
   output wire 			  combranch,
   output wire [`ADDR_LEN-1:0] 	  irq_jmpaddr,
   input wire [`RRF_SEL-1:0] 	  dispatchptr,
   input wire [`RRF_SEL:0] 	  rrf_freenum,
   input wire 			  prmiss
   );

   reg [`RRF_NUM-1:0] 		  finish;
   reg [`RRF_NUM-1:0] 		  storebit;
   reg [`RRF_NUM-1:0] 		  csrbit;
   reg [`RRF_NUM-1:0] 		  dstvalid;
   reg [`RRF_NUM-1:0] 		  brcond;
   reg [`RRF_NUM-1:0] 		  isbranch;
   
   reg [`ADDR_LEN-1:0] 		  inst_pc [0:`RRF_NUM-1];
   reg [`ADDR_LEN-1:0] 		  jmpaddr [0:`RRF_NUM-1];   
   reg [`REG_SEL-1:0] 		  dst [0:`RRF_NUM-1];
   reg [`GSH_BHR_LEN-1:0] 	  bhr [0:`RRF_NUM-1];

   wire 			          commit2;
   wire [`RRF_SEL-1:0]        next_comptr;

   assign comptr2 = comptr+1;
   
   wire 			  hidp = (comptr > dispatchptr) || (rrf_freenum == 0) ? 1'b1 : 1'b0;
   wire 			  com_en1 = ({hidp, dispatchptr} - {1'b0, comptr}) > 0 ? 1'b1 : 1'b0;
   wire 			  com_en2 = ({hidp, dispatchptr} - {1'b0, comptr}) > 1 ? 1'b1 : 1'b0;
   wire 			  commit1 = com_en1 & finish[comptr];
   //   wire commit2 = commit1 & com_en2 & finish[comptr2];

   wire               combranch1 = ~prmiss & commit1 & isbranch[comptr];
   wire               stcommit1 = ~prmiss & commit1 & storebit[comptr];

   assign commit2 = ~combranch1 & ~stcommit1 & commit1 & com_en2 & finish[comptr2];
   assign next_comptr = comptr + commit1 + commit2;
   assign comnum = {1'b0, commit1} + {1'b0, commit2};
   assign stcommit = (stcommit1 | (~prmiss & commit2 & storebit[comptr2])) & ~irq_flush;
   assign csrcommit = ((~prmiss & commit1 & csrbit[comptr]) |
		     (~prmiss & commit2 & csrbit[comptr2])) & ~irq_flush;
   assign arfwe1 = ~prmiss & commit1 & dstvalid[comptr] & ~irq_flush;
   assign arfwe2 = ~prmiss & commit2 & dstvalid[comptr2] & ~irq_flush;
   assign dstarf1 = dst[comptr];
   assign dstarf2 = dst[comptr2];
   assign combranch = combranch1 | (~prmiss & commit2 & isbranch[comptr2]);
   assign pc_combranch = combranch1 ? inst_pc[comptr] : inst_pc[comptr2];
   assign bhr_combranch = combranch1 ? bhr[comptr] : bhr[comptr2];
   assign brcond_combranch = combranch1 ? brcond[comptr] : brcond[comptr2];
   assign jmpaddr_combranch = combranch1 ? jmpaddr[comptr] : jmpaddr[comptr2];

   // next_comptr-1是最后一条commit的指令，如果是分支且跳转，那返回地址应
   // 该是跳转地址，否则就返回下一条commit指令的pc
   // 原设想是，在确认irq的cycle，原本在该cycle可以commit的指令，可以执行
   // commit，但这样似乎有问题，最后暂时还是在确认irq的cycle，取消所有在流水线的指令
   assign irq_jmpaddr = (isbranch[comptr-1] && brcond[comptr-1]) ? 
       jmpaddr[comptr-1] : (inst_pc[comptr-1]+4);

   always @ (posedge clk) begin
      if (reset || irq_flush) begin
	 comptr <= 0;

     // 为什么prmiss，就不执行commit？
     // 似乎没有理由，prmiss前的指令，应该可以commit
     // 之后的指令，包括产生prmiss的分支指令，在本cycle，finish都是0，也不可能commit
     // commit会更新arf的busy位，同时如果发生prmiss，则会恢复busy位，所以不能
     // 执行commit 
      end else if (~prmiss) begin
	 comptr <= next_comptr;
      end
   end
 
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
	    jmpaddr[exfin_branch_addr] <= exfin_branch_jmpaddr;
	 end
      end
   end // always @ (posedge clk)

   always @ (posedge clk) begin
      if (dp1) begin
	 isbranch[dp1_addr] <= isbranch_dp1;
	 storebit[dp1_addr] <= storebit_dp1;
	 csrbit[dp1_addr] <= csrbit_dp1;
	 dstvalid[dp1_addr] <= dstvalid_dp1;
	 dst[dp1_addr] <= dst_dp1;
	 bhr[dp1_addr] <= bhr_dp1;
	 inst_pc[dp1_addr] <= pc_dp1;
      end
      if (dp2) begin
	 isbranch[dp2_addr] <= isbranch_dp2;
	 storebit[dp2_addr] <= storebit_dp2;
	 csrbit[dp2_addr] <= csrbit_dp2;
	 dstvalid[dp2_addr] <= dstvalid_dp2;
	 dst[dp2_addr] <= dst_dp2;
	 bhr[dp2_addr] <= bhr_dp2;
	 inst_pc[dp2_addr] <= pc_dp2;
      end
   end
endmodule // reorderbuf
`default_nettype wire
