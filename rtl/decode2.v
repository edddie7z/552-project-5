`default_nettype none

module decode2 #(
    parameter RF_BYPASS_EN = 0
) (
    input  wire        i_clk,
    input  wire        i_rst,

    input  wire [31:0] i_inst,
    input  wire [31:0] i_pc,

    // Writeback into RF (from hart)
    input  wire        i_wb_wen,
    input  wire [ 4:0] i_wb_waddr,
    input  wire [31:0] i_wb_wdata,

    // Register addresses/data
    output wire [ 4:0] o_rs1_raddr,
    output wire [ 4:0] o_rs2_raddr,
    output wire [ 4:0] o_rd_waddr,
    output wire [31:0] o_rs1_rdata,
    output wire [31:0] o_rs2_rdata,

    // Immediate + format (one-hot [R,I,S,B,U,J])
    output wire [31:0] o_imm,
    output wire [ 5:0] o_imm_format,

    // Operand selection
    // op1_sel: 00=rs1, 01=pc, 10=zero
    // op2_sel_imm: 0=rs2, 1=imm
    output wire [ 1:0] o_op1_sel,
    output wire        o_op2_sel_imm,

    // ALU control (to alu.v)
    output wire [ 2:0] o_alu_opsel,
    output wire        o_alu_sub,
    output wire        o_alu_unsigned,
    output wire        o_alu_arith,

    // Memory controls
    output wire        o_mem_ren,
    output wire        o_mem_wen,
    output wire [ 2:0] o_mem_funct3,

    // Writeback controls
    // wb_sel: 00=ALU, 01=MEM, 10=PC+4, 11=IMM
    output wire        o_reg_wen,
    output wire [ 1:0] o_wb_sel,

    // Control-flow flags
    output wire        o_is_branch,
    output wire        o_is_jal,
    output wire        o_is_jalr,
    output wire [ 2:0] o_branch_funct3,

    // System/halts/traps
    output wire        o_is_ebreak,
    output wire        o_illegal
);

    // ----------------------------
    // Instruction fields (RV32I)
    // ----------------------------
    wire [6:0] opcode = i_inst[6:0];
    wire [4:0] rd     = i_inst[11:7];
    wire [2:0] funct3 = i_inst[14:12];
    wire [4:0] rs1    = i_inst[19:15];
    wire [4:0] rs2    = i_inst[24:20];
    wire [6:0] funct7 = i_inst[31:25];

    assign o_rs1_raddr = rs1;
    assign o_rs2_raddr = rs2;
    assign o_rd_waddr  = rd;

    // ----------------------------
    // Register file
    // ----------------------------
    rf #(
        .BYPASS_EN(RF_BYPASS_EN)
    ) u_rf (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_rs1_raddr(rs1),
        .o_rs1_rdata(o_rs1_rdata),
        .i_rs2_raddr(rs2),
        .o_rs2_rdata(o_rs2_rdata),
        .i_rd_wen(i_wb_wen),
        .i_rd_waddr(i_wb_waddr),
        .i_rd_wdata(i_wb_wdata)
    );

    // ----------------------------
    // Immediate generator
    // ----------------------------
    // One-hot: [0]=R, [1]=I, [2]=S, [3]=B, [4]=U, [5]=J
    reg [5:0] fmt;

    imm u_imm (
        .i_inst(i_inst),
        .i_format(fmt),
        .o_immediate(o_imm)
    );

    assign o_imm_format = fmt;

    // ----------------------------
    // Control regs -> outputs
    // ----------------------------
    reg [1:0] op1_sel;
    reg       op2_sel_imm;

    reg [2:0] alu_opsel;
    reg       alu_sub;
    reg       alu_unsigned;
    reg       alu_arith;

    reg       mem_ren, mem_wen;
    reg [2:0] mem_funct3;

    reg       reg_wen;
    reg [1:0] wb_sel;

    reg       is_branch, is_jal, is_jalr;
    reg [2:0] branch_funct3;

    reg       is_ebreak;
    reg       illegal;

    assign o_op1_sel        = op1_sel;
    assign o_op2_sel_imm    = op2_sel_imm;

    assign o_alu_opsel      = alu_opsel;
    assign o_alu_sub        = alu_sub;
    assign o_alu_unsigned   = alu_unsigned;
    assign o_alu_arith      = alu_arith;

    assign o_mem_ren        = mem_ren;
    assign o_mem_wen        = mem_wen;
    assign o_mem_funct3     = mem_funct3;

    assign o_reg_wen        = reg_wen;
    assign o_wb_sel         = wb_sel;

    assign o_is_branch      = is_branch;
    assign o_is_jal         = is_jal;
    assign o_is_jalr        = is_jalr;
    assign o_branch_funct3  = branch_funct3;

    assign o_is_ebreak      = is_ebreak;
    assign o_illegal        = illegal;

    // ----------------------------
    // Opcode constants (Verilog localparam)
    // ----------------------------
    localparam [6:0] OPC_LUI    = 7'b0110111;
    localparam [6:0] OPC_AUIPC  = 7'b0010111;
    localparam [6:0] OPC_JAL    = 7'b1101111;
    localparam [6:0] OPC_JALR   = 7'b1100111;
    localparam [6:0] OPC_BRANCH = 7'b1100011;
    localparam [6:0] OPC_LOAD   = 7'b0000011;
    localparam [6:0] OPC_STORE  = 7'b0100011;
    localparam [6:0] OPC_OPIMM  = 7'b0010011;
    localparam [6:0] OPC_OP     = 7'b0110011;
    localparam [6:0] OPC_SYSTEM = 7'b1110011;

    // ----------------------------
    // Decode logic (combinational)
    // ----------------------------
    always @(*) begin
        // Defaults: safe NOP-like behavior
        fmt            = 6'b000001; // R (imm don't-care)
        op1_sel        = 2'b00;     // rs1
        op2_sel_imm    = 1'b0;      // rs2

        alu_opsel      = 3'b000;    // add/sub
        alu_sub        = 1'b0;
        alu_unsigned   = 1'b0;
        alu_arith      = 1'b0;

        mem_ren        = 1'b0;
        mem_wen        = 1'b0;
        mem_funct3     = funct3;

        reg_wen        = 1'b0;
        wb_sel         = 2'b00;     // ALU

        is_branch      = 1'b0;
        is_jal         = 1'b0;
        is_jalr        = 1'b0;
        branch_funct3  = funct3;

        is_ebreak      = 1'b0;
        illegal        = 1'b0;

        case (opcode)

            // LUI
            OPC_LUI: begin
                fmt         = 6'b010000; // U
                op1_sel     = 2'b10;     // zero
                op2_sel_imm = 1'b1;      // imm
                alu_opsel   = 3'b000;    // add
                reg_wen     = 1'b1;
                wb_sel      = 2'b00;     // ALU
            end

            // AUIPC
            OPC_AUIPC: begin
                fmt         = 6'b010000; // U
                op1_sel     = 2'b01;     // pc
                op2_sel_imm = 1'b1;      // imm
                alu_opsel   = 3'b000;    // add
                reg_wen     = 1'b1;
                wb_sel      = 2'b00;     // ALU
            end

            // JAL
            OPC_JAL: begin
                fmt         = 6'b100000; // J
                is_jal      = 1'b1;
                // target = pc + imm (hart decides PC redirect)
                op1_sel     = 2'b01;     // pc
                op2_sel_imm = 1'b1;      // imm
                alu_opsel   = 3'b000;    // add (for target calc)
                // rd = pc+4
                reg_wen     = 1'b1;
                wb_sel      = 2'b10;     // PC+4
            end

            // JALR
            OPC_JALR: begin
                fmt         = 6'b000010; // I
                is_jalr     = 1'b1;
                // funct3 must be 000
                if (funct3 != 3'b000) begin
                    illegal = 1'b1;
                end
                // target = rs1 + imm (hart will clear bit0)
                op1_sel     = 2'b00;     // rs1
                op2_sel_imm = 1'b1;      // imm
                alu_opsel   = 3'b000;    // add
                // rd = pc+4
                reg_wen     = 1'b1;
                wb_sel      = 2'b10;     // PC+4
            end

            // BRANCH
            OPC_BRANCH: begin
                fmt            = 6'b001000; // B
                is_branch      = 1'b1;
                branch_funct3  = funct3;

                // compare rs1 vs rs2
                op1_sel        = 2'b00;
                op2_sel_imm    = 1'b0;

                // Often convenient: subtraction path (eq flag still works regardless)
                alu_opsel      = 3'b000;
                alu_sub        = 1'b1;

                // Unsigned comparisons for BLTU/BGEU
                if ((funct3 == 3'b110) || (funct3 == 3'b111)) begin
                    alu_unsigned = 1'b1;
                end

                // validate funct3 (BEQ,BNE,BLT,BGE,BLTU,BGEU)
                if (!((funct3 == 3'b000) || (funct3 == 3'b001) ||
                      (funct3 == 3'b100) || (funct3 == 3'b101) ||
                      (funct3 == 3'b110) || (funct3 == 3'b111))) begin
                    illegal = 1'b1;
                end
            end

            // LOAD
            OPC_LOAD: begin
                fmt         = 6'b000010; // I
                mem_ren     = 1'b1;
                mem_wen     = 1'b0;
                mem_funct3  = funct3;

                // addr = rs1 + imm
                op1_sel     = 2'b00;
                op2_sel_imm = 1'b1;
                alu_opsel   = 3'b000;

                // rd gets MEM
                reg_wen     = 1'b1;
                wb_sel      = 2'b01;

                // validate funct3 (LB,LH,LW,LBU,LHU)
                if (!((funct3 == 3'b000) || (funct3 == 3'b001) ||
                      (funct3 == 3'b010) || (funct3 == 3'b100) ||
                      (funct3 == 3'b101))) begin
                    illegal = 1'b1;
                end
            end

            // STORE
            OPC_STORE: begin
                fmt         = 6'b000100; // S
                mem_ren     = 1'b0;
                mem_wen     = 1'b1;
                mem_funct3  = funct3;

                // addr = rs1 + imm
                op1_sel     = 2'b00;
                op2_sel_imm = 1'b1;
                alu_opsel   = 3'b000;

                // validate funct3 (SB,SH,SW)
                if (!((funct3 == 3'b000) || (funct3 == 3'b001) ||
                      (funct3 == 3'b010))) begin
                    illegal = 1'b1;
                end
            end

            // OP-IMM (I-type ALU)
            OPC_OPIMM: begin
                fmt         = 6'b000010; // I
                reg_wen     = 1'b1;
                wb_sel      = 2'b00;     // ALU

                op1_sel     = 2'b00;     // rs1
                op2_sel_imm = 1'b1;      // imm

                case (funct3)
                    3'b000: begin // ADDI
                        alu_opsel = 3'b000;
                        alu_sub   = 1'b0;
                    end
                    3'b010: begin // SLTI
                        alu_opsel   = 3'b010;
                        alu_unsigned= 1'b0;
                    end
                    3'b011: begin // SLTIU
                        alu_opsel   = 3'b010;
                        alu_unsigned= 1'b1;
                    end
                    3'b100: begin // XORI
                        alu_opsel = 3'b100;
                    end
                    3'b110: begin // ORI
                        alu_opsel = 3'b110;
                    end
                    3'b111: begin // ANDI
                        alu_opsel = 3'b111;
                    end
                    3'b001: begin // SLLI (funct7 must be 0000000)
                        alu_opsel = 3'b001;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b101: begin // SRLI/SRAI
                        alu_opsel = 3'b101;
                        if (funct7 == 7'b0000000) begin
                            alu_arith = 1'b0; // SRLI
                        end else if (funct7 == 7'b0100000) begin
                            alu_arith = 1'b1; // SRAI
                        end else begin
                            illegal = 1'b1;
                        end
                    end
                    default: begin
                        illegal = 1'b1;
                    end
                endcase
            end

            // OP (R-type ALU)
            OPC_OP: begin
                fmt         = 6'b000001; // R
                reg_wen     = 1'b1;
                wb_sel      = 2'b00;     // ALU

                op1_sel     = 2'b00;
                op2_sel_imm = 1'b0;

                case (funct3)
                    3'b000: begin // ADD/SUB
                        alu_opsel = 3'b000;
                        if (funct7 == 7'b0000000) alu_sub = 1'b0;       // ADD
                        else if (funct7 == 7'b0100000) alu_sub = 1'b1;  // SUB
                        else illegal = 1'b1;
                    end
                    3'b001: begin // SLL
                        alu_opsel = 3'b001;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b010: begin // SLT
                        alu_opsel    = 3'b010;
                        alu_unsigned = 1'b0;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b011: begin // SLTU
                        alu_opsel    = 3'b010;
                        alu_unsigned = 1'b1;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b100: begin // XOR
                        alu_opsel = 3'b100;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b101: begin // SRL/SRA
                        alu_opsel = 3'b101;
                        if (funct7 == 7'b0000000) alu_arith = 1'b0;
                        else if (funct7 == 7'b0100000) alu_arith = 1'b1;
                        else illegal = 1'b1;
                    end
                    3'b110: begin // OR
                        alu_opsel = 3'b110;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b111: begin // AND
                        alu_opsel = 3'b111;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    default: begin
                        illegal = 1'b1;
                    end
                endcase
            end

            // SYSTEM (support EBREAK only)
            OPC_SYSTEM: begin
                // EBREAK = 32'h00100073
                if (i_inst == 32'h0010_0073) begin
                    is_ebreak = 1'b1;
                end else begin
                    illegal = 1'b1; // CSR/ECALL not supported yet
                end
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end

    // i_pc currently unused in this module; kept for AUIPC/JAL target-friendly structure.
    // Some tools warn on unused signals; you can ignore or remove i_pc if desired.

endmodule

`default_nettype wire