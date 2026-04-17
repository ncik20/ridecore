`include "constants.vh"
`include "alu_ops.vh"
//`default_nettype none
module get_lddata
  (
   input wire   [1:0]                   staddr_offset,
   input wire   [`MEM_TYPE_WIDTH-1:0]   stfunct3,
   input wire   [`DATA_LEN-1:0]         stdata,
   input wire   [`DATA_LEN-1:0]         lddata,
   output reg   [`DATA_LEN-1:0]         out
   );

   always @ (*) begin
        out = 0;
	    case(stfunct3)
            3'b000:begin
	            case(staddr_offset)
			        2'b00:out = {lddata[31-:24], stdata[7:0]};

			        2'b01:out = {lddata[31-:16], stdata[7:0], lddata[7:0]};

			        2'b10:out = {lddata[31-:8], stdata[7:0], lddata[15:0]};

			        2'b11:out = {stdata[7:0], lddata[23:0]};
		        endcase
            end
            3'b001:begin
	            case(staddr_offset)
			        2'b00:out = {lddata[31-:16], stdata[15:0]};

			        2'b01:out = 32'h0; // TODO:go trap

			        2'b10:out = {stdata[15:0], lddata[15:0]};

			        2'b11:out = 32'h0; // TODO:go trap
		        endcase
            end
			3'b010:out = stdata;
		endcase
   end
endmodule

