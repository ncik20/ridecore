import cache_def::*;

module mmio_fsm(input logic clk, input logic rst,
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

		output logic [31:0]cpu_res_data,		//32-bit data
		output logic [1:0]cpu_res_ready,		//result : 0 = not ready, 1 = read ready, 2 = write ready
        output logic busy
	);

	//timeunit 1ns; timeprecision 1ps;

    reg	            pending_rw_flag;
    reg  [31:0]     pending_req_addr;
    reg  [31:0]     pending_req_data;
    reg  [2:0]      pending_req_funct3;
    wire            rw_flag = busy ? pending_rw_flag : cpu_req_rw;
    wire [31:0]     req_addr = busy ? pending_req_addr : cpu_req_addr;
    wire [31:0]     req_data = busy ? pending_req_data : cpu_req_data;
    wire [2:0]      req_funct3 = busy ? pending_req_funct3 : cpu_req_funct3;
    wire [15:0]     io_write_byteenable;

	/*write clock*/
	typedef enum {idle, write_direct, read_direct} cache_state_type;

	/*FSM state register*/
	cache_state_type next_state, rstate;

	/*temporary variable for cache controller result*/
	cpu_result_type v_cpu_res;

	/*temporary variable for memory controller request*/
	mem_req_type v_mem_req;

	assign mem_req_addr = v_mem_req.addr;
	assign mem_req_data = v_mem_req.data;
    assign mem_req_byteenable = v_mem_req.byteenable;
	assign mem_req_rw = v_mem_req.rw;
	assign mem_req_valid = v_mem_req.valid;

	assign cpu_res_data = v_cpu_res.data[31-:32];
	assign cpu_res_ready = v_cpu_res.ready;

    assign io_write_byteenable = (req_funct3 == 3'b000) ? 16'h0001 :
        (req_funct3 == 3'b001) ? 16'h0003 : 16'h000F;

	always_comb begin
		/*--------------------default values for all signals--------------------*/
		/*no state change by default*/
        next_state = rstate;
		v_cpu_res = '{0, 0};

		/*memory request address(sampled from CPU request)*/
		v_mem_req.addr = req_addr;
		/*memory request data(used in write)*/
		v_mem_req.data = {96'h0, req_data};
        v_mem_req.byteenable = 16'hF;
		v_mem_req.rw = 2'd0;
		v_mem_req.valid = '0;

		//--------------------Cache FSM--------------------
		case(rstate)
		/*idle state*/
		idle: begin
            if (cpu_req_valid) begin
                v_mem_req.valid = '1;

                if (rw_flag) begin
                    v_mem_req.byteenable = io_write_byteenable;
                    v_mem_req.rw = 2'd2;
                    next_state = write_direct;
                end else begin
                    v_mem_req.rw = 2'd1;
                    next_state = read_direct;
                end
            end
		end

        read_direct: begin
			/*memory controller has responded*/
			if (mem_data_ready) begin
                v_cpu_res.data = mem_data_data;
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
                pending_rw_flag	    <= cpu_req_rw;
                pending_req_addr    <= cpu_req_addr;
                pending_req_data    <= cpu_req_data;
                pending_req_funct3  <= cpu_req_funct3;
			end
		end else if(|v_cpu_res.ready)
			busy <= 0;
	end

endmodule
