import cache_def::*;
/*cache:data memory, single port, 1024 blocks*/
module dm_cache_data(input logic clk,
/*		input cache_req_type data_req,		//data request/command, e.g. RW, valid
		input cache_data_type data_write, 	//write port(128-bit line)
		output cache_data_type data_read); 	//read port*/
		input  logic [8:0]			index,
		input  logic 				we,
		input  logic [127:0]		data_write,
		output logic [127:0]		data_read);

	//timeunit 1ns; timeprecision 1ps;

	logic [127:0] data_mem[0:511];

/*	initial begin
		for (int i=0; i<512; i++)
		  data_mem[i] = '0;
	end*/

	//assign data_read = data_mem[index];

	always_ff @(posedge(clk)) begin
        if (we) begin
          data_read = data_write;
		  data_mem[index] <= data_write;
        end else data_read = data_mem[index];
	end
endmodule

/*cache:tag memory, single port, 1024 blocks*/
module dm_cache_tag(input logic clk,			//write clock
/*		input cache_req_type tag_req,		//tag request/command, e.g. RW, valid
		input cache_tag_type tag_write,		//write port
		output cache_tag_type tag_read);	//read port*/
        input  logic                    rst,
		input  logic [8:0]				index,
		input  logic 					we,
		input  logic 					tag_write_valid,
		input  logic 					tag_write_dirty,
		input  logic [TAGMSB:TAGLSB]	tag_write,
		output logic 					tag_read_valid,
		output logic 					tag_read_dirty,
		output logic [TAGMSB:TAGLSB]	tag_read);

	//timeunit 1ns; timeprecision 1ps;

	logic tag_mem_valid[0:511];
	logic tag_mem_dirty[0:511];
	logic [TAGMSB:TAGLSB] tag_mem[0:511];

	//cache_tag_type tag_mem[0:511];

/*	initial begin
		for (int i=0; i<512; i++) begin
		  tag_mem_valid[i] = '0;
		  tag_mem_dirty[i] = '0;
		  tag_mem[i] = '0;
		end
	end*/

    integer i;
	always_ff @(posedge(clk)) begin
        if (rst) begin
		    for (int i=0; i<512; i++) begin
		        tag_mem_valid[i] = '0;
		    end            
        end
		if (we) begin
		  tag_mem_valid[index] <= tag_write_valid;
		  tag_mem_dirty[index] <= tag_write_dirty;
		  tag_mem[index] <= tag_write;
	      tag_read_valid = tag_write_valid;
	      tag_read_dirty = tag_write_dirty;
	      tag_read = tag_write;
        end else begin
	      tag_read_valid = tag_mem_valid[index];
	      tag_read_dirty = tag_mem_dirty[index];
	      tag_read = tag_mem[index];
        end
	end
endmodule

/*cache finite state machine*/
/*module dm_cache_fsm(input bit clk, input bit rst,
		input cpu_req_type cpu_req,			//CPU request input (CPU->cache)
		input mem_data_type mem_data,		//memory response (memory->cache)
		output mem_req_type mem_req,		//memory reguest (cache->memory)
		output cpu_result_type cpu_res		//cache result (cache->CPU)
	);*/
/*   cache icache(
            .CLK(~clk),
            .RST(~reset_x),

            .addr_(pc),
            .rw_flag_(rw_flag_),

            .mem_read_data(mdata),
            .mem_done(mem_done)

            .mem_addr(maddr),
            .mem_rw_flag(mem_rw_flag),

            .read_data(idata),
            .busy(icache_busy),
            .done(icache_done)
      );*/
module dm_cache_fsm(input logic clk, input logic rst,
		input logic [31:0]cpu_req_addr,			//32-bit request addr
		input logic [31:0]cpu_req_data,			//32-bit request data(used when write)
		input logic [2:0]cpu_req_funct3,		//funct3        
		input logic cpu_req_rw,					//request type : 0 = read, 1 = write
		input logic cpu_req_valid,				//request is valid

		input logic [127:0] mem_data_data,		//128-bit read back data
		input logic mem_data_ready,				//data is ready

		output logic [31:0]mem_req_addr,		//request byte addr
		output logic [127:0]mem_req_data,		//128-bit reguest data(used when write)
        output logic [15:0]mem_req_byteenable,
		output logic [1:0]mem_req_rw,			//request type : 0 = no request, 1 = read, 2 = write
		output logic mem_req_valid,				//request is valid

		output logic [127:0]cpu_res_data,		//128-bit data
		output logic [1:0]cpu_res_ready,		//result : 0 = not ready, 1 = read ready, 2 = write ready
        output logic busy
	);

	//timeunit 1ns; timeprecision 1ps;

    reg	        pending_rw_flag;
    reg [31:0]  pending_req_addr;
    wire rw_flag = busy ? pending_rw_flag : cpu_req_rw;
    wire [31:0] req_addr = busy ? pending_req_addr : cpu_req_addr;
    wire io_write_byteenable;

	/*write clock*/
	typedef enum {idle, compare_tag, allocate, write_back, write_direct, read_direct} cache_state_type;

	/*FSM state register*/
	cache_state_type next_state, rstate;

	/*interface signals to tag memory*/
	cache_tag_type tag_read;						//tag read result
	cache_tag_type tag_write;					//tag write data
	cache_req_type tag_req;						//tag request

	/*interface signals to cache data memory*/

	cache_data_type data_read;					//cache line read data
	cache_data_type data_write;					//cache line write data
	cache_req_type data_req;						//data req

	/*temporary variable for cache controller result*/
	cpu_result_type v_cpu_res;

	/*temporary variable for memory controller request*/
	mem_req_type v_mem_req;

