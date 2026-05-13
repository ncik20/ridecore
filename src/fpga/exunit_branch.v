`include "constants.vh"
`include "alu_ops.vh"
`include "rv32_opcodes.vh"
`default_nettype none
module exunit_branch
  (
   input wire 			  clk,
   input wire 			  reset,
   input wire             irq_flush,
   input wire [`DATA_LEN-1:0] 	  ex_src1,
   input wire [`DATA_LEN-1:0] 	  ex_src2,
   input wire [`ADDR_LEN-1:0] 	  pc,
   input wire [`DATA_LEN-1:0] 	  imm,
   input wire 			  dstval,
   input wire [`ALU_OP_WIDTH-1:0] alu_op,
   input wire [`SPECTAG_LEN-1:0]  spectag,
   input wire 			  specbit,
   input wire [`ADDR_LEN-1:0] 	  praddr,
   input wire [6:0] 		  opcode,
   input wire 			  issue,
   input wire [`ADDR_LEN-1:0] 	  mtvec,
   input wire [`ADDR_LEN-1:0] 	  mepc,
   input wire [`ADDR_LEN-1:0] 	  dpc,
   input wire                     dbg_mode,
   input wire [`ADDR_LEN-1:0] 	  dbg_entry_pc,
   output wire [`DATA_LEN-1:0] 	  result,
   output wire 			  rrf_we,
   output wire 			  rob_we, //set finish
   output wire 			  prsuccess,
   output wire 			  prmiss,
   output wire [`ADDR_LEN-1:0] 	  jmpaddr,
   output wire [`ADDR_LEN-1:0] 	  jmpaddr_taken,
   output wire 			  brcond,
   output wire [`SPECTAG_LEN-1:0] tagregfix,
   output wire            ecall,
   output wire            ebreak
   );

   reg 			        busy;

   wire [`DATA_LEN-1:0] comprslt;
   wire 		        addrmatch = (jmpaddr == praddr) ? 1'b1 : 1'b0;

   assign rob_we = busy && ~irq_flush;
   assign rrf_we = dstval && rob_we;
   assign prsuccess = addrmatch && rob_we;
   // 为了不影响commit指令更新arf的busy位，添加irq_flush条件
   assign prmiss = ~addrmatch && rob_we; 

   assign ecall  = (opcode == `RV32_SYSTEM && imm[11:0] == `RV32_FUNCT12_ECALL) && rob_we;
   assign ebreak = (opcode == `RV32_SYSTEM && imm[11:0] == `RV32_FUNCT12_EBREAK) && rob_we;

   assign result = pc + 4;
   assign jmpaddr = brcond ? jmpaddr_taken : (pc + 4);
   assign jmpaddr_taken = (opcode == `RV32_SYSTEM && imm[11:0] == `RV32_FUNCT12_DRET) ? dpc :
                          (opcode == `RV32_SYSTEM && imm[11:0] == `RV32_FUNCT12_MRET) ? mepc :
                          (opcode == `RV32_SYSTEM && imm[11:0] == `RV32_FUNCT12_EBREAK && dbg_mode) ? dbg_entry_pc :
                          (opcode == `RV32_SYSTEM) ? {mtvec[31:2], 2'b0} :
                          (((opcode == `RV32_JALR) ? ex_src1 : pc) + imm);
   
   assign brcond = ((opcode == `RV32_JAL) || (opcode == `RV32_JALR) || 
                    (opcode == `RV32_SYSTEM)) ? 1'b1 : comprslt[0];
   assign tagregfix = {spectag[0], spectag[`SPECTAG_LEN-1:1]};
   
   always @ (posedge clk) begin
      if (reset) begin
	 busy <= 0;
      end else begin
	 busy <= issue;
      end
   end
		  
   alu comparator
     (
      .op(alu_op),
      .in1(ex_src1),
      .in2(ex_src2),
      .out(comprslt)
      );
   
endmodule // exunit_branch

`default_nettype wire
