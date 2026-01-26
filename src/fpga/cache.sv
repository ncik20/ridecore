import cache_def::*;
/*cache:data memory, single port, 1024 blocks*/
module dm_cache_data_pl(
        input   logic               clk,
		input   cache_req_type      data_req1,      //data request/command, e.g. RW, valid
		input   cache_req_type      data_req2,      //
		input   logic [127:0]       data_write2,    //write port(128-bit line)
		output  logic [127:0]       data_read1      //read port
		); 	//
/*		input  logic [8:0]			index,
		input  logic 				we,
		input  logic [127:0]		data_write,
		output logic [127:0]		data_read);*/

	//timeunit 1ns; timeprecision 1ps;

	reg [127:0] data_mem[0:511];

/*	initial begin
		for (int i=0; i<512; i++)
		  data_mem[i] = '0;
	end*/

	//assign data_read = data_mem[index];

	always_ff @(posedge(clk)) begin

        if (data_req1.en) begin
            if (data_req2.en && data_req1.index == data_req2.index)
                data_read1 <= data_write2;
            else
                data_read1 <= data_mem[data_req1.index];
        end 
        else data_read1 <= 'z;

        if (data_req2.en) begin
            data_mem[data_req2.index] <= data_write2;
        end
	end
endmodule

/*cache:tag memory, single port, 1024 blocks*/
module dm_cache_tag_pl(
        input   logic               clk,
        input   logic               rst,
		input   cache_req_type      tag_req1,		//tag request/command, e.g. RW, valid
		input   cache_req_type      tag_req2,		//
		input   cache_tag_type      tag_write2,		//write port
		output  cache_tag_type      tag_read1  	    //read port
		);
/*		input  logic [8:0]				index,
		input  logic 					we,
		input  logic 					tag_write_valid,
		input  logic 					tag_write_dirty,
		input  logic [TAGMSB:TAGLSB]	tag_write,
		output logic 					tag_read_valid,
		output logic 					tag_read_dirty,
		output logic [TAGMSB:TAGLSB]	tag_read);

	//timeunit 1ns; timeprecision 1ps;


	initial begin
		for (int i=0; i<512; i++) begin
		  tag_mem_valid[i] = '0;
		  tag_mem_dirty[i] = '0;
		  tag_mem[i] = '0;
		end
	end
*/

	logic tag_mem_valid[0:511];
	logic tag_mem_dirty[0:511];
	logic [TAGMSB:TAGLSB] tag_mem[0:511];
    // cache_tag_type tag_mem[0:511];

    integer i;
	always_ff @(posedge(clk)) begin
        if (rst) begin
		    for (int i=0; i<512; i++) begin
		        tag_mem_valid[i] <= '0;
                // tag_mem[i] <= '0;
		    end
        end
        else begin

            tag_read1.valid <= tag_mem_valid[tag_req1.index];
            tag_read1.dirty <= tag_mem_dirty[tag_req1.index];
            tag_read1.tag <= tag_mem[tag_req1.index];
            if (tag_req2.en) begin
                tag_mem_valid[tag_req2.index] <= tag_write2.valid;
                tag_mem_dirty[tag_req2.index] <= tag_write2.dirty;
                tag_mem[tag_req2.index] <= tag_write2.tag;
            end
/*
            if (tag_req1.en) begin
                if (tag_req2.en && tag_req1.index == tag_req2.index)
                    tag_read1 <= tag_write2;
                else
                    tag_read1 <= tag_mem[tag_req1.index];
            end
            else tag_read1 <= 'z;

            if (tag_req2.en) begin
                tag_mem[tag_req2.index] <= tag_write2;
            end
*/
        end
	end
endmodule