/*	assign mem_req = v_mem_req;					//connect to output ports
	assign cpu_res = v_cpu_res;*/

	assign mem_req_addr = v_mem_req.addr;
	assign mem_req_data = v_mem_req.data;
    assign mem_req_byteenable = v_mem_req.byteenable;
	assign mem_req_rw = v_mem_req.rw;
	assign mem_req_valid = v_mem_req.valid;

	assign cpu_res_data = v_cpu_res.data;
	assign cpu_res_ready = v_cpu_res.ready;

    assign io_write_byteenable = (cpu_req_funct3 == 3'b000) ? 16'h0001 :
        (cpu_req_funct3 == 3'b001) ? 16'h0003 : 16'h000F;

	always_comb begin
		/*--------------------default values for all signals--------------------*/
		/*no state change by default*/
        next_state = rstate;
		v_cpu_res = '{0, 0}; tag_write = '{0, 0, 0};

		/*read tag by default*/
		tag_req.we = '0;
		/*direct map index for tag*/
		tag_req.index = req_addr[12:4];

		/*read current cache line by default*/
		data_req.we = '0;
		/*direct map index for cache data*/
		data_req.index = req_addr[12:4];

		/*modify correct word(32-bit) based on address*/
		data_write = data_read;
		case(req_addr[3:2])
			2'b00:data_write[31-: 32] = (cpu_req_funct3 == 3'b000) ?
                {data_write[31-:24], cpu_req_data[7:0]} : (cpu_req_funct3 == 3'b001) ?
                {data_write[31-:16], cpu_req_data[15:0]} : cpu_req_data;

			2'b01:data_write[63-: 32] = (cpu_req_funct3 == 3'b000) ?
                {data_write[63-:24], cpu_req_data[7:0]} : (cpu_req_funct3 == 3'b001) ?
                {data_write[63-:16], cpu_req_data[15:0]} : cpu_req_data;

			2'b10:data_write[95-: 32] = (cpu_req_funct3 == 3'b000) ?
                {data_write[95-:24], cpu_req_data[7:0]} : (cpu_req_funct3 == 3'b001) ?
                {data_write[95-:16], cpu_req_data[15:0]} : cpu_req_data;

			2'b11:data_write[127-:32] = (cpu_req_funct3 == 3'b000) ?
                {data_write[127-:24], cpu_req_data[7:0]} : (cpu_req_funct3 == 3'b001) ?
                {data_write[127-:16], cpu_req_data[15:0]} : cpu_req_data;
		endcase

        v_cpu_res.data = data_read;
		/*read out correct word(32-bit) from cache (to CPU)
		case(req_addr[3:2])
			2'b00:v_cpu_res.data = data_read[31-: 32];
			2'b01:v_cpu_res.data = data_read[63-: 32];
			2'b10:v_cpu_res.data = data_read[95-: 32];
			2'b11:v_cpu_res.data = data_read[127-:32];
		endcase*/

		/*memory request address(sampled from CPU request)*/
		v_mem_req.addr = req_addr;
		/*memory request data(used in write)*/
		v_mem_req.data = data_read;
        v_mem_req.byteenable = 16'hFFFF;
		v_mem_req.rw = 2'd0;
		v_mem_req.valid = '0;

		//--------------------Cache FSM--------------------
		case(rstate)
		/*idle state*/
		idle: begin
			/*If there is a CPU request, then compare cache tag*/
            if (cpu_req_valid) begin

                if (req_addr[30]) begin //req_addr >= 32'h4000_0000
                    v_mem_req.valid = '1;

                    if (rw_flag) begin
                        v_mem_req.data = {96'h0, cpu_req_data};
                        v_mem_req.byteenable = io_write_byteenable;
               		    v_mem_req.rw = 2'd2;
					    next_state = write_direct;
                    end else begin
                        v_mem_req.byteenable = 16'h000F;
                        v_mem_req.rw = 2'd1;
					    next_state = read_direct;
                    end
                end else begin
                    next_state = compare_tag;
                end
            end
		end

        read_direct: begin
			/*memory controller has responded*/
			if (mem_data_ready) begin
                v_cpu_res.data = {96'h0, mem_data_data[31:0]};
                v_cpu_res.ready = 2'd1;
                next_state = idle;
			end
        end

        write_direct: begin
			/*memory controller has responded*/
			if (mem_data_ready) begin
                v_cpu_res.ready = 2'd2;
                next_state = idle;
			end
        end

		/*compare_tag state*/
		compare_tag: begin
			/*cache hit (tag match and cache entry is valid)*/
			if (req_addr[TAGMSB:TAGLSB] == tag_read.tag && tag_read.valid) begin

				/*write hit*/
				if (rw_flag) begin
					/*read/modify cache line*/
					tag_req.we = '1; data_req.we = '1;

					/*no change in tag*/
					tag_write.tag = tag_read.tag;
					tag_write.valid = '1;
					/*cache line is dirty*/
					tag_write.dirty = '1;

                    v_cpu_res.ready = 2'd2;
                end else begin 
                    v_cpu_res.ready = 2'd1;
                end

				next_state = idle;
			end
			/*cache miss*/
			else begin
				/*generate new tag*/
				tag_req.we = '1;
				tag_write.valid = '1;
				/*new tag*/
				tag_write.tag = req_addr[TAGMSB:TAGLSB];
				/*cache line is dirty if write*/
				tag_write.dirty = rw_flag;

				/*generate memory request on miss*/
				v_mem_req.valid = '1;
				/*compulsory miss or miss with clean block*/
                if (tag_read.valid == 1'b0 || tag_read.dirty == 1'b0) begin
                    v_mem_req.rw = 2'd1;
					/*wait till a new block is allocated*/
					next_state = allocate;
                end else begin //tag_read.valid == 1'b1 && tag_read.dirty == 1'b1
				/*miss with dirty line*/
					/*write back address*/
					v_mem_req.addr = {tag_read.tag, req_addr[TAGLSB-1:0]};
					v_mem_req.rw = 2'd2;
					/*wait till write is completed*/
					next_state = write_back;
				end
			end
		end
		/*wait for allocating a new cache line*/
		allocate: begin
            v_mem_req.valid = '1;
            v_mem_req.rw = 2'd1; // 这个时候sdr可能不在init状态导致无法接受rw信号，需保持rw信号
                                 // 原因？write_back在mem_data_ready也就是sdr
                                 // 在WRITE_END的状态下，发出了
                                 // v_mem_req.rw(read)，下个cycle，sdr才会到
                                 // init状态
			/*memory controller has responded*/
			if (mem_data_ready) begin
				/*re-compare tag for write miss (need modify correct word)*/
				next_state = compare_tag;
				data_write = mem_data_data;
				/*update cache line data*/
				data_req.we = '1;
			end
		end
		/*wait for writing back dirty cache line*/
		write_back: begin
            //v_mem_req.rw = 2'd2;
			/*write back is completed*/
			if (mem_data_ready) begin
				/*issue new memory request(allocating a new line)*/
				//v_mem_req.valid = '1;
				//v_mem_req.rw = 2'd1;

				next_state = allocate;
			end
		end
		endcase
	end

	always_ff @(posedge(clk)) begin
        if (rst) begin
		  rstate <= idle;						//reset to idle stateelse
        end else
		  rstate <= next_state;
	end

	always_ff @(posedge(clk) or posedge(rst)) begin
		if (rst) begin
			busy <= 0;
            pending_rw_flag	<= 0;
            pending_req_addr <= 32'h0;
		end else if(!busy) begin
			if(v_cpu_res.ready == 0 && cpu_req_valid != 0) begin
				busy <= 1;
                pending_rw_flag	<= cpu_req_rw;
                pending_req_addr <= cpu_req_addr; 
			end
		end else if(v_cpu_res.ready)
			busy <= 0;
	end

	/*connect cache tag/data memory*/
	dm_cache_tag ctag(
		.clk            (clk),
        .rst            (rst),
		.index          (tag_req.index),
		.we             (tag_req.we),
		.tag_write_valid(tag_write.valid),
		.tag_write_dirty(tag_write.dirty),
		.tag_write      (tag_write.tag),
		.tag_read_valid (tag_read.valid),
		.tag_read_dirty (tag_read.dirty),
		.tag_read       (tag_read.tag)
		);
	dm_cache_data cdata(
		.clk       (clk),
		.index     (data_req.index),
		.we        (data_req.we),
		.data_write(data_write),
		.data_read (data_read)
		);
endmodule
