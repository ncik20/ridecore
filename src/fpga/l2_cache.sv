import cache_def::*;

`timescale 1 ns/ 1 ps
`default_nettype none

module l2_sync_ram #(
    parameter ADDR_WIDTH = 11,
    parameter DATA_WIDTH = 128,
    parameter DATA_DEPTH = 2048,
    parameter INIT_ZERO = 0
) (
    input  wire logic                  clk,
    input  wire logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0]      rdata,
    input  wire logic [ADDR_WIDTH-1:0] waddr,
    input  wire logic [DATA_WIDTH-1:0] wdata,
    input  wire logic                  we
);
    logic [DATA_WIDTH-1:0] mem [0:DATA_DEPTH-1];
    integer init_i;

    initial begin
        if (INIT_ZERO) begin
            for (init_i = 0; init_i < DATA_DEPTH; init_i = init_i + 1)
                mem[init_i] = {DATA_WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        rdata <= mem[raddr];
        if (we)
            mem[waddr] <= wdata;
    end
endmodule

module l2_cache_bank #(
    parameter BANK_ID = 0
) (
    input  wire logic    clk,
    input  wire logic    rst,

    input  wire logic    start,
    input  wire logic    start_is_i,
    input  wire logic [1:0]   start_rw,
    input  wire logic [31:0]  start_addr,
    input  wire logic [127:0] start_wdata,
    input  wire logic [15:0]  start_byteenable,
    output logic         busy,

    output logic         done,
    output logic         done_is_i,
    output logic [127:0] done_rdata,

    output logic         invalidate_valid,
    output logic [31:0]  invalidate_addr,

    output logic         lower_req_valid,
    output logic [1:0]   lower_req_rw,
    output logic [31:0]  lower_req_addr,
    output logic [127:0] lower_req_wdata,
    output logic [15:0]  lower_req_byteenable,
    input  wire logic    lower_req_accept,
    input  wire logic [127:0] lower_rsp_data,
    input  wire logic    lower_rsp_done
);
    localparam int SETS_PER_BANK = 2048;
    localparam int SET_BITS = 11;
    localparam int TAG_BITS = 15;
    localparam int META_WIDTH = TAG_BITS + 3;
    localparam logic [1:0] BANK_SEL = BANK_ID[1:0];

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOOKUP,
        ST_WB_REQ,
        ST_WB_WAIT,
        ST_FILL_REQ,
        ST_FILL_WAIT,
        ST_UPDATE
    } state_t;

    state_t state;

    logic         req_is_i;
    logic [1:0]   req_rw;
    logic [31:0]  req_addr;
    logic [127:0] req_wdata;
    logic [15:0]  req_byteenable;
    logic [SET_BITS-1:0] req_set;
    logic [TAG_BITS-1:0] req_tag;

    logic victim_way;
    logic [TAG_BITS-1:0] victim_tag;
    logic [127:0] victim_data;
    logic [127:0] fill_data;
    logic [15:0]  lfsr;

    logic [127:0] data0_read;
    logic [127:0] data1_read;
    logic [META_WIDTH-1:0] meta0_read;
    logic [META_WIDTH-1:0] meta1_read;
    logic [SET_BITS-1:0] ram_raddr;
    logic [SET_BITS-1:0] data0_waddr;
    logic [SET_BITS-1:0] data1_waddr;
    logic [SET_BITS-1:0] meta0_waddr;
    logic [SET_BITS-1:0] meta1_waddr;
    logic [127:0] data0_wdata;
    logic [127:0] data1_wdata;
    logic [META_WIDTH-1:0] meta0_wdata;
    logic [META_WIDTH-1:0] meta1_wdata;
    logic data0_we;
    logic data1_we;
    logic meta0_we;
    logic meta1_we;
    logic reset_clear_active;
    logic [SET_BITS-1:0] reset_clear_addr;
    logic rst_q;

    wire lookup_valid0 = meta0_read[TAG_BITS+2];
    wire lookup_dirty0 = meta0_read[TAG_BITS+1];
    wire lookup_l1i0   = meta0_read[TAG_BITS];
    wire [TAG_BITS-1:0] tag0_read = meta0_read[TAG_BITS-1:0];

    wire lookup_valid1 = meta1_read[TAG_BITS+2];
    wire lookup_dirty1 = meta1_read[TAG_BITS+1];
    wire lookup_l1i1   = meta1_read[TAG_BITS];
    wire [TAG_BITS-1:0] tag1_read = meta1_read[TAG_BITS-1:0];

    wire hit0 = lookup_valid0 && (tag0_read == req_tag);
    wire hit1 = lookup_valid1 && (tag1_read == req_tag);
    wire hit = hit0 || hit1;
    wire hit_way = hit1;
    wire rand_replace_way = lfsr[0];
    wire select_victim_way = !lookup_valid0 ? 1'b0 :
                             !lookup_valid1 ? 1'b1 : rand_replace_way;
    wire select_victim_valid = select_victim_way ? lookup_valid1 : lookup_valid0;
    wire select_victim_dirty = select_victim_way ? lookup_dirty1 : lookup_dirty0;
    wire select_victim_l1i = select_victim_way ? lookup_l1i1 : lookup_l1i0;
    wire [TAG_BITS-1:0] select_victim_tag = select_victim_way ? tag1_read : tag0_read;
    wire [127:0] select_victim_data = select_victim_way ? data1_read : data0_read;
    wire [31:0] victim_line_addr = line_addr(select_victim_tag, req_set);

    function automatic [127:0] merge_byteenable;
        input [127:0] old_data;
        input [127:0] new_data;
        input [15:0]  be;
        integer j;
        begin
            merge_byteenable = old_data;
            for (j = 0; j < 16; j = j + 1) begin
                if (be[j])
                    merge_byteenable[j*8 +: 8] = new_data[j*8 +: 8];
            end
        end
    endfunction

    function automatic [31:0] line_addr;
        input [TAG_BITS-1:0] tag;
        input [SET_BITS-1:0] set;
        begin
            line_addr = {tag, set, BANK_SEL, 4'b0000};
        end
    endfunction

    assign busy = (state != ST_IDLE) || reset_clear_active;

    assign ram_raddr = reset_clear_active ? reset_clear_addr :
                       start ? start_addr[16:6] : req_set;

    always_comb begin
        data0_we = 1'b0;
        data1_we = 1'b0;
        meta0_we = 1'b0;
        meta1_we = 1'b0;
        data0_waddr = req_set;
        data1_waddr = req_set;
        meta0_waddr = req_set;
        meta1_waddr = req_set;
        data0_wdata = 128'h0;
        data1_wdata = 128'h0;
        meta0_wdata = {1'b1, req_rw[1], req_is_i && !req_rw[1], req_tag};
        meta1_wdata = {1'b1, req_rw[1], req_is_i && !req_rw[1], req_tag};

        if (reset_clear_active) begin
            meta0_we = 1'b1;
            meta1_we = 1'b1;
            meta0_waddr = reset_clear_addr;
            meta1_waddr = reset_clear_addr;
            meta0_wdata = {META_WIDTH{1'b0}};
            meta1_wdata = {META_WIDTH{1'b0}};
        end else if (state == ST_LOOKUP && hit && req_rw[1]) begin
            if (hit_way) begin
                data1_we = 1'b1;
                meta1_we = 1'b1;
                data1_wdata = merge_byteenable(data1_read, req_wdata, req_byteenable);
                meta1_wdata = {1'b1, 1'b1, 1'b0, tag1_read};
            end else begin
                data0_we = 1'b1;
                meta0_we = 1'b1;
                data0_wdata = merge_byteenable(data0_read, req_wdata, req_byteenable);
                meta0_wdata = {1'b1, 1'b1, 1'b0, tag0_read};
            end
        end else if (state == ST_LOOKUP && hit && req_is_i && !req_rw[1]) begin
            if (hit_way) begin
                meta1_we = 1'b1;
                meta1_wdata = {1'b1, lookup_dirty1, 1'b1, tag1_read};
            end else begin
                meta0_we = 1'b1;
                meta0_wdata = {1'b1, lookup_dirty0, 1'b1, tag0_read};
            end
        end else if (state == ST_UPDATE) begin
            if (victim_way) begin
                data1_we = 1'b1;
                meta1_we = 1'b1;
                data1_wdata = req_rw[1] ? merge_byteenable(fill_data, req_wdata, req_byteenable) : fill_data;
            end else begin
                data0_we = 1'b1;
                meta0_we = 1'b1;
                data0_wdata = req_rw[1] ? merge_byteenable(fill_data, req_wdata, req_byteenable) : fill_data;
            end
        end
    end

    initial begin
        reset_clear_active = 1'b0;
        reset_clear_addr = {SET_BITS{1'b0}};
        rst_q = 1'b0;
    end

    always @(posedge clk) begin
        rst_q <= rst;
        if (rst && !rst_q) begin
            reset_clear_active <= 1'b1;
            reset_clear_addr <= {SET_BITS{1'b0}};
        end else if (reset_clear_active) begin
            reset_clear_addr <= reset_clear_addr + {{(SET_BITS-1){1'b0}}, 1'b1};
            if (reset_clear_addr == SETS_PER_BANK[SET_BITS-1:0] - {{(SET_BITS-1){1'b0}}, 1'b1})
                reset_clear_active <= 1'b0;
        end

        if (rst) begin
            state <= ST_IDLE;
            done <= 1'b0;
            done_is_i <= 1'b0;
            done_rdata <= 128'h0;
            invalidate_valid <= 1'b0;
            invalidate_addr <= 32'h0;
            lower_req_valid <= 1'b0;
            lower_req_rw <= 2'd0;
            lower_req_addr <= 32'h0;
            lower_req_wdata <= 128'h0;
            lower_req_byteenable <= 16'h0;
            lfsr <= 16'hACE1 ^ {14'h0, BANK_SEL};
        end else if (reset_clear_active) begin
            state <= ST_IDLE;
            done <= 1'b0;
            done_is_i <= 1'b0;
            done_rdata <= 128'h0;
            invalidate_valid <= 1'b0;
            invalidate_addr <= 32'h0;
            lower_req_valid <= 1'b0;
            lower_req_rw <= 2'd0;
            lower_req_addr <= 32'h0;
            lower_req_wdata <= 128'h0;
            lower_req_byteenable <= 16'h0;
        end else begin
            done <= 1'b0;
            invalidate_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    lower_req_valid <= 1'b0;
                    lower_req_rw <= 2'd0;
                    if (start) begin
                        req_is_i <= start_is_i;
                        req_rw <= start_rw;
                        req_addr <= {start_addr[31:4], 4'b0000};
                        req_wdata <= start_wdata;
                        req_byteenable <= start_byteenable;
                        req_set <= start_addr[16:6];
                        req_tag <= start_addr[31:17];
                        state <= ST_LOOKUP;
                    end
                end

                ST_LOOKUP: begin
                    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

                    if (hit) begin
                        done <= 1'b1;
                        done_is_i <= req_is_i;
                        done_rdata <= hit_way ? data1_read : data0_read;

                        if (req_rw[1]) begin
                            if (hit_way) begin
                                if (lookup_l1i1) begin
                                    invalidate_valid <= 1'b1;
                                    invalidate_addr <= req_addr;
                                end
                            end else begin
                                if (lookup_l1i0) begin
                                    invalidate_valid <= 1'b1;
                                    invalidate_addr <= req_addr;
                                end
                            end
                        end

                        state <= ST_IDLE;
                    end else begin
                        victim_way <= select_victim_way;
                        victim_tag <= select_victim_tag;
                        victim_data <= select_victim_data;

                        if (select_victim_valid && select_victim_l1i) begin
                            invalidate_valid <= 1'b1;
                            invalidate_addr <= victim_line_addr;
                        end

                        if (select_victim_valid && select_victim_dirty)
                            state <= ST_WB_REQ;
                        else
                            state <= ST_FILL_REQ;
                    end
                end

                ST_WB_REQ: begin
                    lower_req_valid <= 1'b1;
                    lower_req_rw <= 2'd2;
                    lower_req_addr <= line_addr(victim_tag, req_set);
                    lower_req_wdata <= victim_data;
                    lower_req_byteenable <= 16'hFFFF;
                    if (lower_req_accept) begin
                        lower_req_valid <= 1'b0;
                        state <= ST_WB_WAIT;
                    end
                end

                ST_WB_WAIT: begin
                    if (lower_rsp_done)
                        state <= ST_FILL_REQ;
                end

                ST_FILL_REQ: begin
                    lower_req_valid <= 1'b1;
                    lower_req_rw <= 2'd1;
                    lower_req_addr <= req_addr;
                    lower_req_wdata <= 128'h0;
                    lower_req_byteenable <= 16'hFFFF;
                    if (lower_req_accept) begin
                        lower_req_valid <= 1'b0;
                        state <= ST_FILL_WAIT;
                    end
                end

                ST_FILL_WAIT: begin
                    if (lower_rsp_done) begin
                        fill_data <= lower_rsp_data;
                        state <= ST_UPDATE;
                    end
                end

                ST_UPDATE: begin
                    done <= 1'b1;
                    done_is_i <= req_is_i;
                    done_rdata <= req_rw[1] ?
                        merge_byteenable(fill_data, req_wdata, req_byteenable) : fill_data;

                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    l2_sync_ram #(SET_BITS, 128, SETS_PER_BANK, 0) data_way0_ram (
        .clk(clk),
        .raddr(ram_raddr),
        .rdata(data0_read),
        .waddr(data0_waddr),
        .wdata(data0_wdata),
        .we(data0_we)
    );

    l2_sync_ram #(SET_BITS, 128, SETS_PER_BANK, 0) data_way1_ram (
        .clk(clk),
        .raddr(ram_raddr),
        .rdata(data1_read),
        .waddr(data1_waddr),
        .wdata(data1_wdata),
        .we(data1_we)
    );

    l2_sync_ram #(SET_BITS, META_WIDTH, SETS_PER_BANK, 1) meta_way0_ram (
        .clk(clk),
        .raddr(ram_raddr),
        .rdata(meta0_read),
        .waddr(meta0_waddr),
        .wdata(meta0_wdata),
        .we(meta0_we)
    );

    l2_sync_ram #(SET_BITS, META_WIDTH, SETS_PER_BANK, 1) meta_way1_ram (
        .clk(clk),
        .raddr(ram_raddr),
        .rdata(meta1_read),
        .waddr(meta1_waddr),
        .wdata(meta1_wdata),
        .we(meta1_we)
    );
endmodule

module l2_cache(
    input  wire logic    clk,
    input  wire logic    rst,

    input  wire logic [31:0]  i_req_addr,
    input  wire logic [127:0] i_req_data,
    input  wire logic [15:0]  i_req_byteenable,
    input  wire logic [1:0]   i_req_rw,
    output logic [127:0] i_rsp_data,
    output logic         i_rsp_done,

    input  wire logic [31:0]  d_req_addr,
    input  wire logic [127:0] d_req_data,
    input  wire logic [15:0]  d_req_byteenable,
    input  wire logic [1:0]   d_req_rw,
    output logic [127:0] d_rsp_data,
    output logic         d_rsp_done,

    output logic         i_invalidate_valid,
    output logic [31:0]  i_invalidate_addr,

    output logic [31:0]  mem_req_addr,
    output logic [127:0] mem_req_data,
    output logic [15:0]  mem_req_byteenable,
    output logic [1:0]   mem_req_rw,
    input  wire logic [127:0] mem_rsp_data,
    input  wire logic         mem_rsp_done
);
    logic         i_pending;
    logic         i_outstanding;
    logic [31:0]  i_pending_addr;
    logic [127:0] i_pending_data;
    logic [15:0]  i_pending_byteenable;
    logic [1:0]   i_pending_rw;
    logic [31:0]  i_outstanding_addr;
    logic [1:0]   i_outstanding_rw;

    logic         d_pending;
    logic         d_outstanding;
    logic [31:0]  d_pending_addr;
    logic [127:0] d_pending_data;
    logic [15:0]  d_pending_byteenable;
    logic [1:0]   d_pending_rw;
    logic [31:0]  d_outstanding_addr;
    logic [1:0]   d_outstanding_rw;

    logic [3:0] bank_busy;
    logic [3:0] bank_done;
    logic [3:0] bank_done_is_i;
    logic [127:0] bank_done_rdata [0:3];
    logic [3:0] bank_inv_valid;
    logic [31:0] bank_inv_addr [0:3];

    logic [3:0] lower_req_valid;
    logic [1:0] lower_req_rw [0:3];
    logic [31:0] lower_req_addr [0:3];
    logic [127:0] lower_req_wdata [0:3];
    logic [15:0] lower_req_byteenable [0:3];
    logic [3:0] lower_req_accept;
    logic [3:0] lower_rsp_done;

    logic [3:0] start_i_bank;
    logic [3:0] start_d_bank;
    logic [1:0] i_bank_sel;
    logic [1:0] d_bank_sel;
    logic i_can_start;
    logic d_can_start;

    assign i_bank_sel = i_pending_addr[5:4];
    assign d_bank_sel = d_pending_addr[5:4];
    assign d_can_start = d_pending && !bank_busy[d_bank_sel];
    assign i_can_start = i_pending && !bank_busy[i_bank_sel] &&
                          !(d_can_start && d_bank_sel == i_bank_sel);

    always_comb begin
        start_i_bank = 4'b0000;
        start_d_bank = 4'b0000;
        if (i_can_start)
            start_i_bank[i_bank_sel] = 1'b1;
        if (d_can_start)
            start_d_bank[d_bank_sel] = 1'b1;
    end

    genvar b;
    generate
        for (b = 0; b < 4; b = b + 1) begin : gen_banks
            l2_cache_bank #(.BANK_ID(b)) bank (
                .clk(clk),
                .rst(rst),
                .start(start_i_bank[b] | start_d_bank[b]),
                .start_is_i(start_i_bank[b]),
                .start_rw(start_i_bank[b] ? i_pending_rw : d_pending_rw),
                .start_addr(start_i_bank[b] ? i_pending_addr : d_pending_addr),
                .start_wdata(start_i_bank[b] ? i_pending_data : d_pending_data),
                .start_byteenable(start_i_bank[b] ? i_pending_byteenable : d_pending_byteenable),
                .busy(bank_busy[b]),
                .done(bank_done[b]),
                .done_is_i(bank_done_is_i[b]),
                .done_rdata(bank_done_rdata[b]),
                .invalidate_valid(bank_inv_valid[b]),
                .invalidate_addr(bank_inv_addr[b]),
                .lower_req_valid(lower_req_valid[b]),
                .lower_req_rw(lower_req_rw[b]),
                .lower_req_addr(lower_req_addr[b]),
                .lower_req_wdata(lower_req_wdata[b]),
                .lower_req_byteenable(lower_req_byteenable[b]),
                .lower_req_accept(lower_req_accept[b]),
                .lower_rsp_data(mem_rsp_data),
                .lower_rsp_done(lower_rsp_done[b])
            );
        end
    endgenerate

    logic mem_busy;
    logic [1:0] mem_bank;
    logic [1:0] next_mem_bank;
    logic       accept_any;

    always_comb begin
        lower_req_accept = 4'b0000;
        mem_req_rw = 2'd0;
        mem_req_addr = 32'h0;
        mem_req_data = 128'h0;
        mem_req_byteenable = 16'h0;
        next_mem_bank = 2'd0;
        accept_any = 1'b0;

        if (!mem_busy) begin
            if (lower_req_valid[0]) begin
                lower_req_accept[0] = 1'b1;
                mem_req_rw = lower_req_rw[0];
                mem_req_addr = lower_req_addr[0];
                mem_req_data = lower_req_wdata[0];
                mem_req_byteenable = lower_req_byteenable[0];
                next_mem_bank = 2'd0;
                accept_any = 1'b1;
            end else if (lower_req_valid[1]) begin
                lower_req_accept[1] = 1'b1;
                mem_req_rw = lower_req_rw[1];
                mem_req_addr = lower_req_addr[1];
                mem_req_data = lower_req_wdata[1];
                mem_req_byteenable = lower_req_byteenable[1];
                next_mem_bank = 2'd1;
                accept_any = 1'b1;
            end else if (lower_req_valid[2]) begin
                lower_req_accept[2] = 1'b1;
                mem_req_rw = lower_req_rw[2];
                mem_req_addr = lower_req_addr[2];
                mem_req_data = lower_req_wdata[2];
                mem_req_byteenable = lower_req_byteenable[2];
                next_mem_bank = 2'd2;
                accept_any = 1'b1;
            end else if (lower_req_valid[3]) begin
                lower_req_accept[3] = 1'b1;
                mem_req_rw = lower_req_rw[3];
                mem_req_addr = lower_req_addr[3];
                mem_req_data = lower_req_wdata[3];
                mem_req_byteenable = lower_req_byteenable[3];
                next_mem_bank = 2'd3;
                accept_any = 1'b1;
            end
        end
    end

    always_comb begin
        lower_rsp_done = 4'b0000;
        if (mem_rsp_done)
            lower_rsp_done[mem_bank] = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            i_pending <= 1'b0;
            i_outstanding <= 1'b0;
            d_pending <= 1'b0;
            d_outstanding <= 1'b0;
            mem_busy <= 1'b0;
            mem_bank <= 2'd0;
        end else begin
            if (i_rsp_done)
                i_outstanding <= 1'b0;
            if (d_rsp_done)
                d_outstanding <= 1'b0;

            if (i_req_rw != 2'd0 && !i_pending &&
                !(i_outstanding && i_outstanding_addr == i_req_addr && i_outstanding_rw == i_req_rw)) begin
                i_pending <= 1'b1;
                i_pending_addr <= i_req_addr;
                i_pending_data <= i_req_data;
                i_pending_byteenable <= i_req_byteenable;
                i_pending_rw <= i_req_rw;
            end
            if (d_req_rw != 2'd0 && !d_pending &&
                !(d_outstanding && d_outstanding_addr == d_req_addr && d_outstanding_rw == d_req_rw)) begin
                d_pending <= 1'b1;
                d_pending_addr <= d_req_addr;
                d_pending_data <= d_req_data;
                d_pending_byteenable <= d_req_byteenable;
                d_pending_rw <= d_req_rw;
            end

            if (i_can_start) begin
                i_pending <= 1'b0;
                i_outstanding <= 1'b1;
                i_outstanding_addr <= i_pending_addr;
                i_outstanding_rw <= i_pending_rw;
            end
            if (d_can_start) begin
                d_pending <= 1'b0;
                d_outstanding <= 1'b1;
                d_outstanding_addr <= d_pending_addr;
                d_outstanding_rw <= d_pending_rw;
            end

            if (accept_any) begin
                mem_busy <= 1'b1;
                mem_bank <= next_mem_bank;
            end else if (mem_rsp_done) begin
                mem_busy <= 1'b0;
            end
        end
    end

    always_comb begin
        i_rsp_done = 1'b0;
        d_rsp_done = 1'b0;
        i_rsp_data = 128'h0;
        d_rsp_data = 128'h0;

        if (bank_done[0] && bank_done_is_i[0]) begin
            i_rsp_done = 1'b1;
            i_rsp_data = bank_done_rdata[0];
        end else if (bank_done[1] && bank_done_is_i[1]) begin
            i_rsp_done = 1'b1;
            i_rsp_data = bank_done_rdata[1];
        end else if (bank_done[2] && bank_done_is_i[2]) begin
            i_rsp_done = 1'b1;
            i_rsp_data = bank_done_rdata[2];
        end else if (bank_done[3] && bank_done_is_i[3]) begin
            i_rsp_done = 1'b1;
            i_rsp_data = bank_done_rdata[3];
        end

        if (bank_done[0] && !bank_done_is_i[0]) begin
            d_rsp_done = 1'b1;
            d_rsp_data = bank_done_rdata[0];
        end else if (bank_done[1] && !bank_done_is_i[1]) begin
            d_rsp_done = 1'b1;
            d_rsp_data = bank_done_rdata[1];
        end else if (bank_done[2] && !bank_done_is_i[2]) begin
            d_rsp_done = 1'b1;
            d_rsp_data = bank_done_rdata[2];
        end else if (bank_done[3] && !bank_done_is_i[3]) begin
            d_rsp_done = 1'b1;
            d_rsp_data = bank_done_rdata[3];
        end

        i_invalidate_valid = 1'b0;
        i_invalidate_addr = 32'h0;
        if (bank_inv_valid[0]) begin
            i_invalidate_valid = 1'b1;
            i_invalidate_addr = bank_inv_addr[0];
        end else if (bank_inv_valid[1]) begin
            i_invalidate_valid = 1'b1;
            i_invalidate_addr = bank_inv_addr[1];
        end else if (bank_inv_valid[2]) begin
            i_invalidate_valid = 1'b1;
            i_invalidate_addr = bank_inv_addr[2];
        end else if (bank_inv_valid[3]) begin
            i_invalidate_valid = 1'b1;
            i_invalidate_addr = bank_inv_addr[3];
        end
    end
endmodule

`default_nettype wire
