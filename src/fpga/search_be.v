
module search_begin #(
		      parameter ENTSEL = 2,
		      parameter ENTNUM = 4
		     )
  (
   input wire [ENTNUM-1:0] in,
   output reg [ENTSEL-1:0] out,
   output reg 		   en
   );

   integer 		   i;
   always @ (*) begin
      out = 0;
      en = 0;
      for (i = ENTNUM-1; i >= 0 ; i = i - 1) begin
	 if (in[i]) begin
	    out = i;
	    en = 1;
	 end
      end
   end
   
endmodule // search_from_top
			 // 注意！in[i]=1后，并不会跳出for循环，会找到最后一个in[i]=1的i
			 // 所以是从高位开始找，低位符合的

module search_end #(
		    parameter ENTSEL = 2,
		    parameter ENTNUM = 4
		    )
   (
    input wire [ENTNUM-1:0] in,
    output reg [ENTSEL-1:0] out,
    output reg 		    en
   );

   integer 		   i;
   always @ (*) begin
      out = 0;
      en = 0;
      for (i = 0 ; i < ENTNUM ; i = i + 1) begin
	 if (in[i]) begin
	    out = i;
	    en = 1;
	 end
      end
   end

endmodule // search_from_bottom
