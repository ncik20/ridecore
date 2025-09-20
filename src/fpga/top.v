`include "define.v"
`include "constants.vh"

module top
  (
   input clk,
   input reset_n,
   // avalon_mm_i
   output             avm_i_read,
   output             avm_i_write,
   output [127:0]     avm_i_writedata,
   output [31:0]      avm_i_address,
   input [127:0]      avm_i_readdata,
   input              avm_i_readdatavalid,
   output [15:0]      avm_i_byteenable,
   input              avm_i_waitrequest,
   output [10:0]      avm_i_burstcount,
   // avalon_mm_d
   output             avm_d_read,
   output             avm_d_write,
   output [127:0]     avm_d_writedata,
   output [31:0]      avm_d_address,
   input [127:0]      avm_d_readdata,
   input              avm_d_readdatavalid,
   output [15:0]      avm_d_byteenable,
   input              avm_d_waitrequest,
   output [10:0]      avm_d_burstcount,
   // avalon_mm_io
   output             avm_io_read,
   output             avm_io_write,
   output [127:0]     avm_io_writedata,
   output [31:0]      avm_io_address,
   input [127:0]      avm_io_readdata,
   input              avm_io_readdatavalid,
   output [15:0]      avm_io_byteenable,
   input              avm_io_waitrequest,
   output [10:0]      avm_io_burstcount,

   output [31:0]      pc_reg4test
   );

   wire [`ADDR_LEN-1:0]     pc;

   wire [4*`INSN_LEN-1:0]   idata;

   wire [1:0]               dmem_we;
   wire [`ADDR_LEN-1:0]     dmem_addr;
   wire [15:0]              dmem_byteenable;
   wire [4*`DATA_LEN-1:0]   dmem_wdata;
   wire [4*`DATA_LEN-1:0]   dmem_data;
   wire                     dmem_done;
   wire [4*`DATA_LEN-1:0]   iomem_data;
   wire                     iomem_done;

   wire [1:0]               imem_we;
   wire [`ADDR_LEN-1:0]     imem_addr;
   wire [4*`INSN_LEN-1:0]   imem_data;
   wire                     imem_done;

   wire [1:0] icache_done;
   wire       icache_busy;

   reg [1:0]  rw_flag_;
   reg        prog_loading;

   wire [31:0] rdata4test;
   assign pc_reg4test = {pc[15:0], rdata4test[15:0]};

   always @ (posedge clk) begin
      if (!reset_n) begin
	    prog_loading <= 1'b1;
        rw_flag_ <= 0;
      end else begin
	    prog_loading <= 0;
        rw_flag_ <= 1;
      end
   end

   pipeline pipe
     (
      .clk(clk),
      .reset(~reset_n | prog_loading),
      .pc(pc),
      .idata(idata),

      .dmem_we(dmem_we),
      .dmem_addr(dmem_addr),
      .dmem_byteenable(dmem_byteenable),
      .dmem_wdata(dmem_wdata),
      .dmem_data(dmem_addr[30] ? iomem_data : dmem_data),
      .dmem_done(dmem_addr[30] ? iomem_done : dmem_done),

      .icache_done(icache_done[0]),
      .icache_busy(icache_busy),

      .raddr4test(5'd15),
      .rdata4test(rdata4test)
      );

   avalon_sdr sdr_d(
      .clk(clk),
      .reset(~reset_n),      
      .avm_m0_write(avm_d_write),
      .avm_m0_writedata(avm_d_writedata),
      .avm_m0_read(avm_d_read),
      .avm_m0_address(avm_d_address),
      .avm_m0_readdata(avm_d_readdata),
      .avm_m0_readdatavalid(avm_d_readdatavalid),
      .avm_m0_byteenable(avm_d_byteenable),
      .avm_m0_waitrequest(avm_d_waitrequest),
      .avm_m0_burstcount(avm_d_burstcount),
      .mem_req_rw(dmem_addr[30] ? 2'h0 : dmem_we),
      .maddr(dmem_addr),
      .byteenable(dmem_byteenable),
      .write_data(dmem_wdata),
      .read_data(dmem_data),
      .mem_done(dmem_done)
            );

   avalon_sdr sdr_io(
      .clk(clk),
      .reset(~reset_n),      
      .avm_m0_write(avm_io_write),
      .avm_m0_writedata(avm_io_writedata),
      .avm_m0_read(avm_io_read),
      .avm_m0_address(avm_io_address),
      .avm_m0_readdata(avm_io_readdata),
      .avm_m0_readdatavalid(avm_io_readdatavalid),
      .avm_m0_byteenable(avm_io_byteenable),
      .avm_m0_waitrequest(avm_io_waitrequest),
      .avm_m0_burstcount(avm_io_burstcount),
      .mem_req_rw(dmem_addr[30] ? dmem_we : 2'h0),
      .maddr(dmem_addr),
      .byteenable(dmem_byteenable),
      .write_data(dmem_wdata),
      .read_data(iomem_data),
      .mem_done(iomem_done)
            );
/*
   avalon_sdr sdr_io(
      .clk(clk),
      .reset(~reset_n),      
      .avm_m0_write(avm_io_write),
      .avm_m0_writedata(avm_io_writedata),
      .avm_m0_read(avm_io_read),
      .avm_m0_address(avm_io_address),
      .avm_m0_readdata(avm_io_readdata),
      .avm_m0_readdatavalid(avm_io_readdatavalid),
      .avm_m0_byteenable(avm_io_byteenable),
      .avm_m0_waitrequest(avm_io_waitrequest),
      .avm_m0_burstcount(avm_io_burstcount),
      .mem_req_rw(2'h2),
      .maddr(32'h4000_0000),
      .byteenable(16'h000f),
      .write_data(pc),
      //.read_data(iomem_data),
      .mem_done(iomem_done)
            );*/

   dm_cache_fsm icache(
        .clk(clk),
        .rst(~reset_n), 
        .cpu_req_addr(pc),
        .cpu_req_data(32'h0),
        .cpu_req_funct3(3'b010),
        .cpu_req_rw(1'b0),
        .cpu_req_valid(rw_flag_[0]),

        .mem_data_data(imem_data),
        .mem_data_ready(imem_done),

        .mem_req_addr(imem_addr),
        .mem_req_rw(imem_we),
        //.mem_req_valid

        .cpu_res_data(idata),
        .cpu_res_ready(icache_done),
        .busy(icache_busy)
   );

   avalon_sdr sdr_i(
      .clk(clk),
      .reset(~reset_n),
      .avm_m0_read(avm_i_read),
      .avm_m0_write(avm_i_write),
      .avm_m0_writedata(avm_i_writedata),
      .avm_m0_address(avm_i_address),
      .avm_m0_readdata(avm_i_readdata),
      .avm_m0_readdatavalid(avm_i_readdatavalid),
      .avm_m0_byteenable(avm_i_byteenable),
      .avm_m0_waitrequest(avm_i_waitrequest),
      .avm_m0_burstcount(avm_i_burstcount),
      .mem_req_rw(imem_we),
      .maddr(imem_addr),
      .byteenable(16'hFFFF),
      .read_data(imem_data),
      .mem_done(imem_done)
      );

endmodule // top

   
