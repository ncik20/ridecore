`include "constants.vh"

module storebuf
  (
   input wire 			 clk,
   input wire 			 reset,
   input wire            irq_flush,
   input wire 			 prsuccess,
   input wire 			 prmiss,
   input wire [`SPECTAG_LEN-1:0] prtag,
   input wire [`SPECTAG_LEN-1:0] spectagfix,
   input wire 			 stfin,
   input wire 			 stspecbit,
   input wire [`SPECTAG_LEN-1:0] stspectag,
   input wire [`DATA_LEN-1:0] 	 stdata,
   input wire [`ADDR_LEN-1:0] 	 staddr,
   input wire [`MEM_TYPE_WIDTH-1:0] 					 stfunct3,
   input wire 			 stcom,
   output wire 			 stretire, //dmem_we
   output wire [`DATA_LEN-1:0] 	 retdata,
   output wire [`ADDR_LEN-1:0] 	 retaddr,
   output wire [`MEM_TYPE_WIDTH-1:0] 				 retfunct3,
   input wire 			 memoccupy_ld,
   output wire 			 sb_full,
   //ReadSigs
   input wire[1:0] dmem_w_done,
   input wire cache_busy,
   input wire [`ADDR_LEN-1:0] 	 ldaddr,
   output wire [`DATA_LEN-1:0] 	 lddata,
   output wire [`MEM_TYPE_WIDTH-1:0]    ldfunct3,
   output wire 			 hit
   );

   reg [`STBUF_ENT_SEL-1:0] 	 finptr;
   reg [`STBUF_ENT_SEL-1:0] 	 comptr;
   reg [`STBUF_ENT_SEL-1:0] 	 retptr;
   
   reg [`SPECTAG_LEN-1:0] 	 spectag [0:`STBUF_ENT_NUM-1];
   reg [`STBUF_ENT_NUM-1:0] 	 completed;
   reg [`STBUF_ENT_NUM-1:0] 	 valid;
   reg [`STBUF_ENT_NUM-1:0] 	 specbit;
   reg [`DATA_LEN-1:0] 			 data [0:`STBUF_ENT_NUM-1];
   reg [`ADDR_LEN-1:0] 			 addr [0:`STBUF_ENT_NUM-1];
   reg [`MEM_TYPE_WIDTH-1:0] 	 funct3 [0:`STBUF_ENT_NUM-1];
   wire [`STBUF_ENT_NUM-1:0] 	 completed_new;

   //when prsuccess, specbit_next = specbit & specbitcls
   wire [`STBUF_ENT_NUM-1:0] 	 specbit_cls;
   wire [`STBUF_ENT_NUM-1:0] 	 valid_cls;
   wire 			 notfull_next;
   wire 			 notempty_next;
   wire [`STBUF_ENT_SEL-1:0] 	 nb1;
   wire [`STBUF_ENT_SEL-1:0] 	 ne1;
   wire [`STBUF_ENT_SEL-1:0] 	 nb0;
   wire [`STBUF_ENT_SEL-1:0] 	 finptr_next;
   //For CAM with Priority
   wire [`STBUF_ENT_NUM-1:0] 	 hitvec;
   wire [2*`STBUF_ENT_NUM-1:0] 	 hitvec_rot;
   wire [`STBUF_ENT_SEL-1:0] 	 ldent_rot;
   wire [`STBUF_ENT_SEL-1:0] 	 ldent;
   wire [`STBUF_ENT_SEL-1:0] 	 vecshamt;
   
   search_begin #(`STBUF_ENT_SEL, `STBUF_ENT_NUM) 
   snb1(
	.in(valid & valid_cls),
	.out(nb1),
	.en()
	);
   
   search_end #(`STBUF_ENT_SEL, `STBUF_ENT_NUM) 
   sne1(
	.in(valid & valid_cls),
	.out(ne1),
	.en(notempty_next)
	);

   search_begin #(`STBUF_ENT_SEL, `STBUF_ENT_NUM) 
   snb0(
	.in(~(valid & valid_cls)),
	.out(nb0),
	.en(notfull_next)
	);

   search_end #(`STBUF_ENT_SEL, `STBUF_ENT_NUM)
   findhitent(
	      .in(hitvec_rot[2*`STBUF_ENT_NUM-1:`STBUF_ENT_NUM]),
	      .out(ldent_rot),
	      .en(hit)
	      );
   
   assign retdata = data[retptr];
   assign retaddr = addr[retptr];
   assign retfunct3 = funct3[retptr];
   assign lddata = data[ldent];
   assign ldfunct3 = funct3[ldent];
   assign stretire = valid[retptr] && completed[retptr] && ~(dmem_w_done[1]) && ~prmiss;
   assign sb_full = ((finptr == retptr) && (valid[finptr] == 1)) ? 1'b1 : 1'b0;
   assign finptr_next = (~notfull_next | ~notempty_next) ? finptr :
			(((nb1 == 0) && (ne1 == `STBUF_ENT_NUM-1)) ? nb0 : (ne1+1));
   assign vecshamt = (`STBUF_ENT_NUM - finptr);
   assign hitvec_rot = {hitvec, hitvec} << vecshamt;
   assign ldent = ldent_rot + finptr;
   
   generate
      genvar 			 i;
      for (i = 0 ; i < `STBUF_ENT_NUM ; i = i + 1) 
	begin: L1
	   assign specbit_cls[i] = (prtag == spectag[i]) ? 1'b0 : 1'b1;
	   assign valid_cls[i] = (specbit[i] && ((spectagfix & spectag[i]) != 0)) ? 
				 1'b0 : 1'b1;
	   assign hitvec[i] = (valid[i] && (addr[i] == ldaddr)) ? 1'b1 : 1'b0;
	end
   endgenerate

   generate
      genvar 			 j;
      for (j = 0 ; j < `STBUF_ENT_NUM ; j = j + 1) 
	begin: L2
	   assign completed_new[j] = (j == comptr) ? 1'b1 : completed[j];
	end
   endgenerate

   always @ (posedge clk) begin
      if (~reset & stfin) begin
	 data[finptr] <= stdata;
	 addr[finptr] <= staddr;
	 funct3[finptr] <= stfunct3;
	 spectag[finptr] <= stspectag;
      end
   end

   always @ (posedge clk) begin
      if (reset) begin
	 finptr <= 0;
	 comptr <= 0;
	 retptr <= 0;
	 valid <= 0;
	 completed <= 0;
      end else if (irq_flush) begin
	    if (stcom) begin
	        valid <= valid & completed_new;
	        completed[comptr] <= 1'b1;

	        comptr <= comptr + 1;
            finptr <= comptr + 1;
        end else begin
	        valid <= valid & completed;
            finptr <= comptr;
        end
      end else if (prmiss) begin
	 if (stfin) begin
	    //KillNotOccur!!!
	    finptr <= finptr + 1;
	    valid[finptr] <= 1'b1;
	    completed[finptr] <= 1'b0;
	    comptr <= comptr;
	    retptr <= retptr;
	 end else begin
	    valid <= valid & valid_cls;
	    finptr <= finptr_next;
	    comptr <= ~notempty_next ? finptr : comptr;
	    retptr <= ~notempty_next ? finptr : retptr;
	 end
      end else begin
	 if (stfin) begin
	    finptr <= finptr + 1;
	    valid[finptr] <= 1'b1;
	    completed[finptr] <= 1'b0;
	 end
	 if (stcom) begin
	    comptr <= comptr + 1;
	    completed[comptr] <= 1'b1;
	 end

     //if (dcache.cpu_res_ready) begin
     // 如果此时发生prmiss，这样dmem_w_done[1]就错过了，不会有问题？
     // 是不是就会再申请一次写入？
     // 好像是的
	 if (dmem_w_done[1]) begin
	    retptr <= retptr + 1;
	    valid[retptr] <= 1'b0;
	    completed[retptr] <= 1'b0;
	 end
      end
   end // always @ (posedge clk)
/*
   always @ (posedge stretire) begin
    st_start <= 1;
   end

   always @ (posedge dmem_w_done) begin
    st_start <= 0;
   end*/

   always @ (posedge clk) begin
      if (reset | prmiss) begin
	 specbit <= 0;
      end else if (prsuccess) begin
	 specbit <= (specbit & specbit_cls) |
		    (stfin ? 
		     ({`STBUF_ENT_NUM{stspecbit}} << finptr) : 
		     `STBUF_ENT_NUM'b0);
      end else begin
	 if (stfin) begin
	    specbit[finptr] <= stspecbit;
	 end
      end
   end
endmodule // storebuf
