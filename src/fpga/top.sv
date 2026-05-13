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
   input  wire              irq_rs232,

   input  wire              dbg_tck,
   input  wire              dbg_tms,
   input  wire              dbg_trst_n,
   input  wire              dbg_tdi,
   output wire              dbg_tdo,
   output wire              dbg_tdo_oe
   );

   wire [`ADDR_LEN-1:0]     pc;
   wire [`ADDR_LEN-1:0]     cpu_res_pc;
   wire [4*`INSN_LEN-1:0]   idata;
   wire [4*`INSN_LEN-1:0]   icache_idata;
   wire [`ADDR_LEN-1:0]     pipe_cpu_res_pc;

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
   wire                     l2_clean_addr_start;
   wire [`ADDR_LEN-1:0]     l2_clean_addr;
   wire                     l2_clean_addr_done;
   wire [1:0]               ram_mem_we;
   wire [`ADDR_LEN-1:0]     ram_mem_addr;
   wire [15:0]              ram_mem_byteenable;
   wire [4*`DATA_LEN-1:0]   ram_mem_wdata;
   wire [4*`DATA_LEN-1:0]   ram_mem_data;
   wire                     ram_mem_done;
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

   localparam [`ADDR_LEN-1:0] DM_BASE_ADDR = 32'h4003_0000;
   localparam [`ADDR_LEN-1:0] DEBUG_ROM_ENTRY = DM_BASE_ADDR + 32'h800;
   wire                      if_dm_access;
   wire                      mmio_dm_access;

   wire                      dbg_dmi_rst_n;
   dm::dmi_req_t             dbg_dmi_req;
   wire                      dbg_dmi_req_valid;
   wire                      dbg_dmi_req_ready;
   dm::dmi_resp_t            dbg_dmi_resp;
   wire                      dbg_dmi_resp_valid;
   wire                      dbg_dmi_resp_ready;

   wire                      dbg_ndmreset;
   wire                      dbg_dmactive;
   wire                      dbg_debug_req;
   dm::hartinfo_t [0:0]      dbg_hartinfo;

   wire                      dbg_slave_req;
   wire                      dbg_slave_we;
   wire [`ADDR_LEN-1:0]      dbg_slave_addr;
   wire [3:0]                dbg_slave_be;
   wire [`DATA_LEN-1:0]      dbg_slave_wdata;
   wire [`DATA_LEN-1:0]      dbg_slave_rdata;

   wire [4*`INSN_LEN-1:0]    dbg_i_rsp_data;
   wire [`ADDR_LEN-1:0]      dbg_i_rsp_pc;
   wire                      dbg_i_rsp_done;
   wire                      dbg_i_busy;
   wire [`DATA_LEN-1:0]      dbg_d_rsp_rdata;
   wire                      dbg_d_rsp_done;
   wire                      dbg_d_busy;

   wire                      dbg_master_req;
   wire [`ADDR_LEN-1:0]      dbg_master_addr;
   wire                      dbg_master_we;
   wire [`DATA_LEN-1:0]      dbg_master_wdata;
   wire [3:0]                dbg_master_be;
   wire                      dbg_master_gnt;
   wire                      dbg_master_r_valid;
   wire                      dbg_master_r_err;
   wire                      dbg_master_r_other_err;
   wire [`DATA_LEN-1:0]      dbg_master_rdata;

   wire [1:0]                dbg_sba_mem_we;
   wire [`ADDR_LEN-1:0]      dbg_sba_mem_addr;
   wire [15:0]               dbg_sba_mem_byteenable;
   wire [4*`DATA_LEN-1:0]    dbg_sba_mem_wdata;
   wire [4*`DATA_LEN-1:0]    dbg_sba_mem_data;
   wire                      dbg_sba_mem_done;
   wire                      dbg_sba_accept;
   wire                      dbg_sba_ram_req;
   reg [1:0]                 ram_owner;

   localparam [1:0] RAM_OWNER_NONE = 2'd0;
   localparam [1:0] RAM_OWNER_L2   = 2'd1;
   localparam [1:0] RAM_OWNER_SBA  = 2'd2;

   // wire [31:0] rdata4test;
   // assign pc_reg4test = {pc[15:0], rdata4test[15:0]};
   wire [SOURCES-1:0]       src;    //Interrupt sources
   wire [TARGETS-1:0]       eirq;
   wire [2-1:0]             tirq;
   wire [2-1:0]             sirq;

   clint_reg_pkg::reg_req_t s_reg_req;
   clint_reg_pkg::reg_rsp_t s_reg_rsp;

   assign if_dm_access = (pc[31:12] == DM_BASE_ADDR[31:12]);
   assign mmio_dm_access = (mmio_addr[31:12] == DM_BASE_ADDR[31:12]);
   assign idata = dbg_i_rsp_done ? dbg_i_rsp_data : icache_idata;
   assign pipe_cpu_res_pc = dbg_i_rsp_done ? dbg_i_rsp_pc : cpu_res_pc;
   assign dbg_sba_accept = (ram_owner == RAM_OWNER_NONE) && !(|l2_mem_we);
   assign dbg_sba_ram_req = dbg_master_req && dbg_sba_accept &&
                            (dbg_master_addr < 32'h4000_0000);

   assign ram_mem_we = (ram_owner == RAM_OWNER_SBA) ? dbg_sba_mem_we :
                       (ram_owner == RAM_OWNER_NONE && dbg_sba_ram_req && |dbg_sba_mem_we) ? dbg_sba_mem_we :
                       l2_mem_we;
   assign ram_mem_addr = (ram_owner == RAM_OWNER_SBA) ? dbg_sba_mem_addr :
                         (ram_owner == RAM_OWNER_NONE && dbg_sba_ram_req && |dbg_sba_mem_we) ? dbg_sba_mem_addr :
                         l2_mem_addr;
   assign ram_mem_byteenable = (ram_owner == RAM_OWNER_SBA) ? dbg_sba_mem_byteenable :
                               (ram_owner == RAM_OWNER_NONE && dbg_sba_ram_req && |dbg_sba_mem_we) ? dbg_sba_mem_byteenable :
                               l2_mem_byteenable;
   assign ram_mem_wdata = (ram_owner == RAM_OWNER_SBA) ? dbg_sba_mem_wdata :
                          (ram_owner == RAM_OWNER_NONE && dbg_sba_ram_req && |dbg_sba_mem_we) ? dbg_sba_mem_wdata :
                          l2_mem_wdata;

   assign l2_mem_data = ram_mem_data;
   assign l2_mem_done = (ram_owner == RAM_OWNER_L2) && ram_mem_done;
   assign dbg_sba_mem_data = ram_mem_data;
   assign dbg_sba_mem_done = (ram_owner == RAM_OWNER_SBA) && ram_mem_done;

   assign dbg_hartinfo[0] = '{
      zero1      : 8'h0,
      nscratch   : 4'h2,
      zero0      : 3'h0,
      dataaccess : 1'b1,
      datasize   : dm::DataCount,
      dataaddr   : dm::DataAddr
   };

   dmi_jtag #(
      .IdcodeValue(32'h2495_11c3)
   ) dbg_dtm (
      .clk_i(clk),
      .rst_ni(reset_n),
      .testmode_i(1'b0),
      .dmi_rst_no(dbg_dmi_rst_n),
      .dmi_req_o(dbg_dmi_req),
      .dmi_req_valid_o(dbg_dmi_req_valid),
      .dmi_req_ready_i(dbg_dmi_req_ready),
      .dmi_resp_i(dbg_dmi_resp),
      .dmi_resp_ready_o(dbg_dmi_resp_ready),
      .dmi_resp_valid_i(dbg_dmi_resp_valid),
      .tck_i(dbg_tck),
      .tms_i(dbg_tms),
      .trst_ni(dbg_trst_n),
      .td_i(dbg_tdi),
      .td_o(dbg_tdo),
      .tdo_oe_o(dbg_tdo_oe)
   );

   dbg_dm_slave_bridge dbg_slave_bridge (
      .clk(clk),
      .rst(~reset_n),

      .i_req_valid(rw_flag_ & icache_req & if_dm_access),
      .i_req_kill(kill_icache_req),
      .i_req_addr(pc),
      .i_rsp_data(dbg_i_rsp_data),
      .i_rsp_pc(dbg_i_rsp_pc),
      .i_rsp_done(dbg_i_rsp_done),
      .i_busy(dbg_i_busy),

      .d_req_valid((|mmio_we) & mmio_dm_access),
      .d_req_we(mmio_we[1]),
      .d_req_addr(mmio_addr),
      .d_req_wdata(mmio_wdata[31:0]),
      .d_req_be(mmio_byteenable[3:0]),
      .d_rsp_rdata(dbg_d_rsp_rdata),
      .d_rsp_done(dbg_d_rsp_done),
      .d_busy(dbg_d_busy),

      .slave_req(dbg_slave_req),
      .slave_we(dbg_slave_we),
      .slave_addr(dbg_slave_addr),
      .slave_be(dbg_slave_be),
      .slave_wdata(dbg_slave_wdata),
      .slave_rdata(dbg_slave_rdata)
   );

   dbg_sba_mem_bridge dbg_sba_bridge (
      .clk(clk),
      .rst(~reset_n),

      .master_req(dbg_master_req & dbg_sba_accept),
      .master_addr(dbg_master_addr),
      .master_we(dbg_master_we),
      .master_wdata(dbg_master_wdata),
      .master_be(dbg_master_be),
      .master_gnt(dbg_master_gnt),
      .master_r_valid(dbg_master_r_valid),
      .master_r_err(dbg_master_r_err),
      .master_r_other_err(dbg_master_r_other_err),
      .master_rdata(dbg_master_rdata),

      .mem_req_addr(dbg_sba_mem_addr),
      .mem_req_data(dbg_sba_mem_wdata),
      .mem_req_byteenable(dbg_sba_mem_byteenable),
      .mem_req_rw(dbg_sba_mem_we),
      .mem_rsp_data(dbg_sba_mem_data),
      .mem_rsp_done(dbg_sba_mem_done)
   );

   dm_top #(
      .NrHarts(1),
      .BusWidth(`DATA_LEN),
      .DmBaseAddress(DM_BASE_ADDR),
      .SelectableHarts(1'b1),
      .ReadByteEnable(1'b1)
   ) dbg_dm (
      .clk_i(clk),
      .rst_ni(reset_n),
      .next_dm_addr_i(32'h0),
      .testmode_i(1'b0),
      .ndmreset_o(dbg_ndmreset),
      .ndmreset_ack_i(1'b0),
      .dmactive_o(dbg_dmactive),
      .debug_req_o(dbg_debug_req),
      .unavailable_i(1'b0),
      .hartinfo_i(dbg_hartinfo),
      .slave_req_i(dbg_slave_req),
      .slave_we_i(dbg_slave_we),
      .slave_addr_i(dbg_slave_addr),
      .slave_be_i(dbg_slave_be),
      .slave_wdata_i(dbg_slave_wdata),
      .slave_rdata_o(dbg_slave_rdata),
      .master_req_o(dbg_master_req),
      .master_add_o(dbg_master_addr),
      .master_we_o(dbg_master_we),
      .master_wdata_o(dbg_master_wdata),
      .master_be_o(dbg_master_be),
      .master_gnt_i(dbg_master_gnt),
      .master_r_valid_i(dbg_master_r_valid),
      .master_r_err_i(dbg_master_r_err),
      .master_r_other_err_i(dbg_master_r_other_err),
      .master_r_rdata_i(dbg_master_rdata),
      .dmi_rst_ni(dbg_dmi_rst_n),
      .dmi_req_valid_i(dbg_dmi_req_valid),
      .dmi_req_ready_o(dbg_dmi_req_ready),
      .dmi_req_i(dbg_dmi_req),
      .dmi_resp_valid_o(dbg_dmi_resp_valid),
      .dmi_resp_ready_i(dbg_dmi_resp_ready),
      .dmi_resp_o(dbg_dmi_resp)
   );

   assign s_reg_req.addr = mmio_addr[15:0];
   assign s_reg_req.write = mmio_we[1];
   assign s_reg_req.wdata = mmio_wdata;
   assign s_reg_req.wstrb = 4'b1111;
   assign s_reg_req.valid = (mmio_addr[31:16] == 16'h4000 && |mmio_we);

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
      .cpu_res_pc(pipe_cpu_res_pc),
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
      .mmio_data(dbg_d_rsp_done ? {96'h0, dbg_d_rsp_rdata} :
                 mmio_done ? mmio_data :
                 plic_done ? plic_data : s_reg_rsp.rdata),
      .mmio_done(dbg_d_rsp_done | mmio_done | plic_done | clint_done),

      .icache_done(icache_done[0] | dbg_i_rsp_done),
      .icache_busy(icache_busy | dbg_i_busy),
      .l2_clean_addr_start(l2_clean_addr_start),
      .l2_clean_addr(l2_clean_addr),
      .l2_clean_addr_done(l2_clean_addr_done),

      .dbg_haltreq(dbg_debug_req),
      .dbg_entry_pc(DEBUG_ROM_ENTRY),

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
      .mem_req_rw((mmio_dm_access || mmio_addr[31:16] == 16'h4000 ||
                   mmio_addr[31:16] == 16'h4001) ? 2'd0 : mmio_we),
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
      .mem_req_rw(ram_mem_we),
      .maddr(ram_mem_addr),
      .byteenable(ram_mem_byteenable),
      .write_data(ram_mem_wdata),
      .read_data(ram_mem_data),
      .mem_done(ram_mem_done)
            );

   always @ (posedge clk) begin
      if (!reset_n) begin
         ram_owner <= RAM_OWNER_NONE;
      end else begin
         case (ram_owner)
            RAM_OWNER_NONE: begin
               if (|l2_mem_we)
                  ram_owner <= RAM_OWNER_L2;
               else if (dbg_sba_ram_req)
                  ram_owner <= RAM_OWNER_SBA;
            end
            RAM_OWNER_L2: begin
               if (ram_mem_done)
                  ram_owner <= RAM_OWNER_NONE;
            end
            RAM_OWNER_SBA: begin
               if (ram_mem_done)
                  ram_owner <= RAM_OWNER_NONE;
            end
            default: ram_owner <= RAM_OWNER_NONE;
         endcase
      end
   end


   always @ (posedge clk) begin
      if (mmio_addr[31:16] == 16'h4000 && |mmio_we) begin
         clint_done <= 1;
      end
      else
         clint_done <= 0;

      if (mmio_addr[31:16] == 16'h4001 && |mmio_we) begin
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

    .we       ( (mmio_addr[31:16] == 16'h4001) ? mmio_we[1] : 1'b0 ), //write cycle
    .re       ( (mmio_addr[31:16] == 16'h4001) ? mmio_we[0] : 1'b0 ), //read cycle
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
        .cpu_req_valid(rw_flag_ & icache_req & ~if_dm_access),
        .cpu_req_kill(kill_icache_req),
        .invalidate_valid(il1_invalidate_valid),
        .invalidate_addr(il1_invalidate_addr),
        .invalidate_all(1'b0),
        .clean_start(1'b0),
        .clean_addr_start(1'b0),
        .clean_addr(32'h0),
        .clean_done(),
        .clean_addr_done(),

        .mem_data_data(imem_data),
        .mem_data_ready(imem_done),

        .mem_req_addr(imem_addr),
        .mem_req_data(imem_wdata),
        .mem_req_byteenable(imem_byteenable),
        .mem_req_rw(imem_we),
        //.mem_req_valid

        .cpu_res_pc(cpu_res_pc),
        .cpu_res_data(icache_idata),
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

      .clean_addr_start(l2_clean_addr_start),
      .clean_addr(l2_clean_addr),
      .clean_addr_done(l2_clean_addr_done),

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
