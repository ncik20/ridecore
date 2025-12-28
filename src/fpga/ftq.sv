`include "constants.vh"
`default_nettype none
module fetch_target_queue
(
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     irq_flush,
    input  wire                     prmiss,
    input  wire [`ADDR_LEN-1:0]     jmpaddr,
    input  wire [`FTQ_SEL-1:0]      prmiss_ftq_idx,
    input  wire [3:0]               prmiss_pc_offset,

    input  wire                     read_en1,
    input  wire [`FTQ_SEL-1:0]      ftq_index1,
    output wire [`ADDR_LEN-1:0]     start_addr1,
    output wire [`ADDR_LEN-1:0]     npc1,
    output wire                     predict_cond1,
    output wire [`GSH_BHR_LEN-1:0]  bhr1,

    input  wire                     read_en2,
    input  wire [`FTQ_SEL-1:0]      ftq_index2,
    output wire [`ADDR_LEN-1:0]     start_addr2,
    output wire [`ADDR_LEN-1:0]     npc2,
    output wire                     predict_cond2,
    output wire [`GSH_BHR_LEN-1:0]  bhr2,

    // from bpu
    input  wire [`ADDR_LEN-1:0]     predict_npc,
    input  wire                     predict_cond,
    input  wire [`GSH_BHR_LEN-1:0]  bhr,
    // to bpu
    output reg  [`ADDR_LEN-1:0]     pc,

    // from ifu
    input  wire                     full,
    input  wire [3:0]               insvalid,
    input  wire [8:0]               instype,
    // to ifu
    // output wire                     fetch_req,
    output wire [`FTQ_SEL-1:0]      fetch_ftq_index,
    output wire [`INSN_LEN-1:0]     fetch_pc,
    output wire [`INSN_LEN-1:0]     next_fetch_pc,
    output wire                     next_prcond,

    // to icache
    output wire                     icache_req,
    // from icache
    input  wire                     icache_req_ok,
    input  wire                     icache_done,

    // commit info
    input  wire                     commit1,
    input  wire                     commit2,
    input  wire [`FTQ_SEL-1:0]      com_ftq_idx1,
    input  wire [`FTQ_SEL-1:0]      com_ftq_idx2,
    input  wire [3:0]               com_pc_offset1,
    input  wire [3:0]               com_pc_offset2
);

	// localparam FTQ_SEL          = `CLOG2(`FTQ_NUM);

    // from bpu
    reg  [`ADDR_LEN-1:0]        startAddr       [0:`FTQ_NUM-1];
    reg  [`ADDR_LEN-1:0]        npc             [0:`FTQ_NUM-1];
    reg  [`GSH_BHR_LEN-1:0]     ghr             [0:`FTQ_NUM-1];
    reg  [`FTQ_NUM-1:0]         prcond;
    // from ifu
    reg  [3:0]                  ins_valid       [0:`FTQ_NUM-1];
    reg  [7:0]                  ins_type        [0:`FTQ_NUM-1];

    // ftq control reg
    reg  [`FTQ_NUM-1:0]         valid;
    reg  [`FTQ_NUM-1:0]         is_wb;
    // ftq control ptr
    reg  [`FTQ_SEL-1:0]         bpuPtr;
    reg  [`FTQ_SEL-1:0]         ifuPtr;
    reg  [`FTQ_SEL-1:0]         ifuWbPtr;
    reg  [`FTQ_SEL-1:0]         comPtr;

    wire [`FTQ_NUM-1:0]         valid_after_prmiss;

    wire [`FTQ_SEL-1:0] prmiss_ftq_idx_plus1 = prmiss_ftq_idx + 1;

    wire [3:0] prmiss_invalid = (prmiss_pc_offset == 4'd0) ? 4'b1110 :
                                (prmiss_pc_offset == 4'd4) ? 4'b1100 :
                                (prmiss_pc_offset == 4'd8) ? 4'b1000 : 4'b0000;

	// wire [`FTQ_NUM-1:0]		   found_in_ftq;
    // wire [`FTQ_SEL-1:0]         index;

    // ifuPtr与bpuPtr相等，说明bpuPtr阻塞了，ifuPtr指向的应该已经取过指令了
    assign icache_req = (ifuPtr != bpuPtr && valid[ifuPtr] && icache_req_ok && ~full) ? 1'b1 : 1'b0;

    // assign fetch_req = valid[ifuPtr];
    assign fetch_ftq_index = ifuPtr;
    assign fetch_pc = startAddr[ifuPtr];
    assign next_fetch_pc = npc[ifuPtr];
    assign next_prcond = prcond[ifuPtr];

    assign start_addr1 = read_en1 ? startAddr[ftq_index1] : 'z;
    assign npc1 = read_en1 ? npc[ftq_index1] : 'z;
    assign predict_cond1 = read_en1 ? prcond[ftq_index1] : 'z;
    assign bhr1 = read_en1 ? ghr[ftq_index1] : 'z;

    assign start_addr2 = read_en2 ? startAddr[ftq_index2] : 'z;
    assign npc2 = read_en2 ? npc[ftq_index2] : 'z;
    assign predict_cond2 = read_en2 ? prcond[ftq_index2] : 'z;
    assign bhr2 = read_en2 ? ghr[ftq_index2] : 'z;

    genvar i;
	generate
		for(i = 0; i < `FTQ_NUM; i = i + 1) begin: set_vaild_prmiss
			// assign found_in_ftq[i] = (fetch_index[i] == fetch_pc[`ADDR_LEN-1:4]);

            assign valid_after_prmiss[i] = (bpuPtr > prmiss_ftq_idx) ?
                ((i > prmiss_ftq_idx && i < bpuPtr) ? '0 : valid[i]) :
                ((i < bpuPtr || i > prmiss_ftq_idx) ? '0 : valid[i]);
        end
    endgenerate

    // assign index = `CLOG2(found_in_ftq);
    // assign npc_o = (found_in_ftq != 0) ? npc[index] : 'z;

    always @ (posedge clk) begin
        if (reset) begin

	        bpuPtr <= '0;
	        ifuPtr <= '0;
            ifuWbPtr <= '0;
            comPtr <= '0;

            valid <= '0;
            is_wb <= '0;

            pc <= `ENTRY_POINT;
        end
        else if (irq_flush) begin
            pc <= `IRQ_POINT;

            // TODO
            // prmiss发生branch指令所在的frq如何处理？
        end
        else if (prmiss) begin
            pc <= jmpaddr;

            // 要考虑需要设置为invalid的指令，其原本就有可能是invalid
            // 直接异或，反而会把原来为0(invalid)的设置为1(valid)
            // 所以在异或前，先与一下
            ins_valid[prmiss_ftq_idx] <= ins_valid[prmiss_ftq_idx] ^
                (ins_valid[prmiss_ftq_idx] & prmiss_invalid);

            bpuPtr <= prmiss_ftq_idx_plus1;
            ifuPtr <= prmiss_ftq_idx_plus1;
            ifuWbPtr <= prmiss_ftq_idx_plus1;

            valid <= valid_after_prmiss;
            is_wb <= valid_after_prmiss;
/*
            if ((bpuPtr - 1) < prmiss_ftq_idx_plus1) begin
                valid[`FTQ_NUM-1 : prmiss_ftq_idx_plus1] <= '0;
                is_wb[`FTQ_NUM-1 : prmiss_ftq_idx_plus1] <= '0;

                valid[bpuPtr - 1 : 0] <= '0;
                is_wb[bpuPtr - 1 : 0] <= '0;
            end 
            else begin
                valid[bpuPtr - 1 : prmiss_ftq_idx_plus1] <= '0;
                is_wb[bpuPtr - 1 : prmiss_ftq_idx_plus1] <= '0;
            end
*/
        end
        else begin

            if (valid[bpuPtr] == 1'b0) begin

                startAddr[bpuPtr] <= pc;
                npc[bpuPtr] <= predict_npc;
                ghr[bpuPtr] <= bhr;
                prcond[bpuPtr] <= predict_cond;

                valid[bpuPtr] <= 1'b1;

                bpuPtr <= bpuPtr + 1;

                pc <= predict_npc;
            end
            else
                pc <= pc;

            if (icache_req) begin
                ifuPtr <= ifuPtr + 1;
            end

            if (icache_done) begin

                ins_valid[ifuWbPtr] <= insvalid;
                ins_type[ifuWbPtr] <= instype;
                is_wb[ifuWbPtr] <= 1'b1;

                ifuWbPtr <= ifuWbPtr + 1;
            end

            if (commit1) begin
                case(com_pc_offset1)
                    4'd0:ins_valid[com_ftq_idx1][0] <= '0;
                    4'd4:ins_valid[com_ftq_idx1][1] <= '0;
                    4'd8:ins_valid[com_ftq_idx1][2] <= '0;
                    4'd12:ins_valid[com_ftq_idx1][3] <= '0;
                endcase
            end

            if (commit2) begin
                case(com_pc_offset2)
                    4'd0:ins_valid[com_ftq_idx2][0] <= '0;
                    4'd4:ins_valid[com_ftq_idx2][1] <= '0;
                    4'd8:ins_valid[com_ftq_idx2][2] <= '0;
                    4'd12:ins_valid[com_ftq_idx2][3] <= '0;
                endcase
            end

            if (ins_valid[comPtr] == 4'b0000 && is_wb[comPtr] == 1'b1) begin

                is_wb[comPtr] <= '0; 
                valid[comPtr] <= '0;

                comPtr <= comPtr + 1;
            end
        end
    end
endmodule // fetch_target_queue
`default_nettype wire