module dm_cache_pl(input logic clk, input logic rst,
		input logic [31:0]cpu_req_addr,			//32-bit request addr
		input logic [31:0]cpu_req_data,			//32-bit request data(used when write)
		input logic [2:0]cpu_req_funct3,		//funct3        
		input logic cpu_req_rw,					//request type : 0 = read, 1 = write
		input logic cpu_req_valid,				//request is valid
        input logic cpu_req_kill,

		input logic [127:0] mem_data_data,		//128-bit read back data
		input logic mem_data_ready,				//data is ready

		output logic [31:0]mem_req_addr,		//request byte addr
		output logic [127:0]mem_req_data,		//128-bit reguest data(used when write)
        output logic [15:0]mem_req_byteenable,
		output logic [1:0]mem_req_rw,			//request type : 0 = no request, 1 = read, 2 = write
		output logic mem_req_valid,				//request is valid

        output logic [31:0]cpu_res_pc,
		output logic [127:0]cpu_res_data,		//128-bit data
		output logic [1:0]cpu_res_ready,		//result : 0 = not ready, 1 = read ready, 2 = write ready
        output logic busy
	);

	//timeunit 1ns; timeprecision 1ps;

    //reg	        pending_rw_flag;
    //reg [31:0]  pending_req_addr;
    //wire rw_flag = busy ? pending_rw_flag : cpu_req_rw;
    //wire [31:0] req_addr = busy ? pending_req_addr : cpu_req_addr;
    logic               io_write_byteenable;

    logic               icache_done_at_stage2;
    logic               icache_done_at_stage3;

    logic               accept_req;
    logic               req_kill_latch;
    logic               cache_miss;
    logic [1:0]         mem_access;
    logic               write_back_done;

    logic [31:0]        req_addr_stage1;
    logic [31:0]        req_data_stage1;
    logic [2:0]         req_funct3_stage1;
    logic               req_rw_stage1;
    logic               req_valid_stage1;


	/*interface signals to tag memory*/
	cache_tag_type  tag_read1;					//tag read result
	cache_tag_type  tag_write1;					//tag write data
	cache_req_type  tag_req1;					//tag request

	cache_tag_type  tag_read2;					//tag read result
	cache_tag_type  tag_write2;					//tag write data
	cache_req_type  tag_req2;					//tag request

	/*interface signals to cache data memory*/

	logic [127:0] data_read1;					//cache line read data
	logic [127:0] data_write1;				    //cache line write data
	cache_req_type  data_req1;					//data req

	logic [127:0] data_read2;					//cache line read data
	logic [127:0] data_write2;				    //cache line write data
	cache_req_type  data_req2;					//data req

	/*temporary variable for cache controller result*/
	cpu_result_type v_cpu_res;

	/*temporary variable for memory controller request*/
	mem_req_type v_mem_req;

