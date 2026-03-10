`default_nettype none

module decode (
    input wire [31:0] i_inst,
    output wire [4:0] o_rs1_addr,
    output wire [4:0] o_rs2_addr,
    output wire [4:0] o_rd_addr,
    output wire [5:0] o_imm_format,
    output wire [2:0] o_alu_op,
    output wire o_alu_sub,
    output wire o_alu_unsigned,
    output wire o_alu_arith,
    output wire o_alu_src,
    output wire o_alu_pc,
    output wire o_mem_ren,
    output wire o_mem_wen,
    output wire [2:0] o_mem_op,
    output wire [1:0] o_wb_sel,
    output wire o_reg_wen,
    output wire o_branch,
    output wire o_jump,
    output wire o_is_jalr,
    output wire [2:0] o_branch_op,
    output wire o_halt,
    output wire o_trap,
    output wire o_uses_rs1,
    output wire o_uses_rs2
);


    // Instr fields
    wire [6:0] opcode = i_inst[6:0];
    wire [2:0] funct3 = i_inst[14:12];
    wire [6:0] funct7 = i_inst[31:25];

    assign o_rs1_addr = i_inst[19:15];
    assign o_rs2_addr = i_inst[24:20];
    assign o_rd_addr = i_inst[11:7];

    wire op_r_type = (opcode == 7'b0110011);
    wire op_i_alu = (opcode == 7'b0010011);
    wire op_load = (opcode == 7'b0000011);
    wire op_store = (opcode == 7'b0100011);
    wire op_branch = (opcode == 7'b1100011);
    wire op_lui = (opcode == 7'b0110111);
    wire op_auipc = (opcode == 7'b0010111);
    wire op_jal = (opcode == 7'b1101111);
    wire op_jalr = (opcode == 7'b1100111);
    wire op_system = (opcode == 7'b1110011); 

    // Check valid 
    wire op_valid = op_r_type | op_i_alu | op_load | op_store
                  | op_branch | op_lui | op_auipc
                  | op_jal | op_jalr | op_system;

    // imm format 
    assign o_imm_format[0] = op_r_type;
    assign o_imm_format[1] = op_i_alu | op_load | op_jalr;
    assign o_imm_format[2] = op_store;
    assign o_imm_format[3] = op_branch;
    assign o_imm_format[4] = op_lui | op_auipc;
    assign o_imm_format[5] = op_jal;

    // R/I-type use funct3 
    assign o_alu_op = (op_r_type | op_i_alu) ? funct3 : 3'b000;

    // SUB only for R-type
    assign o_alu_sub = op_r_type & funct7[5] & (funct3 == 3'b000);

    // SLTU/SLTIU
    assign o_alu_unsigned = ((op_r_type | op_i_alu) & (funct3 == 3'b011));

    // SRA/SRAI
    assign o_alu_arith = ((op_r_type | op_i_alu) & (funct3 == 3'b101) & funct7[5]);

    // branches and R-type use rs2 as op2, else immediate
    assign o_alu_src = op_i_alu | op_load | op_store | op_auipc | op_lui;
    assign o_alu_pc = op_auipc;

    assign o_mem_ren = op_load;
    assign o_mem_wen = op_store;
    assign o_mem_op = funct3; 

    assign o_wb_sel = op_load ? 2'b01 :
                      (op_jal | op_jalr) ? 2'b10 :
                      op_lui ? 2'b11 : 2'b00;

    assign o_reg_wen = op_r_type | op_i_alu | op_load | op_lui
                     | op_auipc | op_jal   | op_jalr;

    assign o_branch = op_branch;
    assign o_jump = op_jal | op_jalr;
    assign o_is_jalr = op_jalr;
    assign o_branch_op = funct3;

    assign o_halt = op_system & (funct3 == 3'b000) & i_inst[20];
    assign o_trap = ~op_valid;

    assign o_uses_rs1 = op_r_type | op_i_alu | op_load | op_store
                      | op_branch | op_jalr;
    assign o_uses_rs2 = op_r_type | op_store | op_branch;

endmodule

`default_nettype wire
