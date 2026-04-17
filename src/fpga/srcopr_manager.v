`include "constants.vh"
`default_nettype none
module sourceoperand_manager
  (
   input wire [`DATA_LEN-1:0]  arfdata,
   input wire 		       arf_busy,
   input wire 		       rrf_valid,
   input wire [`RRF_SEL-1:0]   rrftag,
   input wire [`DATA_LEN-1:0]  rrfdata,
   input wire [`RRF_SEL-1:0]   dst1_renamed,
   input wire 		       src_eq_dst1,
   input wire 		       src_eq_0,
   output wire [`DATA_LEN-1:0] src,
   output wire 		       rdy
   );

   wire [`DATA_LEN-1:0] src_;
   wire [1:0] sel;
/*
   assign src = src_eq_0 ? `DATA_LEN'b0 :
		src_eq_dst1 ? dst1_renamed :
		~arf_busy ? arfdata :
		rrf_valid ? rrfdata :
		rrftag;
*/
   assign src = src_eq_0 ? `DATA_LEN'b0 : src_;
   assign sel =
		src_eq_dst1 ? 2'b00 :
		~arf_busy   ? 2'b01 :
		rrf_valid   ? 2'b10 :
                      2'b11 ;

   assign rdy = src_eq_0 | (~src_eq_dst1 & (~arf_busy | rrf_valid));

   mux4 mux_(
    {26'd0,dst1_renamed},
	arfdata,
	rrfdata,
	{26'd0,rrftag},
	sel,
	src_);

endmodule // sourceoperand_manager
`default_nettype wire
