`include "constants.vh"
`default_nettype none
module exunit_csr
  (
   input wire 			            clk,
   input wire 			            reset,
   input wire                       irq_flush,
   input wire [`DATA_LEN-1:0] 	    ex_src1,
   input wire [`DATA_LEN-1:0] 	    imm,
   input wire 			            dstval,
   input wire [`CSR_OP_WIDTH-1:0]   csr_op,
   input wire [`SPECTAG_LEN-1:0]    spectag,
   input wire 			            specbit,
   input wire 			            issue,
   input wire 			            prmiss,
   input wire 			            csrcommit,
   input wire 			            retcommit,
   input wire [`SPECTAG_LEN-1:0]    spectagfix,
   input wire [`ADDR_LEN-1:0] 	    mepc,
   output wire [`DATA_LEN-1:0] 	    result,
   output wire 			            rrf_we,
   output wire 			            rob_we, //set finish
   output wire 			            kill_speculative,

   output wire                      mie
   );

   reg 			       busy;
   reg [`DATA_LEN-1:0] mstatus;
   reg [`DATA_LEN-1:0] mtvec;
   //reg [`DATA_LEN-1:0] mepc;

   assign rob_we = busy;
   assign rrf_we = busy & dstval;
   assign kill_speculative = ((spectag & spectagfix) != 0) && specbit && prmiss;
   assign result = (csr_op == `CSR_WRITE_NOREAD) ? 0 :
       (imm[11:0] == 12'h300) ? mstatus :
       (imm[11:0] == 12'h305) ? mtvec   :
       (imm[11:0] == 12'h341) ? mepc    : 0;

   assign mie = mstatus[3];

   always @ (posedge clk) begin
      if (reset) begin
	 busy <= 0;
     mstatus <= 0;
      end else begin
	 busy <= issue;
      end

      // 应该要考虑prmiss的情况吧？
      // 还是应该在commit阶段再更新csr寄存器吧 
      if (csrcommit) begin
      case (csr_op)
        `CSR_WRITE, `CSR_WRITE_NOREAD : begin
            case (imm[11:0])
                12'h300 : mstatus   <= ex_src1;
                12'h305 : mtvec     <= ex_src1;
                //12'h341 : mepc      <= ex_src1;
            endcase
        end
        `CSR_SET : begin
            case (imm[11:0])
                12'h300 : mstatus   <= mstatus   | ex_src1;
                12'h305 : mtvec     <= mtvec     | ex_src1;
                //12'h341 : mepc      <= mepc      | ex_src1;
            endcase
        end
        `CSR_CLEAR : begin
            case (imm[11:0])
                12'h300 : mstatus   <= mstatus   & ~ex_src1;
                12'h305 : mtvec     <= mtvec     & ~ex_src1;
                //12'h341 : mepc      <= mepc      & ~ex_src1;
            endcase
        end
      endcase
      end

      // 中断确认后屏蔽所有外部irq
      // 未考虑是否同时有csr指令在执行
      if (irq_flush) begin
        //mepc <= irq_jmpaddr;
        mstatus[3] = 1'b0;
      end

      // mret返回后，clear外部irq屏蔽
      // 必须是mret确认commit后才执行
      // 否则在mret确认commit前放开，有可能取消mret的执行
      // 然后mepc又被设置，导致前一次的mepc丢失，无法返回
      if (retcommit) mstatus[3] = 1'b1;
   end
   
endmodule // exunit_csr

   
`default_nettype wire
