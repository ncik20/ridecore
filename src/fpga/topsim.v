`include "define.v"
`include "constants.vh"
`default_nettype none
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
   input  wire                  clk,
   input  wire                  clk_rtc,
   input  wire                  reset_x,

   inout  wire                  ps2_clk,
   inout  wire                  ps2_data,

   input  wire                  rs232_rxd,
   output wire                  rs232_txd
   );
   wire reset_n = reset_x;
/*
   wire [SOURCES-1:0]       src;    //Interrupt sources

   wire [`ADDR_LEN-1:0]     pc;
   wire [`ADDR_LEN-1:0]     cpu_res_pc;
   wire [4*`INSN_LEN-1:0]   idata;   

   wire                     icache_req;
   wire                     kill_icache_req;
   wire [1:0]               icache_done;
   wire                     icache_busy;

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

   wire [1:0]               mmio_we;
   wire [`ADDR_LEN-1:0]     mmio_addr;
   wire [15:0]              mmio_byteenable;
   wire [4*`DATA_LEN-1:0]   mmio_wdata;
   wire [4*`DATA_LEN-1:0]   mmio_data;
   wire                     mmio_done;

   reg  [1:0]               rw_flag_;
   reg                      prog_loading;
*/

   wire                     avm_i_read;
   wire [31:0]              avm_i_address;
   wire [127:0]             avm_i_readdata;
   reg                      avm_i_readdatavalid;

   wire                     avm_d_read;
   wire                     avm_d_write;
   wire [31:0]              avm_d_address;
   wire [127:0]             avm_d_readdata;
   wire [127:0]             avm_d_writedata;
   reg                      avm_d_readdatavalid;

   wire                     avm_io_read;
   wire                     avm_io_write;
   wire [31:0]              avm_io_address;
   wire [127:0]             avm_io_readdata;
   wire [127:0]             avm_io_readdata_keyboard;
   wire [127:0]             avm_io_readdata_uart;
   wire [127:0]             avm_io_writedata;
   reg                      avm_io_readdatavalid;

   wire                     ridecore_0_irqps2_export;
   wire                     ridecore_0_irqrs232_export;

   reg  [31:0]              io_address;

   assign avm_io_readdata = (io_address[9:8] == 2'b00) ? avm_io_readdata_keyboard :
                            (io_address[9:8] == 2'b01) ? avm_io_readdata_uart : 128'd0;

   reg iram_read;
   reg dram_read;

   // reg  [7:0]               led_out;

   always @ (posedge clk) begin
      if (!reset_n) begin
          // led_out <= 0;
          io_address <= 0;

          iram_read <= 0;
          dram_read <= 0;
          avm_i_readdatavalid <= 0;
          avm_d_readdatavalid <= 0;
          avm_io_readdatavalid <= 0;
      end else begin
          // if (avm_io_write) led_out <= avm_io_writedata[7:0];
          // else led_out <= led_out;

          if (avm_io_write || avm_io_read) begin
             avm_io_readdatavalid <= 1;
             io_address <= avm_io_address;
          end
          else begin
             avm_io_readdatavalid <= 0;
             io_address <= 0;
          end

          if (avm_i_read)
              iram_read <= 1;
          else
              iram_read <= 0;

          if (avm_d_read)
              dram_read <= 1;
          else
              dram_read <= 0;

          if (iram_read)
              avm_i_readdatavalid <= 1;
          else
              avm_i_readdatavalid <= 0;

          if (dram_read)
              avm_d_readdatavalid <= 1;
          else
              avm_d_readdatavalid <= 0;
      end
   end

wire [127:0] avm_i_readdata_ram_s1;

	rc #(
		.SOURCES           (7),
		.TARGETS           (1),
		.PRIORITIES        (8),
		.MAX_PENDING_COUNT (1),
		.HAS_THRESHOLD     (1),
		.HAS_CONFIG_REG    (0)
	) ridecore_0 (
		.clk                  (clk),                                     //              clock.clk
        .clk_rtc              (clk_rtc),
		.reset_n              (reset_n),             //              reset.reset_n

		.avm_d_read           (avm_d_read),                 //        data_master.read
		.avm_d_write          (avm_d_write),                //                   .write
		.avm_d_writedata      (avm_d_writedata),            //                   .writedata
		.avm_d_address        (avm_d_address),              //                   .address
		.avm_d_readdata       (avm_d_readdata),             //                   .readdata
		.avm_d_readdatavalid  (avm_d_readdatavalid),        //                   .readdatavalid
		//.avm_d_byteenable     (ridecore_0_data_master_byteenable),           //                   .byteenable
		.avm_d_waitrequest    (1'b0),          //                   .waitrequest
		//.avm_d_burstcount     (ridecore_0_data_master_burstcount),           //                   .burstcount

		.avm_i_read           (avm_i_read),          // instruction_master.read
		//.avm_i_write          (ridecore_0_data_master_write),         //                   .write
		//.avm_i_writedata      (ridecore_0_data_master_writedata),     //                   .writedata
		.avm_i_address        (avm_i_address),       //                   .address
		.avm_i_readdata       (avm_i_readdata),      //                   .readdata
		.avm_i_readdatavalid  (avm_i_readdatavalid), //                   .readdatavalid
		//.avm_i_byteenable     (ridecore_0_instruction_master_byteenable),    //                   .byteenable
		.avm_i_waitrequest    (1'b0),   //                   .waitrequest
		//.avm_i_burstcount     (ridecore_0_instruction_master_burstcount),    //                   .burstcount

		.avm_io_read          (avm_io_read),                   //          io_master.read
		.avm_io_write         (avm_io_write),                  //                   .write
		.avm_io_writedata     (avm_io_writedata),              //                   .writedata
		.avm_io_address       (avm_io_address),                //                   .address
		.avm_io_readdata      (avm_io_readdata),               //                   .readdata
		.avm_io_readdatavalid (avm_io_readdatavalid),          //                   .readdatavalid
		//.avm_io_byteenable    (ridecore_0_io_master_byteenable),             //                   .byteenable
		.avm_io_waitrequest   (1'b0),            //                   .waitrequest
		//.avm_io_burstcount    (ridecore_0_io_master_burstcount),             //                   .burstcount

		.irq_ps2              (ridecore_0_irqps2_export),                    //             irqps2.export
		.irq_rs232            (ridecore_0_irqrs232_export)                   //           irqrs232.export
	);
/*
   //dm_cache_fsm icache(
   dm_cache_pl icache(
        .clk(clk),
        .rst(~reset_n), 
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
      .reset(~reset_n),
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
*/

wire [127:0] avm_i_readdata_ram;
wire [127:0] avm_d_readdata_ram;

iram iram_ (
	.address ( avm_i_address[15:4] ),
	.clock ( clk ),
	.data ( 128'd0 ),
	.rden ( avm_i_read ),
	.wren ( 1'b0 ),
	.q ( avm_i_readdata )
	);

   imem_ld instmemory(
		      .clk(clk),
		      .addr(avm_i_address[12:4]),
		      .rdata(avm_i_readdata_ram),
		      .we({1'b0, avm_i_read})
		      //.done(avm_i_readdatavalid)
		      );

/*
   avalon_sdr sdr_d(
      .clk(clk),
      .reset(~reset_n),
      .avm_m0_write(avm_d_write),
      .avm_m0_writedata(avm_d_writedata),
      .avm_m0_read(avm_d_read),
      .avm_m0_address(avm_d_address),
      .avm_m0_readdata(avm_d_readdata),
      .avm_m0_readdatavalid(avm_d_readdatavalid),
      .avm_m0_waitrequest(1'b0),
      .mem_req_rw(dmem_we),
      .maddr(dmem_addr),
      .byteenable(dmem_byteenable),
      .write_data(dmem_wdata),
      .read_data(dmem_data),
      .mem_done(dmem_done)
            );
*/

ram	dram (
	.address ( avm_d_address[15:4] ),
	.clock ( clk ),
	.data ( avm_d_writedata ),
	.rden ( avm_d_read ),
	.wren ( avm_d_write ),
	.q ( avm_d_readdata )
	);

   dmem datamemory(
		   .clk(clk),
		   .addr(avm_d_address),
		   .wdata(avm_d_writedata),
		   .we({avm_d_write, avm_d_read}),
		   .rdata(avm_d_readdata_ram)
           //.done(avm_d_readdatavalid)
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
      // .avm_m0_byteenable(avm_io_byteenable),
      // .avm_m0_waitrequest(avm_io_waitrequest),
      .avm_m0_waitrequest(1'b0),
      // .avm_m0_burstcount(avm_io_burstcount),
      .mem_req_rw(mmio_we),
      .maddr(mmio_addr),
      .byteenable(mmio_byteenable),
      .write_data(mmio_wdata),
      .read_data(mmio_data),
      .mem_done(mmio_done)
            );
*/
   soc_system qsys(
       .clk_clk(clk),
       .reset_reset_n(reset_n),

       .ps2_0_avalon_ps2_slave_address(avm_io_address[2]),
       .ps2_0_avalon_ps2_slave_chipselect((avm_io_write || avm_io_read) && avm_io_address[31:8] == 24'h4002_00),
       .ps2_0_avalon_ps2_slave_byteenable(4'b0001),
       .ps2_0_avalon_ps2_slave_read(avm_io_read),
       .ps2_0_avalon_ps2_slave_write(avm_io_write),
       .ps2_0_avalon_ps2_slave_writedata(avm_io_writedata),
       .ps2_0_avalon_ps2_slave_readdata(avm_io_readdata_keyboard),
       //.ps2_0_avalon_ps2_slave_waitrequest(),
       .ps2_0_external_interface_CLK(ps2_clk),
       .ps2_0_external_interface_DAT(ps2_data),
       .ps2_0_interrupt_irq(ridecore_0_irqps2_export),

       .rs232_0_avalon_rs232_slave_address(avm_io_address[2]),
       .rs232_0_avalon_rs232_slave_chipselect((avm_io_write || avm_io_read) && avm_io_address[31:8] == 24'h4002_01),
       .rs232_0_avalon_rs232_slave_byteenable(4'b0001),
       .rs232_0_avalon_rs232_slave_read(avm_io_read),
       .rs232_0_avalon_rs232_slave_write(avm_io_write),
       .rs232_0_avalon_rs232_slave_writedata(avm_io_writedata),
       .rs232_0_avalon_rs232_slave_readdata(avm_io_readdata_uart),
       //.rs232_0_avalon_rs232_slave_waitrequest(),
       .rs232_0_external_interface_RXD(rs232_rxd),
       .rs232_0_external_interface_TXD(rs232_txd),
       .rs232_0_interrupt_irq(ridecore_0_irqrs232_export)
   );

endmodule // top

`default_nettype wire
