`include "define.v"
`include "constants.vh"

module top #(
  //PLIC Parameters
  parameter SOURCES           = 7,  //Number of interrupt sources
  parameter TARGETS           = 1,  //Number of interrupt targets
  parameter PRIORITIES        = 8,  //Number of Priority levels
  parameter MAX_PENDING_COUNT = 1,  //Max. number of 'pending' events
  parameter HAS_THRESHOLD     = 1,  //Is 'threshold' implemented?
  parameter HAS_CONFIG_REG    = 0   //Is the 'configuration' register implemented?
)
  (
   input                    clk,
   input                    reset_x,

   inout                    ps2_clk,
   inout                    ps2_data
   );

   wire [SOURCES-1:0]       src;    //Interrupt sources

   wire [`ADDR_LEN-1:0]     pc;
   wire [`ADDR_LEN-1:0]     cpu_res_pc;
   wire [4*`INSN_LEN-1:0]   idata;   

   wire                     icache_req;
   wire                     kill_icache_req;
   wire [1:0]               icache_done;
   wire                     icache_busy;

   wire                     avm_i_read;
   wire [31:0]              avm_i_address;
   wire [127:0]             avm_i_readdata;
   wire                     avm_i_readdatavalid;

   wire                     avm_d_read;
   wire                     avm_d_write;   
   wire [31:0]              avm_d_address;
   wire [127:0]             avm_d_readdata;
   wire [127:0]             avm_d_readdata_plic;
   wire [127:0]             avm_d_readdata_keyboard;
   wire [127:0]             avm_d_writedata;   
   wire                     avm_d_readdatavalid;

   wire [1:0]               imem_we;
   wire [`ADDR_LEN-1:0]     imem_addr;
   wire [4*`INSN_LEN-1:0]   imem_data;
   wire                     imem_done;

   wire [1:0]               dmem_we;
   wire [`ADDR_LEN-1:0]     dmem_addr;
   wire [15:0]              dmem_byteenable;
   wire [4*`DATA_LEN-1:0]   dmem_wdata;
   wire [4*`DATA_LEN-1:0]   dmem_data;
   wire                     dmem_done;

   reg  [1:0]               rw_flag_;
   reg                      prog_loading;

   wire [TARGETS-1:0]       irq;
   reg                      plic_reg_done;

   assign src[5:0] = 6'b000000;

   always @ (posedge clk) begin
      if (!reset_x) begin
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
      .reset(~reset_x | prog_loading),
      .icache_req(icache_req),
      .kill_icache_req(kill_icache_req),
      .pc(pc),
      .cpu_res_pc(cpu_res_pc),
      .idata(idata),

      .dmem_we(dmem_we),
      .dmem_addr(dmem_addr),
      .dmem_byteenable(dmem_byteenable),
      .dmem_wdata(dmem_wdata),
      .dmem_data(dmem_data),
      .dmem_done(dmem_done),

      .icache_done(icache_done[0]),
      .icache_busy(icache_busy),

      .irq(irq)
      ); 

   avalon_sdr sdr_d(
      .clk(clk),
      .reset(~reset_x),
      .avm_m0_write(avm_d_write),
      .avm_m0_writedata(avm_d_writedata),
      .avm_m0_read(avm_d_read),
      .avm_m0_address(avm_d_address),
      .avm_m0_readdata(~dmem_addr[30] ? avm_d_readdata :
                        dmem_addr[9:8] == 2'b00 ? avm_d_readdata_plic : avm_d_readdata_keyboard),
      .avm_m0_readdatavalid(avm_d_readdatavalid | plic_reg_done),
      .avm_m0_waitrequest(1'b0),
      .mem_req_rw(dmem_we),
      .maddr(dmem_addr),
      .byteenable(dmem_byteenable),
      .write_data(dmem_wdata),
      .read_data(dmem_data),
      .mem_done(dmem_done)
            );

   dmem datamemory(
		   .clk(clk),
		   .addr(avm_d_address),
		   .wdata(avm_d_writedata),
		   .we(dmem_addr[30] ? 2'h0 : {avm_d_write, avm_d_read}),
		   .rdata(avm_d_readdata),
           .done(avm_d_readdatavalid)
		   );

  apb4_plic_top #(
    //PLIC Parameters
    .SOURCES           ( SOURCES ),
    .TARGETS           ( TARGETS ),
    .PRIORITIES        ( PRIORITIES ),
    .MAX_PENDING_COUNT ( MAX_PENDING_COUNT ),
    .HAS_THRESHOLD     ( HAS_THRESHOLD ),
    .HAS_CONFIG_REG    ( HAS_CONFIG_REG )
  )
  plic (
    .rst_n    ( reset_x         ), //Active low asynchronous reset
    .clk      ( clk             ), //System clock

    .we       ( (dmem_addr[30] == 1'b1 && dmem_addr[9:8] == 2'b00) ? avm_d_write : 1'b0 ), //write cycle
    .re       ( (dmem_addr[30] == 1'b1 && dmem_addr[9:8] == 2'b00) ? avm_d_read  : 1'b0 ), //read cycle
    .PADDR    ( {24'h0, avm_d_address[7:0]}        ), //address
    .PSTRB    ( 4'b1111                            ), //PSTRB=byte-enables
    .PWDATA   ( avm_d_writedata                    ), //write data
    .PRDATA   ( avm_d_readdata_plic                ), //read data

    .src      ( src                                ), //Interrupt sources
    .irq      ( irq                                )  //Interrupt Requests
 );

   always @ (posedge clk) begin
      plic_reg_done <= 0;
      if (dmem_addr[30] && (avm_d_write || avm_d_read)) begin
         plic_reg_done <= 1;
      end
   end

   soc_system qsys(
       .clk_clk(clk),
       .reset_reset_n(reset_x),
       .ps2_0_avalon_ps2_slave_address(avm_d_address[2]),
       .ps2_0_avalon_ps2_slave_chipselect(dmem_addr[30] == 1'b1 && dmem_addr[9:8] == 2'b10),
       .ps2_0_avalon_ps2_slave_byteenable(4'b0001),
       .ps2_0_avalon_ps2_slave_read((dmem_addr[30] == 1'b1 && dmem_addr[9:8] == 2'b10) ? avm_d_read  : 1'b0),
       .ps2_0_avalon_ps2_slave_write((dmem_addr[30] == 1'b1 && dmem_addr[9:8] == 2'b10) ? avm_d_write : 1'b0),
       .ps2_0_avalon_ps2_slave_writedata(avm_d_writedata),
       .ps2_0_avalon_ps2_slave_readdata(avm_d_readdata_keyboard),
       //.ps2_0_avalon_ps2_slave_waitrequest(),
       .ps2_0_external_interface_CLK(ps2_clk),
       .ps2_0_external_interface_DAT(ps2_data),
       .ps2_0_interrupt_irq(src[6])
   );

/*
   cache icache(
            .CLK(clk),
            .RST(~reset_x),
            .rw_flag_(rw_flag_),
            .addr_(pc),
            .read_data(idata),
            .busy(icache_busy),
            .done(icache_done),
            .mem_rw_flag(imem_we),
            .mem_addr(imem_addr),
            .mem_read_data(imem_data),
            .mem_done(imem_done)
      );*/

   //dm_cache_fsm icache(
   dm_cache_pl icache(
        .clk(clk),
        .rst(~reset_x), 
        .cpu_req_addr(pc),
        .cpu_req_data(32'h0),
        .cpu_req_funct3(3'b010),
        .cpu_req_rw(1'b0),
        .cpu_req_valid(rw_flag_[0] & icache_req),
        .cpu_req_kill(kill_icache_req),

        .mem_data_data(imem_data),
        .mem_data_ready(imem_done),

        .mem_req_addr(imem_addr),
        .mem_req_rw(imem_we),
        //.mem_req_valid

        .cpu_res_pc(cpu_res_pc),
        .cpu_res_data(idata),
        .cpu_res_ready(icache_done),
        .busy(icache_busy)
   );
 
   avalon_sdr sdr_i(
      .clk(clk),
      .reset(~reset_x),
      .avm_m0_read(avm_i_read),
      .avm_m0_address(avm_i_address),
      .avm_m0_readdata(avm_i_readdata),
      .avm_m0_readdatavalid(avm_i_readdatavalid),
      .avm_m0_waitrequest(1'b0),
      .mem_req_rw(imem_we),
      .maddr(imem_addr),
      .byteenable(16'hFFFF),
      .read_data(imem_data),
      .mem_done(imem_done)
      );
   imem_ld instmemory(
		      .clk(clk),
		      .addr(avm_i_address[12:4]),
		      .rdata(avm_i_readdata),
		      .we({1'b0, avm_i_read}),
		      .done(avm_i_readdatavalid)
		      );
endmodule // top

   
