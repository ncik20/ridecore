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
   input wire [`ADDR_LEN-1:0] 	    irq_jmpaddr,
   output wire [`DATA_LEN-1:0] 	    result,
   output wire 			            rrf_we,
   output wire 			            rob_we, //set finish
   output wire 			            kill_speculative,
   input  wire                      ecall,
   input  wire                      ebreak,
   input  wire [`ADDR_LEN-1:0] 	    jmpaddr,

   input  wire                      eirq,
   input  wire                      tirq,
   input  wire                      sirq,
   output reg [`DATA_LEN-1:0]       mie,
   output reg [`DATA_LEN-1:0]       mtvec,
   output reg [`DATA_LEN-1:0]       mepc,
   output wire                      mstatus_mie
   );

   reg 			        busy;
   reg  [`DATA_LEN-1:0] mhartid;     //0xf14
   reg  [`DATA_LEN-1:0] mstatus;     //0x300
// reg  [`DATA_LEN-1:0] mie;         //0x304
// reg  [`DATA_LEN-1:0] mtvec;       //0x305
// reg  [`DATA_LEN-1:0] mepc;        //0x341
   reg  [`DATA_LEN-1:0] mcause;      //0x342
   reg  [`DATA_LEN-1:0] mip;         //0x344

   wire [30:0] mcause1 = (eirq && mie[11]) ? 31'd11 :
                         (tirq && mie[7 ]) ? 31'd7  :
                         (sirq && mie[3 ]) ? 31'd3  : 31'd0;

   assign rob_we = busy;
   assign rrf_we = busy & dstval;
   assign kill_speculative = ((spectag & spectagfix) != 0) && specbit && prmiss;
   assign result = (csr_op == `CSR_WRITE_NOREAD) ? 0 :
       (imm[11:0] == 12'hf14) ? mhartid :
       (imm[11:0] == 12'h300) ? mstatus :
       (imm[11:0] == 12'h304) ? mie     :
       (imm[11:0] == 12'h305) ? mtvec   :
       (imm[11:0] == 12'h341) ? mepc    :
       (imm[11:0] == 12'h342) ? mcause  :
       (imm[11:0] == 12'h344) ? mip     : 0;

   assign mstatus_mie = mstatus[3];

   always @ (posedge clk) begin
      if (reset) begin
         busy <= 0;
         mhartid <= 0;
         mstatus <= 0;
         mie <= 0;
         mip <= 0;
      end else begin
         busy <= issue;

         mip[11] <= eirq ? mie[11] : eirq;
         mip[7]  <= tirq ? mie[7]  : tirq;
         mip[3]  <= sirq ? mie[3]  : sirq;
      end

      // 应该要考虑prmiss的情况吧？
      // 还是应该在commit阶段再更新csr寄存器吧 
      if (csrcommit) begin
      case (csr_op)
        `CSR_WRITE, `CSR_WRITE_NOREAD : begin
            case (imm[11:0])
                12'h300 : mstatus   <= ex_src1;
                12'h304 : mie       <= ex_src1;
                12'h305 : mtvec     <= ex_src1;
                12'h341 : mepc      <= ex_src1;
                12'h344 : mip       <= ex_src1;
            endcase
        end
        `CSR_SET : begin
            case (imm[11:0])
                12'h300 : mstatus   <= mstatus   | ex_src1;
                12'h304 : mie       <= mie       | ex_src1;
                12'h305 : mtvec     <= mtvec     | ex_src1;
                12'h344 : mip       <= mip       | ex_src1;
            endcase
        end
        `CSR_CLEAR : begin
            case (imm[11:0])
                12'h300 : mstatus   <= mstatus   & ~ex_src1;
                12'h304 : mie       <= mie       & ~ex_src1;
                12'h305 : mtvec     <= mtvec     & ~ex_src1;
                12'h344 : mip       <= mip       & ~ex_src1;
            endcase
        end
      endcase
      end

      // 中断确认后屏蔽所有外部irq
      // 未考虑是否同时有csr指令在执行
      if (irq_flush) begin
        mepc <= irq_jmpaddr;
        mstatus[3] <= 1'b0;
        mstatus[7] <= mstatus_mie;
        mcause[31] <= 1'b1;
        mcause[30:0] <= mcause1;
      end

      if (ecall || ebreak) begin
        mepc <= jmpaddr;
        mstatus[3] <= 1'b0;
        mcause[31] <= 1'b0;
        if (ecall)  mcause[30:0] <= 31'd11;
        if (ebreak) mcause[30:0] <= 31'd3;
      end

      // mret返回后，clear外部irq屏蔽
      // 必须是mret确认commit后才执行
      // 否则在mret确认commit前放开，有可能取消mret的执行
      // 然后mepc又被设置，导致前一次的mepc丢失，无法返回
      if (retcommit) begin
          mstatus[3] <= mstatus[7];
          mstatus[7] <= 1'b1;
      end
   end
   
endmodule // exunit_csr

   
`default_nettype wire
