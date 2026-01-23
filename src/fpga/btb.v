`include "constants.vh"
`default_nettype none
module btb(
	   input wire 		            clk,
	   input wire 		            reset,
	   input wire  [`ADDR_LEN-1:0]  pc,
	   output wire 		            hit,
	   output wire 		            is_jmp,
	   output wire 		            have_br_jmp,
	   output wire [`ADDR_LEN-1:0]  jmpaddr,
	   input wire 		            we,
	   input wire  [`ADDR_LEN-1:0]  jmpsrc,
	   input wire  [`ADDR_LEN-1:0]  jmpdst,
       input wire  [11:0]           instype
	   );

   wire [`BTB_TAG_LEN-1:0] 	  tag_data;
   reg  [`BTB_IDX_NUM-1:0] 	  valid;
   wire [13:0]                btb_info;
   wire [`BTB_IDX_SEL-1:0] 	  raddr = pc[4+:`BTB_IDX_SEL];
   wire [`BTB_IDX_SEL-1:0] 	  waddr = jmpsrc[4+:`BTB_IDX_SEL];
   
   wire [2:0]  first_br_jmp_idx;
   // wire [2:0]  first_br_jmp_type;

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
   assign hit = hit_pre && (first_br_jmp_idx == btb_info[1:0]);

   fetch_packet_info fpi_btb(
        .pc_sel(pc[3:2]),
        .instype(btb_info[13-:12]),
        .is_jmp(is_jmp),
        .have_br_jmp(have_br_jmp),
        .first_br_jmp_idx(first_br_jmp_idx)
		// .first_br_jmp_type(first_br_jmp_type)
		);

   always @ (negedge clk) begin
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
      .rdata1(jmpaddr),
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
      .wdata({instype, jmpsrc[3:2]}),
      .we(we)
      );

endmodule // btb
`default_nettype wire
