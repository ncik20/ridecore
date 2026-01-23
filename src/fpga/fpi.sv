`default_nettype none
module fetch_packet_info(
    input  wire [1:0]       pc_sel,
    input  wire [11:0]      instype,
    output wire			    is_jmp,
    output wire			    have_br_jmp,
    output reg	[2:0]		first_br_jmp_idx,
    output reg	[2:0]		first_br_jmp_type
    );

   wire [11:0] inst_type_valid = (pc_sel == 2'b00) ? instype :
                                 (pc_sel == 2'b01) ? {instype[11-:9], 3'h0} :
                                 (pc_sel == 2'b10) ? {instype[11-:6], 6'h0} :
                                                     {instype[11-:3], 9'h0};

   assign have_br_jmp = (first_br_jmp_idx != 3'd7);
   assign is_jmp = (have_br_jmp && first_br_jmp_type != 3'd1) ? 1'b1 : 1'b0;

   always_comb begin

      first_br_jmp_idx = 3'd7;
      first_br_jmp_type = 3'd0;

      if (inst_type_valid[2-:3] != 3'd0) begin
          first_br_jmp_idx = 3'd0;
          first_br_jmp_type = inst_type_valid[2-:3];

      end else if (inst_type_valid[5-:3] != 3'd0) begin
          first_br_jmp_idx = 3'd1;
          first_br_jmp_type = inst_type_valid[5-:3];

      end else if (inst_type_valid[8-:3] != 3'd0) begin
          first_br_jmp_idx = 3'd2;
          first_br_jmp_type = inst_type_valid[8-:3];

      end else if (inst_type_valid[11-:3] != 3'd0) begin
          first_br_jmp_idx = 3'd3;
          first_br_jmp_type = inst_type_valid[11-:3];
      end
   end
endmodule // fetch_packet_info
`default_nettype wire
