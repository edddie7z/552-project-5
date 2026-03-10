`default_nettype none

module execute (
    input wire [31:0] i_rs1_data,
    input wire [31:0] i_rs2_data,
    input wire [31:0] i_immediate,
    input wire [31:0] i_pc,
    input wire [2:0] i_alu_op,
    input wire i_alu_sub,
    input wire i_alu_unsigned,
    input wire i_alu_arith,
    input wire i_alu_src,
    input wire i_alu_pc,
    input wire i_branch,
    input wire i_jump,
    input wire i_is_jalr,
    input wire [2:0] i_branch_op,
    output wire [31:0] o_alu_result,
    output wire [31:0] o_branch_target,
    output wire o_pc_set,
    output wire o_target_misaligned
);

    // ALU op muxes
    wire [31:0] alu_op1 = i_alu_pc ? i_pc : i_rs1_data;
    wire [31:0] alu_op2 = i_alu_src ? i_immediate : i_rs2_data;

    wire alu_eq, alu_slt;

    // ALU module
    alu ALU (
        .i_opsel(i_alu_op),
        .i_sub(i_alu_sub),
        .i_unsigned(i_alu_unsigned),
        .i_arith(i_alu_arith),
        .i_op1(alu_op1),
        .i_op2(alu_op2),
        .o_result(o_alu_result),
        .o_eq(alu_eq),
        .o_slt(alu_slt)
    );

    reg branch_taken;
    always @(*) begin
        case (i_branch_op)
            3'b000: branch_taken = alu_eq; // BEQ
            3'b001: branch_taken = ~alu_eq; // BNE
            3'b100: branch_taken = alu_slt; // BLT
            3'b101: branch_taken = ~alu_slt; // BGE
            3'b110: branch_taken = alu_slt; // BLTU
            3'b111: branch_taken = ~alu_slt; // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    assign o_pc_set = (i_branch & branch_taken) | i_jump;

    // JALR base is rs1, JAL/branch base is PC
    wire [31:0] branch_base = i_is_jalr ? i_rs1_data : i_pc;
    wire [31:0] target_raw = branch_base + i_immediate;
    assign o_branch_target = i_is_jalr ? {target_raw[31:1], 1'b0} : target_raw;
    assign o_target_misaligned = |o_branch_target[1:0];

endmodule

`default_nettype wire
