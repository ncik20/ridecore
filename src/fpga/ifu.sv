`include "constants.vh"
`include "rv32_opcodes.vh"
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
    output reg  [`ADDR_LEN-1:0]     pc1,
    output reg  [`ADDR_LEN-1:0]     pc2,
    output reg  [`ADDR_LEN-1:0]     npc1,
    output reg  [`ADDR_LEN-1:0]     npc2,
    output reg                      prcond1,
    output reg                      prcond2,
    output reg  [`GSH_BHR_LEN-1:0]  bhr1,
    output reg  [`GSH_BHR_LEN-1:0]  bhr2,
    output reg  [`INSN_LEN-1:0]     inst1,
    output reg  [`INSN_LEN-1:0] 	inst2,
    output reg                      invalid1,
    output reg                      invalid2,
    output reg  [11:0]              instype_line1,
    output reg  [11:0]              instype_line2,
    output reg                      sameLine
    // output wire                     prmiss,
    // output wire [`ADDR_LEN-1:0]     jmpaddr,
    // output wire [`FTQ_SEL-1:0]      prmiss_ftq_idx
   );

    reg  [`INSN_LEN*4-1:0]  mem[0:`IBUF_NUM-1];
    reg  [`ADDR_LEN-1:0]    buf_pc[0:`IBUF_NUM-1];
    reg  [`ADDR_LEN-1:0]    buf_npc[0:`IBUF_NUM-1];
    reg  [`IBUF_NUM-1:0]    buf_prcond;
    reg  [`GSH_BHR_LEN-1:0] buf_bhr[0:`IBUF_NUM-1];
    reg  [11:0]             buf_instype[0:`IBUF_NUM-1];

    reg  [3:0]              valid[0:`IBUF_NUM-1];
    reg  [3:0]              valid_rdPtr_next;
    reg  [3:0]              valid_rdPtr1_next;
    reg  [`IBUF_NUM-1:0]    used;
    reg  [`IBUF_NUM-1:0]    used_next;

    reg  [3:0]              read_mask1;
    reg  [3:0]              read_mask2;

    reg  [`IBUF_SEL-1:0]    rdPtr;
    wire [`IBUF_SEL-1:0]    rdPtr1;
    reg  [`IBUF_SEL-1:0]    rdPtr_next;
    reg  [`IBUF_SEL-1:0]    wr_iBufPtr;
    reg  [`IBUF_SEL-1:0]    wr_iBufdataPtr;
    reg  [`IBUF_SEL-1:0]    inst2_rdPrt;

    wire [2:0]              rdPtr_valid_cnt;
    wire                    valid0;
    wire                    valid1;
    wire                    valid2;
    wire                    valid3;
    wire [2:0]              instype0;
    wire [2:0]              instype1;
    wire [2:0]              instype2;
    wire [2:0]              instype3;

    reg  [3:0]              pc_offset1;
    reg  [3:0]              pc_offset2;

    wire [3:0]              insvalid;
    wire [11:0]             instype;

    reg                     pc_err;

    // wire [2:0]              first_br_jmp_idx;

    assign full = (used[wr_iBufPtr] == 1'b1);

    assign rdPtr1 = rdPtr + 1;

    assign rdPtr_valid_cnt = valid[rdPtr][0] + valid[rdPtr][1] +
        valid[rdPtr][2] + valid[rdPtr][3];

    // assign stall = req_latch && ~icache_done;
    
    wire [1:0] pc_sel = buf_pc[wr_iBufdataPtr][3:2];
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
        (pc_sel == 2'b00) ? (pc[wr_iBufdataPtr] + 16) :
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
		    for (int i=0; i<`IBUF_NUM; i++) begin
		        valid[i] <= '0;
		    end
        end
        else begin

            rdPtr <= rdPtr_next;
            used <= used_next;
            valid[rdPtr] <= valid_rdPtr_next;
            valid[rdPtr1] <= valid_rdPtr1_next;

            if (icache_req) begin

                buf_pc[wr_iBufPtr] <= pc;
                buf_npc[wr_iBufPtr] <= npc;
                buf_prcond[wr_iBufPtr] <= prcond;
                buf_bhr[wr_iBufPtr] <= bhr;

                wr_iBufPtr <= wr_iBufPtr + 1;
            end

            if (icache_done) begin

                mem[wr_iBufdataPtr] <= idata;

                buf_instype[wr_iBufdataPtr] <= instype;

                valid[wr_iBufdataPtr] <= insvalid;

                wr_iBufdataPtr <= wr_iBufdataPtr + 1;

                if (cpu_res_pc == buf_pc[wr_iBufdataPtr])
                    pc_err <= '0;
                else
                    pc_err <= 1'b1;
            end
        end
    end

	always_comb begin

        read_mask1 = '0;
        read_mask2 = '0;

        used_next = used;
        rdPtr_next = rdPtr;

        valid_rdPtr_next = valid[rdPtr];
        valid_rdPtr1_next = valid[rdPtr1];

        inst2_rdPrt = rdPtr;
        sameLine = 1'b1;

        pc_offset1 = '0;
        pc_offset2 = '0;

        inst1 = '0;
        inst2 = '0;

        invalid1 = 1'b1;
        invalid2 = 1'b1;

        pc1 = '0;
        pc2 = '0;

        npc1 = '0;
        npc2 = '0;

        prcond1 = '0;
        prcond2 = '0;

        bhr1 = '0;
        bhr2 = '0;

        instype_line1 = '0;
        instype_line2 = '0;

        if (icache_req)
            used_next[wr_iBufPtr] = 1'b1;

        if (rdreq) begin
            case(rdPtr_valid_cnt)
                3'd1:begin
                    invalid1 = '0;
                    invalid2 = '0;
                    inst2_rdPrt = rdPtr1;
                    sameLine = '0;

                    if (valid[rdPtr][0]) begin
                        pc_offset1 = 4'd0;
                        inst1 = mem[rdPtr][31-:32];
                        read_mask1 = 4'b0001;
                    end
                    if (valid[rdPtr][1]) begin
                        pc_offset1 = 4'd4;
                        inst1 = mem[rdPtr][(31+32)-:32];
                        read_mask1 = 4'b0010;
                    end
                    if (valid[rdPtr][2]) begin
                        pc_offset1 = 4'd8;
                        inst1 = mem[rdPtr][(31+32*2)-:32];
                        read_mask1 = 4'b0100;
                    end
                    if (valid[rdPtr][3]) begin
                        pc_offset1 = 4'd12;
                        inst1 = mem[rdPtr][(31+32*3)-:32];
                        read_mask1 = 4'b1000;
                    end

                    if (valid[rdPtr1][0]) begin
                        pc_offset2 = 4'd0;
                        inst2 = mem[rdPtr1][31-:32];
                        read_mask2 = 4'b0001;
                    end else if (valid[rdPtr1][1]) begin
                        pc_offset2 = 4'd4;
                        inst2 = mem[rdPtr1][(31+32)-:32];
                        read_mask2 = 4'b0010;
                    end else if (valid[rdPtr1][2]) begin
                        pc_offset2 = 4'd8;
                        inst2 = mem[rdPtr1][(31+32*2)-:32];
                        read_mask2 = 4'b0100;
                    end else if (valid[rdPtr1][3]) begin
                        pc_offset2 = 4'd12;
                        inst2 = mem[rdPtr1][(31+32*3)-:32];
                        read_mask2 = 4'b1000;
                    end else
                        invalid2 = 1'b1;
                end
                3'd2, 3'd3, 3'd4:begin
                    invalid1 = '0;
                    invalid2 = '0;

                    if (valid[rdPtr][0]) begin
                        pc_offset1 = 4'd0;
                        pc_offset2 = 4'd4;
                        inst1 = mem[rdPtr][31-:32];
                        inst2 = mem[rdPtr][(31+32)-:32];
                        read_mask1 = 4'b0011;
                    end else if (valid[rdPtr][1]) begin
                        pc_offset1 = 4'd4;
                        pc_offset2 = 4'd8;
                        inst1 = mem[rdPtr][(31+32)-:32];
                        inst2 = mem[rdPtr][(31+32*2)-:32];
                        read_mask1 = 4'b0110;
                    end else if (valid[rdPtr][2]) begin
                        pc_offset1 = 4'd8;
                        pc_offset2 = 4'd12;
                        inst1 = mem[rdPtr][(31+32*2)-:32];
                        inst2 = mem[rdPtr][(31+32*3)-:32];
                        read_mask1 = 4'b1100;
                    end
                end
            endcase

            pc1 = {buf_pc[rdPtr][`ADDR_LEN-1:4], 4'b0000} + pc_offset1;
            npc1 = buf_npc[rdPtr];
            prcond1 = buf_prcond[rdPtr];
            bhr1 = buf_bhr[rdPtr];
            instype_line1 = buf_instype[rdPtr];

            pc2 = {buf_pc[inst2_rdPrt][`ADDR_LEN-1:4], 4'b0000} + pc_offset2;
            npc2 = buf_npc[inst2_rdPrt];
            prcond2 = buf_prcond[inst2_rdPrt];
            bhr2 = buf_bhr[inst2_rdPrt];
            instype_line2 = buf_instype[inst2_rdPrt];

            if (read_mask2 != 4'b0000) begin
                if (valid[rdPtr1] == 4'b0001 || 
                    valid[rdPtr1] == 4'b0010 || 
                    valid[rdPtr1] == 4'b0100 || 
                    valid[rdPtr1] == 4'b1000)
                begin
                    used_next[rdPtr] = '0;
                    used_next[rdPtr1] = '0;
                    rdPtr_next = rdPtr + 2;
                end
                else begin
                    used_next[rdPtr] = '0;
                    rdPtr_next = rdPtr + 1;
                end
            end
            else if (read_mask1 != 4'b0000 &&
                (rdPtr_valid_cnt == 3'd1 || rdPtr_valid_cnt == 3'd2))
            begin
                used_next[rdPtr] = '0;
                rdPtr_next = rdPtr + 1;
            end
            
            if (read_mask1 != 4'b0000)
                valid_rdPtr_next = valid_rdPtr_next ^ read_mask1;

            if (read_mask2 != 4'b0000)
                valid_rdPtr1_next = valid_rdPtr1_next ^ read_mask2;
        end
    end
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
