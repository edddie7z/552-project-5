`default_nettype none

module fetch #(
    parameter RESET_ADDR = 32'h0000_0000
) (
    input wire i_clk,
    input wire i_rst,          
    input wire i_stall,
    input wire i_pc_set,
    input wire [31:0] i_pc_next,
    output wire [31:0] o_imem_raddr,
    input wire [31:0] i_imem_rdata,
    output wire [31:0] o_pc,
    output wire [31:0] o_inst,
    output wire o_pc_misaligned
);

    // PC reg
    reg [31:0] pc_q;

    // Fetch signals
    assign o_pc = pc_q;
    assign o_imem_raddr = pc_q;
    assign o_inst = i_imem_rdata;
    assign o_pc_misaligned = |pc_q[1:0];

    // Next PC logic
    wire [31:0] pc_plus4 = pc_q + 32'd4;
    wire [31:0] pc_next_comb = i_pc_set ? i_pc_next : pc_plus4;

    // Update PC
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc_q <= RESET_ADDR;
        end else if (!i_stall) begin
            // else hold pc_q
            pc_q <= pc_next_comb; 
        end
    end

endmodule

`default_nettype wire