/*	assign mem_req = v_mem_req;					//connect to output ports
	assign cpu_res = v_cpu_res;*/

    assign busy = cache_miss | (|mem_access) | tag_req2.en;

	assign mem_req_addr = v_mem_req.addr;
	assign mem_req_data = v_mem_req.data;
    assign mem_req_byteenable = v_mem_req.byteenable;
	assign mem_req_rw = v_mem_req.rw;
	assign mem_req_valid = v_mem_req.valid;

	assign cpu_res_data = v_cpu_res.data;
	assign cpu_res_ready = v_cpu_res.ready;

    assign io_write_byteenable = (cpu_req_funct3 == 3'b000) ? 16'h0001 :
        (cpu_req_funct3 == 3'b001) ? 16'h0003 : 16'h000F;

    function automatic [31:0] store_b;
        input [1:0]     addr;
        input [31:0]    org_word;
        input [7:0]     update_data;

	    case(addr)
			2'b00:return {org_word[31-:24], update_data};

			2'b01:return {org_word[31-:16], update_data, org_word[7:0]};

			2'b10:return {org_word[31-:8], update_data, org_word[15:0]};

			2'b11:return {update_data, org_word[23:0]};
		endcase
    endfunction : store_b

    function automatic [31:0] store_h;
        input [1:0]     addr;
        input [31:0]    org_word;
        input [15:0]    update_data;

	    case(addr)
			2'b00:return {org_word[31-:16], update_data};

			2'b01:return '0; // TODO:go trap

			2'b10:return {update_data, org_word[15:0]};

			2'b11:return '0; // TODO:go trap
		endcase
    endfunction : store_h

    function automatic [127:0] get_data_write;
        input [3:0]     req_addr;
        input [2:0]     req_funct3;
        input [31:0]    req_data;
        input [127:0]   org_data;

        logic [127:0]   data_write;

        data_write = org_data;

        case(req_addr[3:2])
            2'b00:data_write[31-: 32] = (req_funct3 == 3'b000) ?
              store_b(req_addr[1:0], data_write[31-: 32], req_data[7:0]) :
              (req_funct3 == 3'b001) ?
              store_h(req_addr[1:0], data_write[31-: 32], req_data[15:0]) :
              req_data;

            2'b01:data_write[63-: 32] = (req_funct3 == 3'b000) ?
              store_b(req_addr[1:0], data_write[63-: 32], req_data[7:0]) :
              (req_funct3 == 3'b001) ?
              store_h(req_addr[1:0], data_write[63-: 32], req_data[15:0]) :
              req_data;

            2'b10:data_write[95-: 32] = (req_funct3 == 3'b000) ?
              store_b(req_addr[1:0], data_write[95-: 32], req_data[7:0]) :
              (req_funct3 == 3'b001) ?
              store_h(req_addr[1:0], data_write[95-: 32], req_data[15:0]) :
              req_data;

            2'b11:data_write[127-:32] = (req_funct3 == 3'b000) ?
              store_b(req_addr[1:0], data_write[127-: 32], req_data[7:0]) :
              (req_funct3 == 3'b001) ?
              store_h(req_addr[1:0], data_write[127-: 32], req_data[15:0]) :
              req_data;
        endcase

        return data_write;

    endfunction : get_data_write

    assign accept_req = cpu_req_valid && ~cpu_req_kill; //&& ((|v_cpu_res.ready) || ~busy);

	always_ff @(posedge(clk)) begin
        if (rst) begin
            
            req_kill_latch <= '0;
            mem_access <= '0;
            write_back_done <= '0;

            req_addr_stage1 <= '0;
            req_data_stage1 <= '0;
            req_funct3_stage1 <= '0;
            req_rw_stage1 <= '0;
            req_valid_stage1 <= '0;

        end
        else begin
            if (accept_req) begin
                req_addr_stage1 <= cpu_req_addr;
                req_data_stage1 <= cpu_req_data;
                req_funct3_stage1 <= cpu_req_funct3;
                req_rw_stage1 <= cpu_req_rw;
                req_valid_stage1 <= cpu_req_valid;
            end
            else if (cpu_req_kill || ((|v_cpu_res.ready) && ~cpu_req_valid)) begin
                req_addr_stage1 <= '0;
                req_data_stage1 <= '0;
                req_funct3_stage1 <= '0;
                req_rw_stage1 <= '0;
                req_valid_stage1 <= '0;
            end

            if (|mem_access) begin
                if (mem_data_ready) begin
                    if (mem_access == 2'd1) begin
                        mem_access <= '0;
                    end
                    else begin
                        mem_access <= 2'd1;
                        write_back_done <= 1'b1;
                    end

                    req_kill_latch <= '0;
                end
                else begin
                    write_back_done <= '0;

                    req_kill_latch <= cpu_req_kill;
                end
            end
            else if (cache_miss) mem_access <= v_mem_req.rw;
        end
	end

    // stage1
	always_comb begin
		/*read tag by default*/
		tag_req1.we = '0;
		/*direct map index for tag*/
		tag_req1.index = cpu_req_addr[12:4];
		tag_req1.en = '0;

		/*read current cache line by default*/
		data_req1.we = '0;
		/*direct map index for cache data*/
		data_req1.index = cpu_req_addr[12:4];
		data_req1.en = '0;

        // enable tag1, data1 access if have cache req
        // if (~mem_access && ~cpu_req_kill && cpu_req_valid) begin
        // bram不支持读优先(读写同时发生，读出写入的数据)
        // 所以有写发生的时候不能读
        if (accept_req) begin
		    tag_req1.en = 1'b1;
		    data_req1.en = 1'b1;
        end
    end

    // stage2,3
	always_comb begin

        icache_done_at_stage2 = '0;
        icache_done_at_stage3 = '0;

        cache_miss = '0;

		tag_req2.we = 1'b1;
		tag_req2.index = req_addr_stage1[12:4];
        tag_req2.en = '0;

		/*no change in tag*/
		tag_write2.tag = req_addr_stage1[TAGMSB:TAGLSB];
		tag_write2.valid = 1'b1;
		/*cache line is dirty if write*/
		tag_write2.dirty = req_rw_stage1;

        data_req2.we = 1'b1;
		data_req2.index = req_addr_stage1[12:4];
        data_req2.en = '0;

	    /*modify correct word(32-bit) based on address*/
		data_write2 = get_data_write(req_addr_stage1[3:0], req_funct3_stage1,
            req_data_stage1, data_read1);

        cpu_res_pc = req_addr_stage1;
        v_cpu_res.data = data_read1;
        v_cpu_res.ready = '0;

		/*memory request address(sampled from CPU request)*/
		v_mem_req.addr = req_addr_stage1;
		/*memory request data(used in write)*/
		v_mem_req.data = data_read1;
        v_mem_req.byteenable = 16'hFFFF;
		v_mem_req.rw = '0;
		v_mem_req.valid = '0;

        // if (~mem_access && ~cpu_req_kill && req_valid_stage1) begin
        if (~|mem_access && ~cpu_req_kill && req_valid_stage1) begin
		    /*cache hit (tag match and cache entry is valid)*/
		    if (req_addr_stage1[TAGMSB:TAGLSB] == tag_read1.tag && tag_read1.valid) begin
			    /*write hit*/
			    if (req_rw_stage1) begin
				    /*read/modify cache line*/
				    tag_req2.en = 1'b1;
                    data_req2.en = 1'b1;

	                v_cpu_res.ready = 2'd2;
	            end else begin 
	                v_cpu_res.ready = 2'd1;
                    icache_done_at_stage2 = 1'b1;
	            end
	        end
	        /*cache miss*/
	        else begin

	            cache_miss = 1'b1;

				/*compulsory miss or miss with clean block*/
	            if (tag_read1.valid == 1'b0 || tag_read1.dirty == 1'b0) begin
	                v_mem_req.rw = 2'd1;
	            end
	            //tag_read.valid == 1'b1 && tag_read.dirty == 1'b1
				/*miss with dirty line*/
	            else begin
					/*write back address*/
					v_mem_req.addr = {tag_read1.tag, req_addr_stage1[TAGLSB-1:0]};
		            /*memory request data(used in write)*/
					v_mem_req.rw = 2'd2;
				end

				/*generate memory request on miss*/
				v_mem_req.valid = 1'b1;

				/*generate new tag*/
                // 等到memdata回来后同时写，避免此cycle同时读取到写入的内容
                //tag_req2.en = 1'b1;
	        end
        end

        // stage3

        // write_back结束后下一个cycle，再发起allocate请求
        if (write_back_done) begin
            v_mem_req.rw = 2'd1;
            v_mem_req.valid = 1'b1;
        end

        if (mem_data_ready && mem_access == 2'd1) begin

            v_cpu_res.data = mem_data_data;

            if (req_rw_stage1) begin
                /*modify correct word(32-bit) based on address*/
                data_write2 = get_data_write(req_addr_stage1[3:0], req_funct3_stage1,
                    req_data_stage1, mem_data_data);

                v_cpu_res.ready = 2'd2;
            end else begin 
                data_write2 = mem_data_data;
                if (~cpu_req_kill && ~req_kill_latch) v_cpu_res.ready = 2'd1;
                icache_done_at_stage3 = 1'b1;
            end

            /*read/modify cache line*/
            tag_req2.en = 1'b1;
            data_req2.en = 1'b1;
        end
    end

	/*connect cache tag/data memory*/
	dm_cache_tag_pl ctag(
		.clk                (clk),
        .rst                (rst),
		.tag_req1           (tag_req1),
		.tag_req2           (tag_req2),
		.tag_write2         (tag_write2),
		.tag_read1          (tag_read1)
		);

    ram_sync_1r1w #(9, 128, 512) cdata(
		.clk            (clk),
        .raddr1         (data_req1.index),
        .rdata1         (data_read1),
        .waddr          (data_req2.index),
        .wdata          (data_write2),
        .we             (data_req2.en)
		);
/*
	dm_cache_data_pl cdata(
		.clk            (clk),
		.data_req1      (data_req1),
		.data_req2      (data_req2),
		.data_write2    (data_write2),
		.data_read1     (data_read1)
		);
*/

/*
	dm_cache_tag ctag(
		.clk                (clk),
        .rst                (rst),
		.index1             (tag_req1.index),
		.we1                (tag_req1.we),
		.index2             (tag_req2.index),
		.we2                (tag_req2.we),
		.tag_write_valid    (tag_write.valid),
		.tag_write_dirty    (tag_write.dirty),
		.tag_write          (tag_write.tag),
		.tag_read_valid     (tag_read.valid),
		.tag_read_dirty     (tag_read.dirty),
		.tag_read           (tag_read.tag)
		);
	dm_cache_data cdata(
		.clk        (clk),
		.index1     (data_req1.index),
		.we1        (data_req1.we),
		.index2     (data_req2.index),
		.we2        (data_req2.we),
		.data_write (data_write),
		.data_read  (data_read)
		);*/
endmodule
