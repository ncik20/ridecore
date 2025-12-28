`include "constants.vh"
`include "rv32_opcodes.vh"
`default_nettype none
module instruction_fetch
(
    input  wire 			        clk,
    input  wire 			        reset,

    input  wire  [`FTQ_SEL-1:0]     fetch_ftq_index,
    input  wire  [1:0]              fetch_pc_sel,
    input  wire  [`INSN_LEN-1:0]    next_fetch_pc,
    input  wire                     next_prcond,

    input  wire                     icache_req,
    input  wire                     icache_done,
    // input  wire  [`ADDR_LEN-1:0] 	cpu_res_pc,
    input  wire  [4*`INSN_LEN-1:0]  idata,
    output wire                     full,
    output wire [3:0]               insvalid,
    output wire [8:0]               instype,

    input  wire                     rdreq,
    output reg  [`FTQ_SEL-1:0]      ftq_idx1,
    output reg  [`FTQ_SEL-1:0]      ftq_idx2,
    output reg  [3:0]               pc_offset1,
    output reg  [3:0]               pc_offset2,
    output reg  [`INSN_LEN-1:0]     inst1,
    output reg  [`INSN_LEN-1:0] 	inst2,
    output reg                      invalid1,
    output reg                      invalid2
   );

    reg  [`INSN_LEN-1:0]    mem0[0:`IBUF_NUM-1];
    reg  [`INSN_LEN-1:0]    mem1[0:`IBUF_NUM-1];
    reg  [`INSN_LEN-1:0]    mem2[0:`IBUF_NUM-1];
    reg  [`INSN_LEN-1:0]    mem3[0:`IBUF_NUM-1];
    reg  [`FTQ_SEL-1:0]     ftq_idx[0:`IBUF_NUM-1];
    reg  [1:0]              pc_sel[0:`IBUF_NUM-1];
    reg  [`IBUF_NUM-1:0]    prcond;
    reg  [3:0]              valid[0:`IBUF_NUM-1];
    reg  [`IBUF_NUM-1:0]    used;

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
    wire [1:0]              instype0;
    wire [1:0]              instype1;
    wire [1:0]              instype2;
    wire [1:0]              instype3;
    wire                    inst0_is_jump;
    wire                    inst1_is_jump;
    wire                    inst2_is_jump;

    assign full = (used[wr_iBufPtr] == 1'b1);

    assign readPtr_plus1 = readPtr + 1;

    assign readPtr_valid_cnt = valid[readPtr][0] + valid[readPtr][1] +
        valid[readPtr][2] + valid[readPtr][3];

    assign insvalid = {valid3, valid2, valid1, valid0};
    assign instype = {instype3, instype2, instype1, instype0};

    // assign stall = req_latch && ~icache_done;
    
    wire nor3 = (instype3 == 2'd0);
    wire nor23 = (instype2 == 2'd0) & nor3;
    wire nor123 = (instype1 == 2'd0) & nor23;
    wire nor0123 = (instype0 == 2'd0) & nor123;

    wire prmiss = (icache_done && prcond[wr_iBufdataPtr] &&
                    ((pc_sel[wr_iBufdataPtr] == 2'b00 && nor0123) ||
                     (pc_sel[wr_iBufdataPtr] == 2'b01 && nor123) ||
                     (pc_sel[wr_iBufdataPtr] == 2'b10 && nor23) ||
                     (pc_sel[wr_iBufdataPtr] == 2'b11 && nor3))
                  ) ? 1'b1 : 1'b0;

    assign inst0_is_jump = (instype0 == 2'd0 || (instype0 == 2'd1 && ~prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;
    assign inst1_is_jump = (instype1 == 2'd0 || (instype1 == 2'd1 && ~prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;
    assign inst2_is_jump = (instype2 == 2'd0 || (instype2 == 2'd1 && ~prcond[wr_iBufdataPtr])) ?
        1'b0 : 1'b1;

    f_decode fdecode0(
        .opcode(idata[6:0]),
		.ins_type(instype0)
		);

    f_decode fdecode1(
        .opcode(idata[38:32]),
		.ins_type(instype1)
		);

    f_decode fdecode2(
        .opcode(idata[70:64]),
		.ins_type(instype2)
		);

    f_decode fdecode3(
        .opcode(idata[102:96]),
		.ins_type(instype3)
		);

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
		);

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
                pc_sel[wr_iBufPtr] <= fetch_pc_sel;
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
            end

            if (rdreq) begin

                if (read_mask2 != 4'b0000) begin
                    if (valid[readPtr_plus1] == 4'b0001 || 
                        valid[readPtr_plus1] == 4'b0010 || 
                        valid[readPtr_plus1] == 4'b0100 || 
                        valid[readPtr_plus1] == 4'b1000)
                    begin
                        used[readPtr] <= '0;
                        used[readPtr + 1] <= '0;

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
    input  wire [6:0]      opcode,
    output wire [1:0]       ins_type
    );

    assign ins_type = (opcode == `RV32_BRANCH) ? 2'd1 :
                      (opcode == `RV32_JAL) ? 2'd2 :
                      (opcode == `RV32_JALR) ? 2'd3 : 2'd0;
endmodule

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
endmodule

`default_nettype wire
