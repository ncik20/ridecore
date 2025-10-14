`include "constants.vh"
`default_nettype none
module rs_csr_ent
  (
   //Memory
   input wire 			 clk,
   input wire 			 reset,
   input wire 			 busy,
   input wire [`DATA_LEN-1:0] 	 wsrc1,
   input wire 			 wvalid1,
   input wire [`DATA_LEN-1:0] 	 wimm,
   input wire [`CSR_OP_WIDTH-1:0]    wcsr_op,
   input wire [`RRF_SEL-1:0] 	 wrrftag,
   input wire 			 wdstval,
   input wire [`SPECTAG_LEN-1:0] 	 wspectag,
   input wire 			 we,
   output wire [`DATA_LEN-1:0] 	 ex_src1,
   output wire 			 ready,
   output reg [`DATA_LEN-1:0] 	 imm,
   output reg [`CSR_OP_WIDTH-1:0]    csr_op,
   output reg [`RRF_SEL-1:0] 	 rrftag,
   output reg 			 dstval,
   output reg [`SPECTAG_LEN-1:0] spectag,
   //EXRSLT
   input wire [`DATA_LEN-1:0] 	 exrslt1,
   input wire [`RRF_SEL-1:0] 	 exdst1,
   input wire 			 kill_spec1,
   input wire [`DATA_LEN-1:0] 	 exrslt2,
   input wire [`RRF_SEL-1:0] 	 exdst2,
   input wire 			 kill_spec2,
   input wire [`DATA_LEN-1:0] 	 exrslt3,
   input wire [`RRF_SEL-1:0] 	 exdst3,
   input wire 			 kill_spec3,
   input wire [`DATA_LEN-1:0] 	 exrslt4,
   input wire [`RRF_SEL-1:0] 	 exdst4,
   input wire 			 kill_spec4,
   input wire [`DATA_LEN-1:0] 	 exrslt5,
   input wire [`RRF_SEL-1:0] 	 exdst5,
   input wire 			 kill_spec5,
   input wire [`DATA_LEN-1:0] 	 exrslt6,
   input wire [`RRF_SEL-1:0] 	 exdst6,
   input wire 			 kill_spec6
   );

   reg [`DATA_LEN-1:0] 		 src1;
   reg 				 valid1;

   wire [`DATA_LEN-1:0] 	 nextsrc1;
   wire 			 nextvalid1;
   
   assign ready = busy & valid1;
   assign ex_src1 = ~valid1 & nextvalid1 ?
		    nextsrc1 : src1;
   
   always @ (posedge clk) begin
      if (reset) begin
	 imm <= 0;
	 rrftag <= 0;
	 dstval <= 0;
	 spectag <= 0;
	 csr_op <= 0;

	 src1 <= 0;
	 valid1 <= 0;
      end else if (we) begin
	 imm <= wimm;
	 rrftag <= wrrftag;
	 dstval <= wdstval;
	 spectag <= wspectag;
	 csr_op <= wcsr_op;

	 src1 <= wsrc1;
	 valid1 <= wvalid1;
      end else begin // if (we)
	 src1 <= nextsrc1;
	 valid1 <= nextvalid1;
      end
   end
   
   src_manager srcmng1(
		       .opr(src1),
		       .opr_rdy(valid1),
		       .exrslt1(exrslt1),
		       .exdst1(exdst1),
		       .kill_spec1(kill_spec1),
		       .exrslt2(exrslt2),
		       .exdst2(exdst2),
		       .kill_spec2(kill_spec2),
		       .exrslt3(exrslt3),
		       .exdst3(exdst3),
		       .kill_spec3(kill_spec3),
		       .exrslt4(exrslt4),
		       .exdst4(exdst4),
		       .kill_spec4(kill_spec4),
		       .exrslt5(exrslt5),
		       .exdst5(exdst5),
		       .kill_spec5(kill_spec5),
		       .exrslt6(exrslt6),
		       .exdst6(exdst6),
		       .kill_spec6(kill_spec6),
		       .src(nextsrc1),
		       .resolved(nextvalid1)
		       );