module ldst_byteenable
  (
   input wire   [1:0]                   addr_offset,
   input wire   [`MEM_TYPE_WIDTH-1:0]   funct3,
   input wire   [`DATA_LEN-1:0]         lddata,
   output reg   [`DATA_LEN-1:0]         out_data,
   output reg   [3:0]                   byteenable
   );

   always @ (*) begin
        out_data = 32'h0;
        byteenable = 4'b0000;
	    case(funct3)
            3'b000, 3'b100:begin
	            case(addr_offset)
                    2'b00:begin
                        byteenable = 4'b0001;
                        out_data = {24'h0, lddata[7-:8]};
                    end
                    2'b01:begin
                        byteenable = 4'b0010;
                        out_data = {24'h0, lddata[15-:8]};
                    end
                    2'b10:begin
                        byteenable = 4'b0100;
                        out_data = {24'h0, lddata[23-:8]};
                    end
                    2'b11:begin
                        byteenable = 4'b1000;
                        out_data = {24'h0, lddata[31-:8]};
                    end
	        	endcase
            end
            3'b001, 3'b101:begin
	            case(addr_offset)
                    2'b00:begin
                        byteenable = 4'b0011;
                        out_data = {16'h0, lddata[15-:16]};
                    end
                    2'b01:begin             // TODO:go trap
                        byteenable = 4'b0011;
                        out_data = {16'h0, lddata[15-:16]};
                    end
                    2'b10:begin
                        byteenable = 4'b1100;
                        out_data = {16'h0, lddata[31-:16]};
                    end
                    2'b11:begin             // TODO:go trap
                        byteenable = 4'b1100;
                        out_data = {16'h0, lddata[31-:16]};
                    end
	        	endcase
            end
            3'b010:begin
                byteenable = 4'b1111;
                out_data = lddata;
            end
		endcase
   end
endmodule

module exunit_ldst
  (
   input wire 			 clk,
   input wire 			 reset,
   input wire 			 irq_flush,
   input wire [`DATA_LEN-1:0] 	    ex_src1,
   input wire [`DATA_LEN-1:0] 	    ex_src2,
   input wire [`ADDR_LEN-1:0] 	    pc,
   input wire [`DATA_LEN-1:0] 	    imm,
   input wire [`MEM_TYPE_WIDTH-1:0] funct3, 
   input wire                       dstval,
   input wire [`SPECTAG_LEN-1:0]    spectag,
   input wire 			            specbit,
   input wire 			            issue,
   input wire 			            prmiss,
   input wire [`SPECTAG_LEN-1:0]    spectagfix,
   input wire [`RRF_SEL-1:0] 	    rrftag,
   output wire [`DATA_LEN-1:0] 	    result,
   output wire 			            rrf_we,
   output wire 			            rob_we, //set finish
   output wire [`RRF_SEL-1:0] 	    wrrftag,
   output wire                      kill_ld_req,
   output wire 			            kill_speculative,
   output wire 			            busy_next,
   //Signal dcache
   //input wire                       cache_busy,
   input wire                       cache_done,
   //output reg                       cache_req,
   //Signal StoreBuf
   output wire 			            stfin,
   //Store
   output wire 			            memoccupy_ld,
   input wire 			            fullsb,
   output wire [`DATA_LEN-1:0] 	    storedata,
   output wire [`ADDR_LEN-1:0] 	    storeaddr,
   //Load
   input wire 			            hitsb,
   input wire [1:0]                 hit_staddr_off,    // st时staddr的后2位
   input wire [`MEM_TYPE_WIDTH-1:0] ldfunct3,
   output wire [`ADDR_LEN-1:0] 	    ldaddr,
   input wire [`DATA_LEN-1:0] 	    lddatasb,
   input wire [4*`DATA_LEN-1:0] 	lddatamem
   );

   reg 				        busy;
   wire 			        clearbusy;
   wire [`ADDR_LEN-1:0]     effaddr;
   wire                     killspec1;
   wire                     must_read_mem;
   wire                     sb_ld_ok;
   wire                     ld_ok;
   wire                     ld_io;
   //wire [7:0]               result_lb;
   //wire [15:0]              result_lh;
   //wire [`DATA_LEN-1:0]     result_lw;
   wire [`DATA_LEN-1:0]     mem_data;
   wire [`DATA_LEN-1:0]     lddatasbmen;
   wire [`DATA_LEN-1:0]     lddata;
   wire [`DATA_LEN-1:0]     out_lddata;
   wire  [3:0]              ld_byteenable;
   wire  [3:0]              st_byteenable;
   wire  [3:0]              ldst_and;
   
   //LATCH
   reg 				                dstval_latch;
   //reg                              ld_io_latch;
   reg [`MEM_TYPE_WIDTH-1:0]        funct3_latch;
   reg [`RRF_SEL-1:0] 		        rrftag_latch;
   reg 				                specbit_latch;
   reg [`SPECTAG_LEN-1:0] 	        spectag_latch;
   //reg [1:0]                        ldaddr_offset_latch;
   //reg [`DATA_LEN-1:0] 		        lddatasb_latch;
   //reg [`DATA_LEN-1:0] 		        lddatamem_latch;
   //reg [`MEM_TYPE_WIDTH-1:0]        ldfunct3_latch;
   //reg 				                hitsb_latch;
   reg [`DATA_LEN-1:0] 		        out_lddata_latch;

   reg 				                insnvalid_latch; // ldst exec is done

   get_lddata getlddata(
       .staddr_offset(hit_staddr_off),
       .stfunct3(ldfunct3),
       .stdata(lddatasb),
       .lddata(sb_ld_ok ? 32'h0 : mem_data),
       .out(lddatasbmen)
   );

   ldst_byteenable ld(
       .addr_offset(ldaddr[1:0]),
       .funct3(funct3),
       .lddata(lddata),
       .out_data(out_lddata),
       .byteenable(ld_byteenable)
   );

   ldst_byteenable st(
       .addr_offset(hit_staddr_off),
       .funct3(ldfunct3),
       .byteenable(st_byteenable)
   );

   // assign clearbusy = (killspec1 || dstval || (~dstval && ~fullsb)) ? 1'b1 : 1'b0;

   //assign must_read_mem = (funct3 == 3'b010 && ldfunct3 != 3'b010) ||
   //    ((funct3 == 3'b001 || funct3 == 3'b101) && ldfunct3 == 3'b000) || ld_io;

   assign ldst_and = st_byteenable & ld_byteenable;

   assign must_read_mem = ((funct3 == 3'b000 || funct3 == 3'b100) && ~|ldst_and) ||
    ((funct3 == 3'b001 || funct3 == 3'b101) && ldst_and != 4'b1100 && ldst_and != 4'b0011) ||
    (funct3 == 3'b010 && ldst_and != 4'b1111) || ld_io;

   assign sb_ld_ok = hitsb && ~must_read_mem;

   //assign lddata = sb_ld_ok ? lddatasb : (ld_io || ~hitsb) ? mem_data : lddatasbmen;
   assign lddata = (ld_io || ~hitsb) ? mem_data : lddatasbmen;

   assign ld_ok = dstval && (sb_ld_ok || cache_done);
   assign clearbusy = (killspec1 || ld_ok || (~dstval && ~fullsb)) ? 1'b1 : 1'b0;
   assign killspec1 = ((spectag & spectagfix) != 0) && specbit && prmiss;
   assign kill_speculative = ((spectag_latch & spectagfix) != 0) && specbit_latch && prmiss;
   assign kill_ld_req = busy && killspec1;
   //assign result_lb = (hitsb_latch && ~ld_io_latch) ? lddatasb_latch[7:0] :
   //    lddatamem_latch[7:0];

   //assign result_lh = (~hitsb_latch || ld_io_latch) ? lddatamem_latch[15:0] :
   //    (ldfunct3_latch == 3'b000) ? {lddatamem_latch[15:8], lddatasb_latch[7:0]} :
   //    lddatasb_latch[15:0];

   //assign result_lw = (~hitsb_latch || ld_io_latch) ? lddatamem_latch :
   //    (ldfunct3_latch == 3'b000) ? st_b_out :
   //    (ldfunct3_latch == 3'b001) ? st_h_out :
   //    lddatasb_latch;

   assign result = (funct3_latch == 3'b000) ? {{24{out_lddata_latch[7]}}, out_lddata_latch[7:0]} :
       (funct3_latch == 3'b100) ? {24'h0, out_lddata_latch[7:0]} :
       (funct3_latch == 3'b001) ? {{16{out_lddata_latch[15]}}, out_lddata_latch[15:0]} :
       (funct3_latch == 3'b101) ? {16'h0, out_lddata_latch[15:0]} : out_lddata_latch;

   assign rrf_we = dstval_latch & insnvalid_latch;
   assign rob_we = insnvalid_latch;
   assign wrrftag = rrftag_latch;
   assign busy_next = clearbusy ? 1'b0 : busy;
   // stfin如果fullsb了，就一直是真，不会导致sb里的finptr一直自增？
   // assign stfin = ~killspec1 & busy & ~dstval;
   assign stfin = ~killspec1 & busy & ~dstval & ~fullsb;
   // load的时候，写dmem，可能因为storebuffer的valid置0导致找不到，从dmem取，又因为store的值还未写入dmem，导致load取到旧值
   // 上面这个写的什么意思？
   // 非load写dmem，也是以写dmem只需1个cycle为前提，实际写下级存储，要考虑大于1cycle的情况
   // 上面这个，的确要考虑
   // 在sb数据写入dcache的stage2开始，在sb就查不到该数据，但此时，还并未写入dcache
   // 中，此时如果正好有ld在请求该数据，应该考虑直接返回该数据
   assign memoccupy_ld = ~killspec1 & busy & dstval & ~sb_ld_ok;
   assign storedata = ex_src2;
   assign storeaddr = effaddr;
   assign ldaddr = effaddr;
   assign effaddr = ex_src1 + imm;
   assign ld_io = ldaddr[30]; //ldaddr >= 32'h4000_0000
   assign mem_data = ld_io ? lddatamem[31-: 32] :
       (ldaddr[3:2] == 2'b00) ? lddatamem[31-: 32] :
       (ldaddr[3:2] == 2'b01) ? lddatamem[63-: 32] :
       (ldaddr[3:2] == 2'b10) ? lddatamem[95-: 32] : lddatamem[127-:32];

   always @ (posedge clk) begin
      if (reset || killspec1 || ~busy || (~dstval && fullsb)) begin
	 dstval_latch <= 0;
     //ld_io_latch <= 0;
     funct3_latch <= 0;
	 rrftag_latch <= 0;
	 specbit_latch <= 0;
	 spectag_latch <= 0;
     //ldaddr_offset_latch <= 0;
	 //lddatasb_latch <= 0;
     //lddatamem_latch <= 0;
     //ldfunct3_latch <= 0;
	 //hitsb_latch <= 0;
     out_lddata_latch <= 0;
	 insnvalid_latch <= 0;
      end else begin
	 dstval_latch <= dstval;
     //ld_io_latch <= ld_io;
     funct3_latch <= funct3;
	 rrftag_latch <= rrftag;
	 specbit_latch <= specbit;
	 spectag_latch <= spectag;
     //ldaddr_offset_latch <= ldaddr[1:0];
	 //lddatasb_latch <= lddatasb;
     //lddatamem_latch <= mem_data;
     //ldfunct3_latch <= ldfunct3;
	 //hitsb_latch <= hitsb;
     out_lddata_latch <= out_lddata;
	 insnvalid_latch <= ~killspec1 & ((busy & ld_ok) |
					  (busy & ~dstval & ~fullsb));
	 // insnvalid_latch <= ~killspec1 & ((busy & dstval) |
	 //				  (busy & ~dstval & ~fullsb));
      end
   end // always @ (posedge clk)

   always @ (posedge clk) begin
      if (reset || killspec1 || irq_flush) begin
        busy <= 0;
      end else begin
        busy <= issue | busy_next;
      end
   end

endmodule // exunit_ldst

//`default_nettype none
