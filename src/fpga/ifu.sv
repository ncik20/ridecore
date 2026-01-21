`include "constants.vh"
`include "rv32_opcodes.vh"
`default_nettype none
module instruction_fetch
(
    input  wire 			        clk,
    input  wire 			        reset,

    input  wire  [`FTQ_SEL-1:0]     fetch_ftq_index,
    input  wire  [`ADDR_LEN-1:0]    fetch_pc,
    // input  wire  [`ADDR_LEN-1:0]    next_fetch_pc,
    input  wire                     next_prcond,

    input  wire                     icache_req,
    input  wire                     icache_done,
    input  wire  [`ADDR_LEN-1:0] 	cpu_res_pc,
    input  wire  [4*`INSN_LEN-1:0]  idata,
    output wire                     full,
    output wire [3:0]               insvalid,
    output wire [11:0]              instype,

    input  wire                     rdreq,
    output reg  [`FTQ_SEL-1:0]      ftq_idx1,
    output reg  [`FTQ_SEL-1:0]      ftq_idx2,
    output reg  [3:0]               pc_offset1,
    output reg  [3:0]               pc_offset2,
    output reg  [`INSN_LEN-1:0]     inst1,
    output reg  [`INSN_LEN-1:0] 	inst2,
    output reg                      invalid1,
    output reg                      invalid2,

    output wire                     prmiss,
    output wire [`ADDR_LEN-1:0]     jmpaddr,
    output wire [`FTQ_SEL-1:0]      prmiss_ftq_idx
   );

    reg  [`INSN_LEN-1:0]    mem0[0:`IBUF_NUM-1];
    reg  [`INSN_LEN-1:0]    mem1[0:`IBUF_NUM-1];
    reg  [`INSN_LEN-1:0]    mem2[0:`IBUF_NUM-1];
    reg  [`INSN_LEN-1:0]    mem3[0:`IBUF_NUM-1];
    reg  [`FTQ_SEL-1:0]     ftq_idx[0:`IBUF_NUM-1];
    reg  [`ADDR_LEN-1:0]    pc[0:`IBUF_NUM-1];
    reg  [`IBUF_NUM-1:0]    prcond;
    reg  [3:0]              valid[0:`IBUF_NUM-1];
    reg  [`IBUF_NUM-1:0]    used;
    wire [`IBUF_NUM-1:0]    used_after_prmiss;
    wire [`IBUF_NUM-1:0]    used_set2bit;

    reg  [3:0]              read_mask1;
    reg  [3:0]              read_mask2;

    reg  [`IBUF_SEL-1:0]    readPtr;
    reg  [`IBUF_SEL-1:0]    wr_iBufPtr;
    reg  [`IBUF_SEL-1:0]    wr_iBufdataPtr;

    wire [`IBUF_SEL-1:0]    readPtr_plus1;
    wire [2:0]              readPtr_valid_cnt;
    wire                    valid0;
    wire                    valid1;
    wire                    valid2;
    wire                    valid3;
    wire [2:0]              instype0;
    wire [2:0]              instype1;
    wire [2:0]              instype2;
    wire [2:0]              instype3;

    reg                     pc_err;

    wire [2:0]              first_br_jmp_idx;

    assign full = (used[wr_iBufPtr] == 1'b1);

    assign readPtr_plus1 = readPtr + 1;

    assign readPtr_valid_cnt = valid[readPtr][0] + valid[readPtr][1] +
        valid[readPtr][2] + valid[readPtr][3];

    // assign stall = req_latch && ~icache_done;
    
    wire [1:0] pc_sel = pc[wr_iBufdataPtr][3:2];
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

    assign prmiss_ftq_idx = ftq_idx[wr_iBufdataPtr];

    wire inst0_is_jump = (instype0 == 3'd0 || (instype0 == 3'd1 && ~prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;
    wire inst1_is_jump = (instype1 == 3'd0 || (instype1 == 3'd1 && ~prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;
    wire inst2_is_jump = (instype2 == 3'd0 || (instype2 == 3'd1 && ~prcond[wr_iBufdataPtr])) ?
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

    genvar m;
	generate
		for(m = 0; m < `IBUF_NUM; m = m + 1) begin: set_used_prmiss

            assign used_after_prmiss[m] = (wr_iBufPtr > wr_iBufdataPtr) ?
                ((m > wr_iBufdataPtr && m < wr_iBufPtr) ? '0 : used[m]) :
                ((m < wr_iBufPtr || m > wr_iBufdataPtr) ? '0 : used[m]);

            assign used_set2bit[m] = (m == readPtr || m == readPtr_plus1) ? '0 : used[m];
        end
    endgenerate

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

   fetch_packet_info fpi_ifu(
        .pc_sel(pc_sel),
        .instype(instype),
        .first_br_jmp_idx(first_br_jmp_idx)
		);
/*
    inst_valid inst0_valid(
        .inst_offset(2'd0),
        .icache_done(icache_done),
        .pc_sel(pc_sel[wr_iBufdataPtr]),
        .jump0(inst0_is_jump),
        .jump1(inst1_is_jump),
        .jump2(inst2_is_jump),
		.valid(valid0)
		);

    inst_valid inst1_valid(
        .inst_offset(2'd1),
        .icache_done(icache_done),
        .pc_sel(pc_sel[wr_iBufdataPtr]),
        .jump0(inst0_is_jump),
        .jump1(inst1_is_jump),
        .jump2(inst2_is_jump),
		.valid(valid1)
		);

    inst_valid inst2_valid(
        .inst_offset(2'd2),
        .icache_done(icache_done),
        .pc_sel(pc_sel[wr_iBufdataPtr]),
        .jump0(inst0_is_jump),
        .jump1(inst1_is_jump),
        .jump2(inst2_is_jump),
		.valid(valid2)
		);

    inst_valid inst3_valid(
        .inst_offset(2'd3),
        .icache_done(icache_done),
        .pc_sel(pc_sel[wr_iBufdataPtr]),
        .jump0(inst0_is_jump),
        .jump1(inst1_is_jump),
        .jump2(inst2_is_jump),
		.valid(valid3)
		);*/

    integer i;
    always_ff @(posedge(clk)) begin
        if (reset) begin
            wr_iBufPtr <= '0;
            wr_iBufdataPtr <= '0;
            readPtr <= '0;

            used <= '0;
		    for (int i=0; i<`IBUF_NUM; i++) begin
		        valid[i] <= '0;
		    end
        end
        else begin
            if (icache_req) begin
                // req_latch <= fetch_req;
                // ftq_index_latch <= fetch_ftq_index;
                // pc_sel_latch <= fetch_pc_sel;
                // npc_latch <= next_fetch_pc;
                ftq_idx[wr_iBufPtr] <= fetch_ftq_index;
                pc[wr_iBufPtr] <= fetch_pc;
                prcond[wr_iBufPtr] <= next_prcond;

                used[wr_iBufPtr] <= 1'b1;
                wr_iBufPtr <= wr_iBufPtr + 1;
            end

            if (icache_done) begin

                mem0[wr_iBufdataPtr] <= idata[31 -:32];
                mem1[wr_iBufdataPtr] <= idata[63 -:32];
                mem2[wr_iBufdataPtr] <= idata[95 -:32];
                mem3[wr_iBufdataPtr] <= idata[127-:32];

                valid[wr_iBufdataPtr] <= insvalid;

                wr_iBufdataPtr <= wr_iBufdataPtr + 1;

                if (cpu_res_pc == pc[wr_iBufdataPtr])
                    pc_err <= '0;
                else
                    pc_err <= 1'b1;
            end

            if (prmiss) begin
                wr_iBufPtr <= wr_iBufdataPtr + 1;

                used <= used_after_prmiss;
            end

            if (rdreq) begin

                if (read_mask2 != 4'b0000) begin
                    if (valid[readPtr_plus1] == 4'b0001 || 
                        valid[readPtr_plus1] == 4'b0010 || 
                        valid[readPtr_plus1] == 4'b0100 || 
                        valid[readPtr_plus1] == 4'b1000)
                    begin
                        // 以下代码，有可能会导致used[readPtr]成功设置为0，
                        // 但是used[readPtr + 1]没有设置为0
                        // used[readPtr] <= '0;
                        // used[readPtr + 1] <= '0;

                        used <= used_set2bit;

                        readPtr <= readPtr + 2;
                    end
                    else begin
                        used[readPtr] <= '0;

                        readPtr <= readPtr + 1;
                    end
                end
                else if (read_mask1 != 4'b0000 &&
                    (readPtr_valid_cnt == 3'd1 || readPtr_valid_cnt == 3'd2))
                begin
                    used[readPtr] <= '0;

                    readPtr <= readPtr + 1;
                end
                
                if (read_mask1 != 4'b0000)
                    valid[readPtr] <= valid[readPtr] ^ read_mask1;

                if (read_mask2 != 4'b0000)
                    valid[readPtr_plus1] <= valid[readPtr_plus1] ^ read_mask2;
            end
        end
    end

	always_comb begin

        read_mask1 = '0;
        read_mask2 = '0;

        ftq_idx1 = ftq_idx[readPtr];
        ftq_idx2 = ftq_idx[readPtr];

        pc_offset1 = '0;
        pc_offset2 = '0;

        inst1 = '0;
        inst2 = '0;

        invalid1 = 1'b1;
        invalid2 = 1'b1;

        if (rdreq) begin
            case(readPtr_valid_cnt)
                3'd1:begin
                    invalid1 = '0;
                    invalid2 = '0;
                    ftq_idx2 = ftq_idx[readPtr_plus1];

                    if (valid[readPtr][0]) begin
                        pc_offset1 = 4'd0;
                        inst1 = mem0[readPtr];
                        read_mask1 = 4'b0001;
                    end
                    if (valid[readPtr][1]) begin
                        pc_offset1 = 4'd4;
                        inst1 = mem1[readPtr];
                        read_mask1 = 4'b0010;
                    end
                    if (valid[readPtr][2]) begin
                        pc_offset1 = 4'd8;
                        inst1 = mem2[readPtr];
                        read_mask1 = 4'b0100;
                    end
                    if (valid[readPtr][3]) begin
                        pc_offset1 = 4'd12;
                        inst1 = mem3[readPtr];
                        read_mask1 = 4'b1000;
                    end

                    if (valid[readPtr_plus1][0]) begin
                        pc_offset2 = 4'd0;
                        inst2 = mem0[readPtr_plus1];
                        read_mask2 = 4'b0001;
                    end else if (valid[readPtr_plus1][1]) begin
                        pc_offset2 = 4'd4;
                        inst2 = mem1[readPtr_plus1];
                        read_mask2 = 4'b0010;
                    end else if (valid[readPtr_plus1][2]) begin
                        pc_offset2 = 4'd8;
                        inst2 = mem2[readPtr_plus1];
                        read_mask2 = 4'b0100;
                    end else if (valid[readPtr_plus1][3]) begin
                        pc_offset2 = 4'd12;
                        inst2 = mem3[readPtr_plus1];
                        read_mask2 = 4'b1000;
                    end else
                        invalid2 = 1'b1;
                end
                3'd2, 3'd3, 3'd4:begin
                    invalid1 = '0;
                    invalid2 = '0;

                    if (valid[readPtr][0]) begin
                        pc_offset1 = 4'd0;
                        pc_offset2 = 4'd4;
                        inst1 = mem0[readPtr];
                        inst2 = mem1[readPtr];
                        read_mask1 = 4'b0011;
                    end else if (valid[readPtr][1]) begin
                        pc_offset1 = 4'd4;
                        pc_offset2 = 4'd8;
                        inst1 = mem1[readPtr];
                        inst2 = mem2[readPtr];
                        read_mask1 = 4'b0110;
                    end else if (valid[readPtr][2]) begin
                        pc_offset1 = 4'd8;
                        pc_offset2 = 4'd12;
                        inst1 = mem2[readPtr];
                        inst2 = mem3[readPtr];
                        read_mask1 = 4'b1100;
                    end
                end
            endcase
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
/*
module inst_valid(
    input  wire [1:0]       inst_offset,
    input  wire             icache_done,
    input  wire [1:0]       pc_sel,
    input  wire 			jump0,
    input  wire 			jump1,
    input  wire 			jump2,
    output reg 			    valid
    );

	always_comb begin
        valid = '0;

        // 1）如果是jal，jalr，必定跳转，后面的指令无效
        // 2）如果是branch，并且预测跳转，则后面的指令无效
        // 3）如果是jal，可以算出跳转地址

        if (icache_done) begin
            case(pc_sel)
                2'b00 : begin
                    case (inst_offset)
                        2'd0 : valid = 1'b1;
                        2'd1 : if (~jump0) valid = 1'b1;
                        2'd2 : if (~(jump0 || jump1)) valid = 1'b1;
                        2'd3 : if (~(jump0 || jump1 || jump2)) valid = 1'b1;
                    endcase
                end
                2'b01 : begin
                    case (inst_offset)
                        2'd1 : valid = 1'b1;
                        2'd2 : if (~jump1) valid = 1'b1;
                        2'd3 : if (~(jump1 || jump2)) valid = 1'b1;
                    endcase
                end
                2'b10 : begin
                    case (inst_offset)
                        2'd2 : valid = 1'b1;
                        2'd3 : if (~jump2) valid = 1'b1;
                    endcase
                end
                2'b11 : begin
                    if (inst_offset == 2'd3) valid = 1'b1;
                end
            endcase
        end
    end
endmodule*/

`default_nettype wire
