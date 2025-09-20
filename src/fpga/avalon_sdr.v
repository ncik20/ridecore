module avalon_sdr (
  // clk and reset are always required.
  input   wire          clk,
  input   wire          reset,
  // Bidirectional ports i.e. read and write.
  output  reg           avm_m0_read,
  output  reg           avm_m0_write,
  output  reg   [127:0] avm_m0_writedata,
  output  reg   [31:0]  avm_m0_address,
  input   wire  [127:0] avm_m0_readdata,
  input   wire          avm_m0_readdatavalid,
  output  reg   [15:0]  avm_m0_byteenable,
  input   wire          avm_m0_waitrequest,
  output  reg   [10:0]  avm_m0_burstcount,
  // External.
  input   wire  [1:0]   mem_req_rw,
  input   wire  [31:0]  maddr,
  input   wire  [15:0]  byteenable,
  input   wire  [127:0] write_data,  
  output  reg   [127:0] read_data,
  output  reg           mem_done
);

localparam INIT = 3'd0;
localparam READ_START = 3'd1;
localparam READ_END = 3'd2;
localparam WRITE_START = 3'd3;
localparam WRITE_END = 3'd4;


reg [2:0] cur_state;
reg [2:0] next_state;

reg [31:0] cur_addr;
reg [31:0] next_addr;

reg [15:0] cur_byteenable;
reg [15:0] next_byteenable;

reg [127:0] cur_writedata;
reg [127:0] next_writedata;

always @(posedge clk) begin
  if (reset) begin
    cur_state <= INIT;
    cur_addr <= 32'd0;
    cur_byteenable <= 16'd0;
    cur_writedata <= 128'd0;
  end else begin
    cur_state <= next_state;
    cur_addr <= next_addr;
    cur_byteenable <= next_byteenable;
    cur_writedata <= next_writedata;
  end
end

always @(*) begin
  next_state = cur_state;
  next_addr = cur_addr;
  next_writedata = cur_writedata;
  next_byteenable = cur_byteenable;
  read_data = 128'd0;
  mem_done = 1'b0;

  case(cur_state)
    INIT: begin

        if (mem_req_rw) begin
            next_addr = maddr;
            next_byteenable = byteenable;
        end

        if (mem_req_rw[0]) next_state = READ_START;

        if (mem_req_rw[1]) begin
            next_state = WRITE_START;
            next_writedata = write_data;
        end
    end

    READ_START: begin
      if (avm_m0_waitrequest) next_state = READ_START; // Wait here.
      else next_state = READ_END;
    end

    READ_END: begin
      if (avm_m0_readdatavalid) begin
        read_data = avm_m0_readdata;
        mem_done = 1'b1;

        next_state = INIT;
      end
      else next_state = READ_END; // Wait here.
    end

    WRITE_START: begin
      if (avm_m0_waitrequest) next_state = WRITE_START; // Wait here.
      else next_state = WRITE_END;
    end

    WRITE_END: begin
      mem_done = 1'b1;
      next_state = INIT;
    end

    default: begin
      next_state = INIT;
    end
  endcase
end

always @(*) begin
  avm_m0_address = 32'd0;
  avm_m0_read = 1'b0;
  avm_m0_write = 1'b0;
  avm_m0_byteenable = 16'd0;
  avm_m0_burstcount = 11'd0;
  avm_m0_writedata = 128'd0;

  case(cur_state)

    READ_START: begin
      avm_m0_address = cur_addr;
      avm_m0_read = 1'b1;
      avm_m0_byteenable = cur_byteenable; // Get all 128 bits.
      avm_m0_burstcount = 11'd1; // Get only 1 address value.
    end

    WRITE_START: begin
      avm_m0_address = cur_addr;
      avm_m0_write = 1'b1;
      avm_m0_writedata = cur_writedata;
      avm_m0_byteenable = cur_byteenable;
      avm_m0_burstcount = 11'd1; // Get only 1 address value.
    end

    default: begin
    end
  endcase
end

/*always @(posedge clk) begin
  if (reset) begin
    read_data <= 128'd0;
    read_done <= 0;
  end
  else begin
    case (cur_state)
      READ_END: begin
        if (avm_m0_readdatavalid) begin
          read_data <= avm_m0_readdata;
          read_done <= 1;
        end
      end

      default: begin
      end
    endcase
  end
end*/

endmodule