endmodule // rs_csr


module rs_csr
  (
   //System
   input wire 			  clk,
   input wire 			  reset,
   input wire 			  irq_flush,
   output reg [`CSR_ENT_NUM-1:0]  busyvec,
   input wire 			  prmiss,
   input wire 			  prsuccess,
   input wire [`SPECTAG_LEN-1:0] 	  prtag,
   input wire [`SPECTAG_LEN-1:0] 	  specfixtag,
   output wire [`CSR_ENT_NUM-1:0] prbusyvec_next,
   //WriteSignal
   input wire 			  clearbusy, //Issue 
   input wire [`CSR_ENT_SEL-1:0] 	  issueaddr, //= raddr, clsbsyadr
   input wire 			  we1, //alloc1
   input wire 			  we2, //alloc2
   input wire [`CSR_ENT_SEL-1:0] 	  waddr1, //allocent1
   input wire [`CSR_ENT_SEL-1:0] 	  waddr2, //allocent2
   //WriteSignal1
   input wire [`DATA_LEN-1:0] 	  wsrc1_1,
   input wire 			  wvalid1_1,
   input wire [`DATA_LEN-1:0] 	   wimm_1,
   input wire [`CSR_OP_WIDTH-1:0]  wcsr_op_1,
   input wire [`RRF_SEL-1:0] 	  wrrftag_1,
   input wire 			  wdstval_1,
   input wire [`SPECTAG_LEN-1:0] 	  wspectag_1,
   input wire 			  wspecbit_1,

   //WriteSignal2
   input wire [`DATA_LEN-1:0] 	  wsrc1_2,
   input wire 			  wvalid1_2,
   input wire [`DATA_LEN-1:0] 	   wimm_2,
   input wire [`CSR_OP_WIDTH-1:0]  wcsr_op_2,
   input wire [`RRF_SEL-1:0] 	  wrrftag_2,
   input wire 			  wdstval_2,
   input wire [`SPECTAG_LEN-1:0] 	  wspectag_2,
   input wire 			  wspecbit_2,

   //ReadSignal
   output wire [`DATA_LEN-1:0] 	  ex_src1,
   output wire [`CSR_ENT_NUM-1:0] ready,
   output wire [`DATA_LEN-1:0] 	  imm,
   output wire [`CSR_OP_WIDTH-1:0] 	  csr_op,
   output wire [`RRF_SEL-1:0] 	  rrftag,
   output wire 			  dstval,
   output wire [`SPECTAG_LEN-1:0] spectag,
   output wire 			  specbit,

   //EXRSLT
   input wire                     csrcommit,
   input wire [`DATA_LEN-1:0] 	  exrslt1,
   input wire [`RRF_SEL-1:0] 	  exdst1,
   input wire 			  kill_spec1,
   input wire [`DATA_LEN-1:0] 	  exrslt2,
   input wire [`RRF_SEL-1:0] 	  exdst2,
   input wire 			  kill_spec2,
   input wire [`DATA_LEN-1:0] 	  exrslt3,
   input wire [`RRF_SEL-1:0] 	  exdst3,
   input wire 			  kill_spec3,
   input wire [`DATA_LEN-1:0] 	  exrslt4,
   input wire [`RRF_SEL-1:0] 	  exdst4,
   input wire 			  kill_spec4,
   input wire [`DATA_LEN-1:0] 	  exrslt5,
   input wire [`RRF_SEL-1:0] 	  exdst5,
   input wire 			  kill_spec5,
   input wire [`DATA_LEN-1:0] 	  exrslt6,
   input wire [`RRF_SEL-1:0] 	  exdst6,
   input wire 			  kill_spec6
   );

   //_0
   wire [`DATA_LEN-1:0] 	      ex_src1_0;
   wire 			      ready_0;
   wire [`DATA_LEN-1:0] 	      imm_0;
   wire [`CSR_OP_WIDTH-1:0] 	  csr_op_0;
   wire [`RRF_SEL-1:0] 		      rrftag_0;
   wire 			      dstval_0;
   wire [`SPECTAG_LEN-1:0] 	      spectag_0;
   
   //_1
   wire [`DATA_LEN-1:0] 	      ex_src1_1;
   wire 			      ready_1;
   wire [`DATA_LEN-1:0] 	      imm_1;
   wire [`CSR_OP_WIDTH-1:0] 	  csr_op_1;
   wire [`RRF_SEL-1:0] 		      rrftag_1;
   wire 			      dstval_1;
   wire [`SPECTAG_LEN-1:0] 	      spectag_1;

   reg [`CSR_ENT_NUM-1:0] 	  specbitvec;

   reg [`SPECTAG_LEN-1:0]   csr_spectag;
   reg                      csr_specbit;
   reg                      csr_excute;
   reg                      ready_0_;
   reg                      ready_1_;

   wire [`CSR_ENT_NUM-1:0] 	  inv_vector =
				  {(spectag_1 & specfixtag) == 0 ? 1'b1 : 1'b0,
				   (spectag_0 & specfixtag) == 0 ? 1'b1 : 1'b0};

   wire [`CSR_ENT_NUM-1:0] 	  inv_vector_spec =
				  {(spectag_1 == prtag) ? 1'b0 : 1'b1,
				   (spectag_0 == prtag) ? 1'b0 : 1'b1};

   wire [`CSR_ENT_NUM-1:0] 	  specbitvec_next =
				  (inv_vector_spec & specbitvec);
   /* |
				  (we1 & wspecbit_1 ? (`MUL_ENT_SEL'b1 << waddr1) : 0) |
				  (we2 & wspecbit_2 ? (`MUL_ENT_SEL'b1 << waddr2) : 0);
    */
   assign specbit = prsuccess ? 
		    specbitvec_next[issueaddr] : specbitvec[issueaddr];

   assign ready = {ready_1 & ready_1_, ready_0 & ready_0_};
   assign prbusyvec_next = inv_vector & busyvec;

   always @ (posedge clk) begin
      if (reset || irq_flush) begin
          csr_excute <= 0;
          ready_0_ <= 0;
          ready_1_ <= 0;
          //csr_spectag <= 0;
      end else if (csr_excute && ((csr_spectag & specfixtag) != 0) && csr_specbit && prmiss) begin
          csr_excute <= 0;
      end else if (~prmiss && ~csr_excute && (we1 || we2 || |busyvec)) begin
          csr_excute <= 1'b1;

          if (|busyvec) begin
              csr_spectag <= rrftag;
              csr_specbit <= spectag;

              if (issueaddr == 0) ready_0_ <= 1'b1;
              else ready_1_ <= 1'b1;
          end else if (we1) begin
              csr_spectag <= wspectag_1;
              csr_specbit <= wspecbit_1;

              if (waddr1 == 0) ready_0_ <= 1'b1;
              else ready_1_ <= 1'b1;
          end else begin
              csr_spectag <= wspectag_2;
              csr_specbit <= wspecbit_2;

              if (waddr2 == 0) ready_0_ <= 1'b1;
              else ready_1_ <= 1'b1;
          end
      end

	  if (clearbusy) begin
          ready_0_ <= 0;
          ready_1_ <= 0;
	  end

	  if (csrcommit) begin
          csr_excute <= 0;
	  end
   end // always @ (posedge clk)

/*
   // if csr (rs_ent_1_id == `RS_ENT_CSR)
   // 如果目标csr没有在写入中，就取得csr内容，否则就是csr的index
   assign csr_rdy2_1 = ~csr_busy[wimm_1[11:0]];

   assign csr_opr2_1 = csr_rdy2_1 ? csrdata[wimm_1[11:0]] : wimm_1;

   assign issue_csr_ready = (issueaddr == 0) ? valid2_0 : valid2_1;

   always @ (posedge clk) begin
      if (reset) begin
	 issue_csr_ready <= 0;
      end else if (busyvec[issueaddr]) begin
	 //src1 <= wsrc1;
	 issue_csr_ready <= next_issue_csr_ready;
      end
   end

   assign next_issue_csr_ready = issue_csr_ready | (imm == commit_csr);

   assign ready = (issueaddr == 0) ? {ready_1, ready_0 & next_issue_csr_ready} : {ready_1 & next_issue_csr_ready, ready_0};


   if (busyvec[issueaddr] && imm == commit_csr && ~issue_csr_ready) begin
       next_issue_csr_ready = 1'b1;
   end else if (busyvec[~issueaddr] && ((issueaddr == 0) ? imm_1 : imm_0) == commit_csr) begin
   end else if (csr_opr2_1 == commit_csr) begin
   end else begin
   end

   assign commit_csr_eq_1 = (commit_csr1 == csr_opr2_1) | (commit_csr2 == csr_opr2_1);

   assign csr_src2_1 = csr_rdy2_1 ? csr_opr2_1 :
		commit_csr_eq_1 ? csrdata[csr_opr2_1[11:0]] : csr_opr2_1;

   assign csr_resolved2_1 = csr_rdy2_1 | commit_csr_eq_1;

   // if csr (rs_ent_2_id == `RS_ENT_CSR)
   // 如果目标csr为同时decode指令的目标csr，就是目标csr的index
   // 如果目标csr没有在写入中，就取得csr内容，否则就是csr的index
   assign csr_rdy2_2 = (wimm_1 != wimm_2) & ~csr_busy[wimm_2[11:0]];

   assign csr_opr2_2 = csr_rdy2_2 ? csrdata[imm2[11:0]] : wimm_2;

   // 如果同时decode的两条指令的目标csr一样，第二条csr，似乎不能用以下条件判断是
   // 否可用，因为可用只能是对于第一条来说可用，第二条必须等第一条commit的结果
   // 如何做到？
   // 引申一下，下个cycle如果再来一个同样目标的csr指令，似乎也不应该激活
   // 应该始终看，在流水线中所有的csr指令，与自己目标相同的最近的一条，其commit后，才能激活
   assign commit_csr_eq_2 = (commit_csr1 == csr_opr2_2) | (commit_csr2 == csr_opr2_2);

   assign csr_src2_2 = csr_rdy2_2 ? csr_opr2_2 :
		commit_csr_eq_2 ? csrdata[csr_opr2_2[11:0]] : csr_opr2_2;

   assign csr_resolved2_2 = csr_rdy2_2 | commit_csr_eq_2;
*/



   always @ (posedge clk) begin
      if (reset || irq_flush) begin
	 busyvec <= 0;
	 specbitvec <= 0;
      end else begin
	 if (prmiss) begin
	    busyvec <= prbusyvec_next;
	    specbitvec <= 0;
	 end else if (prsuccess) begin
	    specbitvec <= specbitvec_next;
	    /*
	    if (we1) begin
	       busyvec[waddr1] <= 1'b1;
	    end
	    if (we2) begin
	       busyvec[waddr2] <= 1'b1;
	    end
	     */
	    if (clearbusy) begin
	       busyvec[issueaddr] <= 1'b0;
	    end
     end else begin
	    if (we1) begin
	       busyvec[waddr1] <= 1'b1;
	       specbitvec[waddr1] <= wspecbit_1;
	    end
	    if (we2) begin
	       busyvec[waddr2] <= 1'b1;
	       specbitvec[waddr2] <= wspecbit_2;
	    end
	    if (clearbusy) begin
	       busyvec[issueaddr] <= 1'b0;
	    end
	 end
      end
   end

   rs_csr_ent ent0(
		   .clk(clk),
		   .reset(reset),		      		   
		   .busy(busyvec[0]),
		   .wsrc1((we1 && (waddr1 == 0)) ? wsrc1_1 : wsrc1_2),
		   .wvalid1((we1 && (waddr1 == 0)) ? wvalid1_1 : wvalid1_2),
		   .wimm((we1 && (waddr1 == 0)) ? wimm_1 : wimm_2),
		   .wcsr_op((we1 && (waddr1 == 0)) ? wcsr_op_1 : wcsr_op_2),
		   .wrrftag((we1 && (waddr1 == 0)) ? wrrftag_1 : wrrftag_2),
		   .wdstval((we1 && (waddr1 == 0)) ? wdstval_1 : wdstval_2),
		   .wspectag((we1 && (waddr1 == 0)) ? wspectag_1 : wspectag_2),
		   .we((we1 && (waddr1 == 0)) || (we2 && (waddr2 == 0))),
		   .ex_src1(ex_src1_0),
		   .ready(ready_0),
		   .imm(imm_0),
		   .csr_op(csr_op_0),
		   .rrftag(rrftag_0),
		   .dstval(dstval_0),
		   .spectag(spectag_0),
		   .exrslt1(exrslt1),
		   .exdst1(exdst1),
		   .kill_spec1(kill_spec1),
		   .exrslt2(exrslt2),
		   .exdst2(exdst2),
		   .kill_spec2(kill_spec2),
		   .exrslt3(exrslt3),
		   .exdst3(exdst3),
		   .kill_spec3(kill_spec3),
		   .exrslt4(exrslt4),
		   .exdst4(exdst4),
		   .kill_spec4(kill_spec4),
		   .exrslt5(exrslt5),
		   .exdst5(exdst5),
		   .kill_spec5(kill_spec5),
		   .exrslt6(exrslt6),
		   .exdst6(exdst6),
		   .kill_spec6(kill_spec6)
		   );

   rs_csr_ent ent1(
		   .clk(clk),
		   .reset(reset),		   
		   .busy(busyvec[1]),
		   .wsrc1((we1 && (waddr1 == 1)) ? wsrc1_1 : wsrc1_2),
		   .wvalid1((we1 && (waddr1 == 1)) ? wvalid1_1 : wvalid1_2),
		   .wimm((we1 && (waddr1 == 1)) ? wimm_1 : wimm_2),
		   .wcsr_op((we1 && (waddr1 == 1)) ? wcsr_op_1 : wcsr_op_2),
		   .wrrftag((we1 && (waddr1 == 1)) ? wrrftag_1 : wrrftag_2),
		   .wdstval((we1 && (waddr1 == 1)) ? wdstval_1 : wdstval_2),
		   .wspectag((we1 && (waddr1 == 1)) ? wspectag_1 : wspectag_2),
		   .we((we1 && (waddr1 == 1)) || (we2 && (waddr2 == 1))),
		   .ex_src1(ex_src1_1),
		   .ready(ready_1),
		   .imm(imm_1),
		   .csr_op(csr_op_1),
		   .rrftag(rrftag_1),
		   .dstval(dstval_1),
		   .spectag(spectag_1),
		   .exrslt1(exrslt1),
		   .exdst1(exdst1),
		   .kill_spec1(kill_spec1),
		   .exrslt2(exrslt2),
		   .exdst2(exdst2),
		   .kill_spec2(kill_spec2),
		   .exrslt3(exrslt3),
		   .exdst3(exdst3),
		   .kill_spec3(kill_spec3),
		   .exrslt4(exrslt4),
		   .exdst4(exdst4),
		   .kill_spec4(kill_spec4),
		   .exrslt5(exrslt5),
		   .exdst5(exdst5),
		   .kill_spec5(kill_spec5),
		   .exrslt6(exrslt6),
		   .exdst6(exdst6),
		   .kill_spec6(kill_spec6)
		   );
   
   assign ex_src1 = (issueaddr == 0) ? ex_src1_0 : ex_src1_1;
   
   assign imm = (issueaddr == 0) ? imm_0 : imm_1;

   assign csr_op = (issueaddr == 0) ? csr_op_0 : csr_op_1;

   assign rrftag = (issueaddr == 0) ? rrftag_0 : rrftag_1;
   
   assign dstval = (issueaddr == 0) ? dstval_0 : dstval_1;

   assign spectag = (issueaddr == 0) ? spectag_0 : spectag_1;

endmodule // rs_csr
`default_nettype wire
