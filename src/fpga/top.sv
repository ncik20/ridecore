`include "define.v"
`include "constants.vh"
`default_nettype none
module rc #(
  //PLIC Parameters
  parameter SOURCES           = 7,  //Number of interrupt sources
  parameter TARGETS           = 1,  //Number of interrupt targets
  parameter PRIORITIES        = 8,  //Number of Priority levels
  parameter MAX_PENDING_COUNT = 1,  //Max. number of 'pending' events
  parameter HAS_THRESHOLD     = 1,  //Is 'threshold' implemented?
  parameter HAS_CONFIG_REG    = 0   //Is the 'configuration' register implemented?
)
  (
   input  wire              clk,
   input  wire              clk_rtc,
   input  wire              reset_n,

   // avalon_mm_d
   output wire              avm_d_read,
   output wire              avm_d_write,
   output wire [127:0]      avm_d_writedata,
   output wire [31:0]       avm_d_address,
   input  wire [127:0]      avm_d_readdata,
   input  wire              avm_d_readdatavalid,
   output wire [15:0]       avm_d_byteenable,
   input  wire              avm_d_waitrequest,
   output wire [10:0]       avm_d_burstcount,
   // avalon_mm_io
   output wire              avm_io_read,
   output wire              avm_io_write,
   output wire [127:0]      avm_io_writedata,
   output wire [31:0]       avm_io_address,
   input  wire [127:0]      avm_io_readdata,
   input  wire              avm_io_readdatavalid,
   output wire [15:0]       avm_io_byteenable,
   input  wire              avm_io_waitrequest,
   output wire [10:0]       avm_io_burstcount,

   input  wire              irq_ps2,
   input  wire              irq_rs232
   );

   wire [`ADDR_LEN-1:0]     pc;
   wire [`ADDR_LEN-1:0]     cpu_res_pc;
   wire [4*`INSN_LEN-1:0]   idata;

   wire                     icache_req;
   wire                     kill_icache_req;
   wire [1:0]               icache_done;
   wire                     icache_busy;

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
   wire [15:0]              imem_byteenable;
   wire [4*`INSN_LEN-1:0]   imem_wdata;
   wire [4*`INSN_LEN-1:0]   imem_data;
   wire                     imem_done;

   wire [1:0]               l2_mem_we;
   wire [`ADDR_LEN-1:0]     l2_mem_addr;
   wire [15:0]              l2_mem_byteenable;
   wire [4*`DATA_LEN-1:0]   l2_mem_wdata;
   wire [4*`DATA_LEN-1:0]   l2_mem_data;
   wire                     l2_mem_done;
   wire                     il1_invalidate_valid;
   wire [`ADDR_LEN-1:0]     il1_invalidate_addr;

   wire [1:0]               mmio_we;
   wire [`ADDR_LEN-1:0]     mmio_addr;
   wire [15:0]              mmio_byteenable;
   wire [4*`DATA_LEN-1:0]   mmio_wdata;
   wire [4*`DATA_LEN-1:0]   mmio_data;
   wire                     mmio_done;

   wire [4*`DATA_LEN-1:0]   plic_data;
   reg                      plic_done;
   reg                      clint_done;

   reg                      rw_flag_;
   reg                      prog_loading;

   // wire [31:0] rdata4test;
   // assign pc_reg4test = {pc[15:0], rdata4test[15:0]};
   wire [SOURCES-1:0]       src;    //Interrupt sources
   wire [TARGETS-1:0]       eirq;
   wire [2-1:0]             tirq;
   wire [2-1:0]             sirq;

   clint_reg_pkg::reg_req_t s_reg_req;
   clint_reg_pkg::reg_rsp_t s_reg_rsp;

   assign s_reg_req.addr = mmio_addr[15:0];
   assign s_reg_req.write = mmio_we[1];
   assign s_reg_req.wdata = mmio_wdata;
   assign s_reg_req.wstrb = 4'b1111;
   assign s_reg_req.valid = (mmio_addr[17:16] == 2'b00 && |mmio_we);

   clint clint_ (
     .clk_i         (clk),
     .rst_ni        (reset_n),
     .testmode_i    (1'b0),
     .reg_req_i     (s_reg_req),
     .reg_rsp_o     (s_reg_rsp),
     .rtc_i         (clk_rtc),
     .timer_irq_o   (tirq),
     .ipi_o         (sirq)
   );

   assign src[4:0] = 5'b00000;
   assign src[5] = irq_rs232;
   assign src[6] = irq_ps2;

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

      .mmio_we(mmio_we),
      .mmio_addr(mmio_addr),
      .mmio_byteenable(mmio_byteenable),
      .mmio_wdata(mmio_wdata),
      .mmio_data(mmio_done ? mmio_data : plic_done ? plic_data : s_reg_rsp.rdata),
      .mmio_done(mmio_done | plic_done | clint_done),

      .icache_done(icache_done[0]),
      .icache_busy(icache_busy),

      .eirq(eirq),
      .tirq(tirq[0]),
      .sirq(sirq[0])
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
      // .mem_req_rw((mmio_addr[17:16] == 2'b10) ? mmio_we : 2'd0),
      .mem_req_rw((mmio_addr[31:16] == 16'h4000 || mmio_addr[31:16] == 16'h4001) ? 2'd0 : mmio_we),
      .maddr(mmio_addr),
      .byteenable(mmio_byteenable),
      .write_data(mmio_wdata),
      .read_data(mmio_data),
      .mem_done(mmio_done)
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
      .mem_req_rw(l2_mem_we),
      .maddr(l2_mem_addr),
      .byteenable(l2_mem_byteenable),
      .write_data(l2_mem_wdata),
      .read_data(l2_mem_data),
      .mem_done(l2_mem_done)
            );


   always @ (posedge clk) begin
      if (mmio_addr[17:16] == 2'b00 && |mmio_we) begin
         clint_done <= 1;
      end
      else
         clint_done <= 0;

      if (mmio_addr[17:16] == 2'b01 && |mmio_we) begin
         plic_done <= 1;
      end
      else
         plic_done <= 0;
   end

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
    .rst_n    ( reset_n         ), //Active low asynchronous reset
    .clk      ( clk             ), //System clock

    .we       ( (mmio_addr[17:16] == 2'b01) ? mmio_we[1] : 1'b0 ), //write cycle
    .re       ( (mmio_addr[17:16] == 2'b01) ? mmio_we[0] : 1'b0 ), //read cycle
    .PADDR    ( {24'h0, mmio_addr[7:0]}                         ), //address
    .PSTRB    ( 4'b1111                                         ), //PSTRB=byte-enables
    .PWDATA   ( mmio_wdata                                      ), //write data
    .PRDATA   ( plic_data                                       ), //read data

    .src      ( src                                             ), //Interrupt sources
    .irq      ( eirq                                            )  //Interrupt Requests
 );

   dm_cache_pl icache(
        .clk(clk),
        .rst(~reset_n), 
        .cpu_req_addr(pc),
        .cpu_req_data(32'h0),
        .cpu_req_funct3(3'b010),
        .cpu_req_rw(1'b0),
        .cpu_req_valid(rw_flag_ & icache_req),
        .cpu_req_kill(kill_icache_req),
        .invalidate_valid(il1_invalidate_valid),
        .invalidate_addr(il1_invalidate_addr),
        .invalidate_all(1'b0),
        .clean_start(1'b0),
        .clean_done(),

        .mem_data_data(imem_data),
        .mem_data_ready(imem_done),

        .mem_req_addr(imem_addr),
        .mem_req_data(imem_wdata),
        .mem_req_byteenable(imem_byteenable),
        .mem_req_rw(imem_we),
        //.mem_req_valid

        .cpu_res_pc(cpu_res_pc),
        .cpu_res_data(idata),
        .cpu_res_ready(icache_done),
        .busy(icache_busy)
   );

   l2_cache l2(
      .clk(clk),
      .rst(~reset_n),

      .i_req_addr(imem_addr),
      .i_req_data(imem_wdata),
      .i_req_byteenable(16'hFFFF),
      .i_req_rw(imem_we),
      .i_rsp_data(imem_data),
      .i_rsp_done(imem_done),

      .d_req_addr(dmem_addr),
      .d_req_data(dmem_wdata),
      .d_req_byteenable(dmem_byteenable),
      .d_req_rw(dmem_we),
      .d_rsp_data(dmem_data),
      .d_rsp_done(dmem_done),

      .i_invalidate_valid(il1_invalidate_valid),
      .i_invalidate_addr(il1_invalidate_addr),

      .mem_req_addr(l2_mem_addr),
      .mem_req_data(l2_mem_wdata),
      .mem_req_byteenable(l2_mem_byteenable),
      .mem_req_rw(l2_mem_we),
      .mem_rsp_data(l2_mem_data),
      .mem_rsp_done(l2_mem_done)
   );

endmodule // top

`default_nettype wire
