`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. This ALU is a purely combinational block, so
// you should not attempt to add any registers or pipeline it.
module alu (
    // NOTE: Both 3'b010 and 3'b011 are used for set less than operations and
    // your implementation should output the same result for both codes. The
    // reason for this will become clear in project 3.
    //
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010,
    // 3'b011: set less than/unsigned if `i_unsigned` asserted
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is used for branch comparisons and set less than unsigned. For
    // b ranch operations, the ALU result is not used, only the comparison
    // results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_eq,
    // Set less than result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_slt
);
    // TODO: Fill in your implementation here.

    // Barrel shifter
    // Shift left
    wire [31:0] sl1 = i_op2[0] ? {i_op1[30:0], 1'b0} : i_op1;
    wire [31:0] sl2 = i_op2[1] ? {sl1[29:0], 2'b0} : sl1;
    wire [31:0] sl4 = i_op2[2] ? {sl2[27:0], 4'b0} : sl2;
    wire [31:0] sl8 = i_op2[3] ? {sl4[23:0], 8'b0} : sl4;
    wire [31:0] sl16 = i_op2[4] ? {sl8[15:0], 16'b0} : sl8;
    // Shift right
    wire [31:0] sr1 = i_op2[0] ? (i_arith ? {i_op1[31], i_op1[31:1]} : {1'b0, i_op1[31:1]}) : i_op1;
    wire [31:0] sr2 = i_op2[1] ? (i_arith ? {{2{sr1[31]}}, sr1[31:2]} : {2'b0, sr1[31:2]}) : sr1;
    wire [31:0] sr4 = i_op2[2] ? (i_arith ? {{4{sr2[31]}}, sr2[31:4]} : {4'b0, sr2[31:4]}) : sr2;
    wire [31:0] sr8 = i_op2[3] ? (i_arith ? {{8{sr4[31]}}, sr4[31:8]} : {8'b0, sr4[31:8]}) : sr4;
    wire [31:0] sr16 = i_op2[4] ? (i_arith ? {{16{sr8[31]}}, sr8[31:16]} : {16'b0, sr8[31:16]}) : sr8;

    // Operation selection
    assign o_result = (i_opsel == 3'b000) ? (i_sub ? (i_op1 - i_op2) : (i_op1 + i_op2)) :
                (i_opsel == 3'b001) ? sl16 :
                (i_opsel == 3'b010) ? {31'b0, o_slt} :
                (i_opsel == 3'b011) ? {31'b0, o_slt} :
                (i_opsel == 3'b100) ? i_op1 ^ i_op2 :
                (i_opsel == 3'b101) ? sr16 :
                (i_opsel == 3'b110) ? i_op1 | i_op2 :
                (i_opsel == 3'b111) ? i_op1 & i_op2 : 32'b0;

    // Equality logic
    assign o_eq = (i_op1 == i_op2);

    // SLT logic
    assign o_slt = i_unsigned ? (i_op1 < i_op2) : (i_op1[31] == i_op2[31]) ? (i_op1 < i_op2) : i_op1[31];


endmodule

`default_nettype wire
