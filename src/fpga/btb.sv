`include "constants.vh"
`default_nettype none
module btb(
	   input wire 		            clk,
	   input wire 		            reset,
	   input wire [`ADDR_LEN-1:0]   pc,
	   output wire 		            hit,
	   output wire 		            is_jmp,
	   output wire 		            have_br_jmp,
	   output wire [`ADDR_LEN-1:0]  jmpaddr,
	   input wire 		            we,
	   input wire [`ADDR_LEN-1:0]   jmpsrc,
	   input wire [`ADDR_LEN-1:0]   jmpdst,
       input wire [11:0]            pc_fetch_info,
       output wire [29:0]           ras_backup,
       output wire [3:0]            rasPtr_backup,
       input wire 			        prmiss,
       input wire [29:0]            prmiss_ras,
       input wire [3:0]             prmiss_rasPtr
	   );
   reg  [29:0]                ras[0:`RAS_NUM-1];
   reg  [7:0]                 sameAddrCnt[0:`RAS_NUM-1];
   reg  [3:0]                 rasPtr;
   wire [3:0]                 rasRdPtr = rasPtr - 1;

   wire [`ADDR_LEN-1:0]       branch_jmpdst;
   wire [`ADDR_LEN-1:0]       ret_addr;

   wire [`BTB_TAG_LEN-1:0] 	  tag_data;
   reg  [`BTB_IDX_NUM-1:0] 	  valid;
   wire [13:0]                btb_info;
   wire [`BTB_IDX_SEL-1:0] 	  raddr = pc[4+:`BTB_IDX_SEL];
   wire [`BTB_IDX_SEL-1:0] 	  waddr = jmpsrc[4+:`BTB_IDX_SEL];

   wire [2:0]  first_br_jmp_idx;
   wire [2:0]  first_br_jmp_type;
   wire [29:0] retaddr;

   wire hit_pre = ((tag_data == pc[`ADDR_LEN-1:4+`BTB_IDX_SEL]) &&
       valid[pc[4+:`BTB_IDX_SEL]]) ? 1'b1 : 1'b0;

   /*
    0:normal
    1:branch
    2:jal
    3:jalr
    4:call
    5:ret
    6:ret then call
   */
   wire do_popup = (first_br_jmp_type == 3'd5 && sameAddrCnt[rasRdPtr] != 0);

   assign hit = hit_pre && ((first_br_jmp_idx == btb_info[1:0]) || do_popup);

   assign jmpaddr = do_popup ? {ras[rasRdPtr], 2'b00} : branch_jmpdst;

   assign retaddr = {pc[31:4], first_br_jmp_idx[1:0]} + 1;

   assign ras_backup = ras[rasRdPtr];
   assign rasPtr_backup = rasPtr;

   fetch_packet_info fpi_btb(
        .pc_sel(pc[3:2]),
        .instype(btb_info[13-:12]),
        .is_jmp(is_jmp),
        .have_br_jmp(have_br_jmp),
        .first_br_jmp_idx(first_br_jmp_idx),
		.first_br_jmp_type(first_br_jmp_type)
		);

   integer i;
   always_ff @(posedge clk) begin
      if (reset) begin
         rasPtr <= 0;

         for (int i=0; i<`RAS_NUM; i++) begin
             sameAddrCnt[i] <= 0;
         end
      end else if (prmiss) begin
         ras[prmiss_rasPtr - 1] <= prmiss_ras;
         rasPtr <= prmiss_rasPtr;
      end else begin
         // push
         if (first_br_jmp_type == 3'd4) begin
            if (ras[rasRdPtr] == retaddr) begin
                sameAddrCnt[rasRdPtr] <= sameAddrCnt[rasRdPtr] + 1;
            end else begin
                ras[rasPtr] <= retaddr;
                sameAddrCnt[rasPtr] <= 8'd1;
                rasPtr <= rasPtr + 1;
            end
         // popup
         end else if (do_popup) begin
            sameAddrCnt[rasRdPtr] <= sameAddrCnt[rasRdPtr] - 1;
            if (sameAddrCnt[rasRdPtr] == 8'd1)
                rasPtr <= rasPtr - 1;
         end
      end
   end

   always_ff @(negedge clk) begin
      if (reset) begin
         valid <= 0;
      end else begin
         if (we) begin
            valid[waddr] <= 1'b1;
         end
      end
   end

   ram_sync_1r1w #(`BTB_IDX_SEL, `BTB_TAG_LEN, `BTB_IDX_NUM) bia
     (
      .clk(~clk),
      .raddr1(raddr),
      .rdata1(tag_data),
      .waddr(waddr),
      .wdata(jmpsrc[`ADDR_LEN-1:4+`BTB_IDX_SEL]),
      // .wdata(jmpsrc),
      .we(we)
      );
   
   // TODO：考虑commit的指令是ret的话，不写jmpdst？
   ram_sync_1r1w #(`BTB_IDX_SEL, `ADDR_LEN, `BTB_IDX_NUM) bta
     (
      .clk(~clk),
      .raddr1(raddr),
      .rdata1(branch_jmpdst),
      .waddr(waddr),
      .wdata(jmpdst),
      .we(we)
      );

   // 每条指令的类型12bit+jmpsrc[3:2]2bit
   ram_sync_1r1w #(`BTB_IDX_SEL, 14, `BTB_IDX_NUM) pc_info
     (
      .clk(~clk),
      .raddr1(raddr),
      .rdata1(btb_info),
      .waddr(waddr),
      .wdata({pc_fetch_info, jmpsrc[3:2]}),
      .we(we)
      );

endmodule // btb
`default_nettype wire
