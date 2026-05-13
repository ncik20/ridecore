`include "constants.vh"
`include "rv32_opcodes.vh"
`include "common.h"
`default_nettype none
module instruction_fetch
(
    input  wire 			        clk,
    input  wire 			        reset,

    input  wire  [`ADDR_LEN-1:0]    pc,
    input  wire  [`ADDR_LEN-1:0]    npc,
    input  wire                     prcond,
    input  wire  [`GSH_BHR_LEN-1:0] bhr,

    input  wire                     icache_req,
    input  wire                     icache_done,
    input  wire  [`ADDR_LEN-1:0] 	cpu_res_pc,
    input  wire  [4*`INSN_LEN-1:0]  idata,
    output wire                     full,
    // output wire [3:0]               insvalid,
    // output wire [11:0]              instype,

    input  wire                     rdreq,
    input  wire                     rdOneIns,
    output wire [`ADDR_LEN-1:0]     pc1,
    output wire [`ADDR_LEN-1:0]     pc2,
    output wire [`ADDR_LEN-1:0]     npc1,
    output wire [`ADDR_LEN-1:0]     npc2,
    output wire [`GSH_BHR_LEN-1:0]  bhr1,
    output wire [`GSH_BHR_LEN-1:0]  bhr2,
    output reg                      prcond1,
    output reg                      prcond2,

    output wire [`INSN_LEN-1:0]     inst1,
    output wire [`INSN_LEN-1:0] 	inst2,
    output wire                     invalid1,
    output wire                     invalid2,
    output wire [11:0]              instype_line1,
    output wire [11:0]              instype_line2,
    output reg                      sameLine

    // output wire                     prmiss,
    // output wire [`ADDR_LEN-1:0]     jmpaddr,
    // output wire [`FTQ_SEL-1:0]      prmiss_ftq_idx
   );

    reg  [`IBUF_NUM-1:0]    buf_prcond;

    reg  [3:0]              valid[0:`IBUF_NUM-1];
    reg  [3:0]              valid_rdPtr_next;
    reg  [3:0]              valid_rdPtr1_next;

    reg  [`IBUF_NUM-1:0]    used;
    reg  [`IBUF_NUM-1:0]    used_next;

    reg  [3:0]              read_mask1;
    reg  [3:0]              read_mask2;
    reg  [3:0]              read_mask1_next;
    reg  [3:0]              read_mask2_next;

    reg  [3:0]              pc_offset1;
    reg  [3:0]              pc_offset2;
    reg  [3:0]              pc_offset1_next;
    reg  [3:0]              pc_offset2_next;

    reg  [`IBUF_SEL-1:0]    rdPtr;
    reg  [`IBUF_SEL-1:0]    rdPtr_next;
    reg  [`IBUF_SEL-1:0]    wr_iBufPtr;
    reg  [`IBUF_SEL-1:0]    wr_iBufdataPtr;
    wire [`IBUF_SEL-1:0]    rdPtr1 = rdPtr + 1;

    wire [2:0]              rdPtr_valid_cnt;
    wire                    valid0;
    wire                    valid1;
    wire                    valid2;
    wire                    valid3;
    wire [2:0]              instype0;
    wire [2:0]              instype1;
    wire [2:0]              instype2;
    wire [2:0]              instype3;

    wire [`ADDR_LEN-1:0]    pc_rdPtr;
    wire [`ADDR_LEN-1:0]    pc_rdPtr1;
    wire [`ADDR_LEN-1:0]    npc_rdPtr1;
    wire [`GSH_BHR_LEN-1:0] bhr_rdPtr1;
    wire [11:0]             instype_rdPtr1;

    wire [3:0]              insvalid;
    wire [11:0]             instype;

    wire [`INSN_LEN*4-1:0]  mem_rdPtr;
    wire [`INSN_LEN*4-1:0]  mem_rdPtr1;
    reg  [1:0]              first_valid_rdPtr1;
    reg                     find_valid_rdPtr1;

    wire [1:0] read_mask1_count = read_mask1[0] + read_mask1[1] + read_mask1[2] + read_mask1[3];

    assign sameLine = (read_mask1_count == 2'd1) ? 0 : 1;

    assign pc1 = {pc_rdPtr[`ADDR_LEN-1:4], 4'b0000} + pc_offset1;
    assign pc2 = sameLine ? (pc1 + 4) : {pc_rdPtr1[`ADDR_LEN-1:4], 4'b0000} + pc_offset2;

    assign npc2 = sameLine ? npc1 : npc_rdPtr1;
    assign bhr2 = sameLine ? bhr1 : bhr_rdPtr1;
    assign instype_line2 = sameLine ? instype_line1 : instype_rdPtr1;

    assign inst1 = read_mask1[0] ? mem_rdPtr[31+32*0-:32] :
                   read_mask1[1] ? mem_rdPtr[31+32*1-:32] :
                   read_mask1[2] ? mem_rdPtr[31+32*2-:32] :
                   read_mask1[3] ? mem_rdPtr[31+32*3-:32] : 0;

    assign invalid1 = (inst1 == 0) ? 1 : 0;

    assign inst2 = (read_mask1_count == 2'd2 && read_mask1[0]) ? mem_rdPtr[31+32*1-:32] :
                   (read_mask1_count == 2'd2 && read_mask1[1]) ? mem_rdPtr[31+32*2-:32] :
                   (read_mask1_count == 2'd2 && read_mask1[2]) ? mem_rdPtr[31+32*3-:32] :
                   (read_mask1_count == 2'd1 && read_mask2[0]) ? mem_rdPtr1[31+32*0-:32] :
                   (read_mask1_count == 2'd1 && read_mask2[1]) ? mem_rdPtr1[31+32*1-:32] :
                   (read_mask1_count == 2'd1 && read_mask2[2]) ? mem_rdPtr1[31+32*2-:32] :
                   (read_mask1_count == 2'd1 && read_mask2[3]) ? mem_rdPtr1[31+32*3-:32] : 0;

    assign invalid2 = (inst2 == 0) ? 1 : 0;

    assign full = (used[wr_iBufPtr] == 1'b1);

    assign rdPtr_valid_cnt = valid[rdPtr][0] + valid[rdPtr][1] +
        valid[rdPtr][2] + valid[rdPtr][3];

    // assign stall = req_latch && ~icache_done;


    wire [1:0] pc_sel = cpu_res_pc[3:2];
    // wire [1:0] pc_sel = buf_pc[wr_iBufdataPtr][3:2];
/*    
    wire no_jmp_br_prmiss = (icache_done && prcond[wr_iBufdataPtr] &&
                    ((pc_sel == 2'b00 && instype == 12'd0) ||
                     (pc_sel == 2'b01 && instype[11-:9] == 9'd0) ||
                     (pc_sel == 2'b10 && instype[11-:6] == 6'd0) ||
                     (pc_sel == 2'b11 && instype[11-:3] == 3'd0))) ? 1'b1 : 1'b0;

    wire jal_prmiss = (icache_done && ~prcond[wr_iBufdataPtr] &&
            ((first_br_jmp_idx == 3'd0 && idata[6-:7] == `RV32_JAL) ||
             (first_br_jmp_idx == 3'd1 && idata[(6+32)-:7] == `RV32_JAL) ||
             (first_br_jmp_idx == 3'd2 && idata[(6+32*2)-:7] == `RV32_JAL) ||
             (first_br_jmp_idx == 3'd3 && idata[(6+32*3)-:7] == `RV32_JAL))) ? 1'b1 : 1'b0;

    assign prmiss = (no_jmp_br_prmiss | jal_prmiss);

    wire [`DATA_LEN-1:0] jal_inst = (first_br_jmp_idx == 3'd0) ? idata[31-:32] :
                                    (first_br_jmp_idx == 3'd1) ? idata[(31+32)-:32] :
                                    (first_br_jmp_idx == 3'd2) ? idata[(31+32*2)-:32] :
                                                                 idata[(31+32*3)-:32];

    wire [`DATA_LEN-1:0] jal_offset = 
        { {12{jal_inst[31]}}, jal_inst[19:12], jal_inst[20], jal_inst[30:21], 1'b0 };

    assign jmpaddr = jal_prmiss ? (pc[wr_iBufdataPtr] + first_br_jmp_idx * 4 + jal_offset) :
        (pc_sel == 2'b00) ? (pc[wr_iBufdataPt    assign prcond1 = buf_prcond[rdPtr];
    assign prcond2 = sameLine ? buf_prcond[rdPtr] : buf_prcond[rdPtr1];r] + 16) :
        (pc_sel == 2'b01) ? (pc[wr_iBufdataPtr] + 12) :
        (pc_sel == 2'b10) ? (pc[wr_iBufdataPtr] + 8) :
                            (pc[wr_iBufdataPtr] + 4);
*/
    // assign prmiss_ftq_idx = ftq_idx[wr_iBufdataPtr];

    wire inst0_is_jump = (instype0 == 3'd0 || (instype0 == 3'd1 && ~buf_prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;
    wire inst1_is_jump = (instype1 == 3'd0 || (instype1 == 3'd1 && ~buf_prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;
    wire inst2_is_jump = (instype2 == 3'd0 || (instype2 == 3'd1 && ~buf_prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;

    assign valid0 = (pc_sel == 2'b00) ? 1'b1 : 1'b0;

    assign valid1 = (pc_sel == 2'b10 || pc_sel == 2'b11 ||
                     (pc_sel == 2'b00 && inst0_is_jump)) ? 1'b0 : 1'b1;

    assign valid2 = (pc_sel == 2'b11 ||
                     (pc_sel == 2'b00 && (inst0_is_jump || inst1_is_jump)) ||
                     (pc_sel == 2'b01 && inst1_is_jump)) ? 1'b0 : 1'b1;

    assign valid3 = (
                     (pc_sel == 2'b00 && (inst0_is_jump || inst1_is_jump || inst2_is_jump)) ||
                     (pc_sel == 2'b01 && (inst1_is_jump || inst2_is_jump)) ||
                     (pc_sel == 2'b10 && inst2_is_jump)) ? 1'b0 : 1'b1;

    assign insvalid = {valid3, valid2, valid1, valid0};

    assign instype = {instype3, instype2, instype1, instype0};

    f_decode fdecode0(
        .opcode(idata[6-:7]),
        .rd(idata[11-:5]),
        .rs1(idata[19-:5]),
		.ins_type(instype0)
		);

    f_decode fdecode1(
        .opcode(idata[(6+32)-:7]),
        .rd(idata[(11+32)-:5]),
        .rs1(idata[(19+32)-:5]),
		.ins_type(instype1)
		);

    f_decode fdecode2(
        .opcode(idata[(6+32*2)-:7]),
        .rd(idata[(11+32*2)-:5]),
        .rs1(idata[(19+32*2)-:5]),
		.ins_type(instype2)
		);

    f_decode fdecode3(
        .opcode(idata[(6+32*3)-:7]),
        .rd(idata[(11+32*3)-:5]),
        .rs1(idata[(19+32*3)-:5]),
		.ins_type(instype3)
		);

    integer i;
    always_ff @(posedge(clk)) begin
        if (reset) begin
            wr_iBufPtr <= '0;
            wr_iBufdataPtr <= '0;
            rdPtr <= '0;

            used <= '0;

            read_mask1 <= '0;
            read_mask2 <= '0;

            pc_offset1 <= '0;
            pc_offset2 <= '0;

		    for (i = 0; i < `IBUF_NUM; i++) begin
		        valid[i] <= '0;
		    end
        end
        else begin

            read_mask1 <= read_mask1_next;
            read_mask2 <= read_mask2_next;

            pc_offset1 <= pc_offset1_next;
            pc_offset2 <= pc_offset2_next;

            if (rdreq) begin
                used <= used_next;

                rdPtr <= rdPtr_next;
                valid[rdPtr] <= valid_rdPtr_next;
                valid[rdPtr1] <= valid_rdPtr1_next;

                prcond1 <= buf_prcond[rdPtr];
                prcond2 <= (read_mask2_next != 0) ? buf_prcond[rdPtr1] : buf_prcond[rdPtr];
            end else if (icache_req) begin
                used[wr_iBufPtr] <= 1'b1;
            end

            if (icache_req) begin
                buf_prcond[wr_iBufPtr] <= prcond;
                wr_iBufPtr <= wr_iBufPtr + 1;
            end

            if (icache_done) begin
                valid[wr_iBufdataPtr] <= insvalid;
                wr_iBufdataPtr <= wr_iBufdataPtr + 1;
            end
        end
    end

    integer j;
	always_comb begin

        used_next = used;
        rdPtr_next = rdPtr;

        valid_rdPtr_next = valid[rdPtr];
        valid_rdPtr1_next = valid[rdPtr1];

        read_mask1_next = '0;
        read_mask2_next = '0;

        pc_offset1_next = '0;
        pc_offset2_next = '0;

        find_valid_rdPtr1 = '0;
        first_valid_rdPtr1 = '0;

        for (j = 3; j >= 0; j = j - 1) begin
            if (valid_rdPtr1_next[j]) begin
                find_valid_rdPtr1 = 1'b1;
                first_valid_rdPtr1 = j;
            end
        end

        if (icache_req) begin
            used_next[wr_iBufPtr] = 1'b1;
        end

        if (rdreq) begin
            case(rdPtr_valid_cnt)
                3'd1:begin
                    
                    read_mask1_next = valid_rdPtr_next;
                    pc_offset1_next = `CLOG2(valid_rdPtr_next) * 4;

                    if (~rdOneIns) begin
                        read_mask2_next = find_valid_rdPtr1 ? (4'b0001 << first_valid_rdPtr1) :
                                                              read_mask2_next;
                        pc_offset2_next = first_valid_rdPtr1 * 4;
                    end
                end
                3'd2, 3'd3, 3'd4:begin
                    if (valid_rdPtr_next[0]) begin
                        pc_offset1_next = 4'd0;
                        read_mask1_next = rdOneIns ? 4'b0001 : 4'b0011;
                    end else if (valid_rdPtr_next[1]) begin
                        pc_offset1_next = 4'd4;
                        read_mask1_next = rdOneIns ? 4'b0010 : 4'b0110;
                    end else if (valid_rdPtr_next[2]) begin
                        pc_offset1_next = 4'd8;
                        read_mask1_next = rdOneIns ? 4'b0100 : 4'b1100;
                    end
                end
            endcase

            if (read_mask2_next != 4'b0000) begin
                if (valid_rdPtr1_next == 4'b0001 || 
                    valid_rdPtr1_next == 4'b0010 || 
                    valid_rdPtr1_next == 4'b0100 || 
                    valid_rdPtr1_next == 4'b1000)
                begin
                    used_next[rdPtr] = '0;
                    used_next[rdPtr1] = '0;
                    rdPtr_next = rdPtr + 2;
                end
                else begin
                    used_next[rdPtr] = '0;
                    rdPtr_next = rdPtr1;
                end
            end
            else if (read_mask1_next != 4'b0000 &&
                (rdPtr_valid_cnt == 3'd1 || rdPtr_valid_cnt == 3'd2))
            begin
                used_next[rdPtr] = '0;
                rdPtr_next = rdPtr1;
            end
            
            if (read_mask1_next != 4'b0000) begin
                valid_rdPtr_next = valid_rdPtr_next ^ read_mask1_next;
            end

            if (read_mask2_next != 4'b0000) begin
                valid_rdPtr1_next = valid_rdPtr1_next ^ read_mask2_next;
            end
        end
        // 为什么不在一开始按照以下设置初始值
        // 如果读iBuf(rdreq==1)，但是valid[rdPtr]为0导致无读出
        // 则read_mask1_next、pc_offset1_next都应该为0
        // 而不是read_mask1、pc_offset1
        else begin
            read_mask1_next = read_mask1;
            read_mask2_next = read_mask2;

            pc_offset1_next = pc_offset1;
            pc_offset2_next = pc_offset2;
        end
    end

   ram_sync_2r1w_2bank #(
    .BRAM_ADDR_WIDTH    (`IBUF_SEL),
	.BRAM_DATA_WIDTH    (`INSN_LEN*4),
	.DATA_DEPTH         (`IBUF_NUM)
   ) mem (
    .clk                (clk),
    .raddr1             (rdPtr),
    .raddr2             (rdPtr1),
    .rdata1             (mem_rdPtr),
    .rdata2             (mem_rdPtr1),
    .waddr1             (wr_iBufdataPtr),
    .wdata1             (idata),
    .we1                (icache_done),
    .rden               (rdreq)
   );

   ram_sync_2r1w_2bank #(
    .BRAM_ADDR_WIDTH    (`IBUF_SEL),
	.BRAM_DATA_WIDTH    (12),
	.DATA_DEPTH         (`IBUF_NUM)
   ) buf_instype (
    .clk                (clk),
    .raddr1             (rdPtr),
    .raddr2             (rdPtr1),
    .rdata1             (instype_line1),
    .rdata2             (instype_rdPtr1),
    .waddr1             (wr_iBufdataPtr),
    .wdata1             (instype),
    .we1                (icache_done),
    .rden               (rdreq)
   );

   ram_sync_2r1w_2bank #(
    .BRAM_ADDR_WIDTH    (`IBUF_SEL),
	.BRAM_DATA_WIDTH    (`ADDR_LEN),
	.DATA_DEPTH         (`IBUF_NUM)
   ) buf_pc (
    .clk                (clk),
    .raddr1             (rdPtr),
    .raddr2             (rdPtr1),
    .rdata1             (pc_rdPtr),
    .rdata2             (pc_rdPtr1),
    .waddr1             (wr_iBufPtr),
    .wdata1             (pc),
    .we1                (icache_req),
    .rden               (rdreq)
   );

   ram_sync_2r1w_2bank #(
    .BRAM_ADDR_WIDTH    (`IBUF_SEL),
	.BRAM_DATA_WIDTH    (`ADDR_LEN),
	.DATA_DEPTH         (`IBUF_NUM)
   ) buf_npc (
    .clk                (clk),
    .raddr1             (rdPtr),
    .raddr2             (rdPtr1),
    .rdata1             (npc1),
    .rdata2             (npc_rdPtr1),
    .waddr1             (wr_iBufPtr),
    .wdata1             (npc),
    .we1                (icache_req),
    .rden               (rdreq)
   );

   ram_sync_2r1w_2bank #(
    .BRAM_ADDR_WIDTH    (`IBUF_SEL),
	.BRAM_DATA_WIDTH    (`GSH_BHR_LEN),
	.DATA_DEPTH         (`IBUF_NUM)
   ) buf_bhr (
    .clk                (clk),
    .raddr1             (rdPtr),
    .raddr2             (rdPtr1),
    .rdata1             (bhr1),
    .rdata2             (bhr_rdPtr1),
    .waddr1             (wr_iBufPtr),
    .wdata1             (bhr),
    .we1                (icache_req),
    .rden               (rdreq)
   );
endmodule

module f_decode(
    input  wire [6:0]       opcode,
    input  wire [4:0]       rd,
    input  wire [4:0]       rs1,
    output wire [2:0]       ins_type
    );

    assign ins_type = (opcode == `RV32_BRANCH) ? 3'd1 :

        (opcode == `RV32_JAL && (rd != 5'd1 && rd != 5'd5)) ? 3'd2 :

        (opcode == `RV32_JALR && (rd != 5'd1 && rd != 5'd5)
                              && (rs1 != 5'd1 && rs1 != 5'd5)) ? 3'd3 :

        (
         (opcode == `RV32_JAL && (rd == 5'd1 || rd == 5'd5)) ||
         ((opcode == `RV32_JALR && (rd == 5'd1 || rd == 5'd5)) &&
          ((rs1 != 5'd1 && rs1 != 5'd5) || ((rs1 == 5'd1 || rs1 == 5'd5) && rd == rs1)))
        ) ? 3'd4 :

        (opcode == `RV32_JALR && (rd != 5'd1 && rd != 5'd5)
                              && (rs1 == 5'd1 || rs1 == 5'd5)) ? 3'd5 :

        (opcode == `RV32_JALR && (rd == 5'd1 || rd == 5'd5)
                              && (rs1 == 5'd1 || rs1 == 5'd5)
                              && rd != rs1) ? 3'd6 : 3'd0;
endmodule

`default_nettype wire
