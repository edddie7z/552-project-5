module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Instruction fetch goes through a read only instruction memory (imem)
    // port. The port accepts a 32-bit address (e.g. from the program counter)
    // per cycle and combinationally returns a 32-bit instruction word. This
    // is not representative of a realistic memory interface; it has been
    // modeled as more similar to a DFF or SRAM to simplify phase 3. In
    // later phases, you will replace this with a more realistic memory.
    //
    // 32-bit read address for the instruction memory. This is expected to be
    // 4 byte aligned - that is, the two LSBs should be zero.
    output wire [31:0] o_imem_raddr,
    // Instruction word fetched from memory, available on the same cycle.
    input  wire [31:0] i_imem_rdata,
    // Data memory accesses go through a separate read/write data memory (dmem)
    // that is shared between read (load) and write (stored). The port accepts
    // a 32-bit address, read or write enable, and mask (explained below) each
    // cycle. Reads are combinational - values are available immediately after
    // updating the address and asserting read enable. Writes occur on (and
    // are visible at) the next clock edge.
    //
    // Read/write address for the data memory. This should be 32-bit aligned
    // (i.e. the two LSB should be zero). See `o_dmem_mask` for how to perform
    // half-word and byte accesses at unaligned addresses.
    output wire [31:0] o_dmem_addr,
    // When asserted, the memory will perform a read at the aligned address
    // specified by `i_addr` and return the 32-bit word at that address
    // immediately (i.e. combinationally). It is illegal to assert this and
    // `o_dmem_wen` on the same cycle.
    output wire        o_dmem_ren,
    // When asserted, the memory will perform a write to the aligned address
    // `o_dmem_addr`. When asserted, the memory will write the bytes in
    // `o_dmem_wdata` (specified by the mask) to memory at the specified
    // address on the next rising clock edge. It is illegal to assert this and
    // `o_dmem_ren` on the same cycle.
    output wire        o_dmem_wen,
    // The 32-bit word to write to memory when `o_dmem_wen` is asserted. When
    // write enable is asserted, the byte lanes specified by the mask will be
    // written to the memory word at the aligned address at the next rising
    // clock edge. The other byte lanes of the word will be unaffected.
    output wire [31:0] o_dmem_wdata,
    // The dmem interface expects word (32 bit) aligned addresses. However,
    // WISC-25 supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    //
    // To perform a half-word read at address 0x00001002, align `o_dmem_addr`
    // to 0x00001000, assert `o_dmem_ren`, and set the mask to 0b1100 to
    // indicate that only the upper two bytes should be read. Only the upper
    // two bytes of `i_dmem_rdata` can be assumed to have valid data; to
    // calculate the final value of the `lh[u]` instruction, shift the rdata
    // word right by 16 bits and sign/zero extend as appropriate.
    //
    // To perform a byte write at address 0x00002003, align `o_dmem_addr` to
    // `0x00002000`, assert `o_dmem_wen`, and set the mask to 0b1000 to
    // indicate that only the upper byte should be written. On the next clock
    // cycle, the upper byte of `o_dmem_wdata` will be written to memory, with
    // the other three bytes of the aligned word unaffected. Remember to shift
    // the value of the `sb` instruction left by 24 bits to place it in the
    // appropriate byte lane.
    output wire [ 3:0] o_dmem_mask,
    // The 32-bit word read from data memory. When `o_dmem_ren` is asserted,
    // this will immediately reflect the contents of memory at the specified
    // address, for the bytes enabled by the mask. When read enable is not
    // asserted, or for bytes not set in the mask, the value is undefined.
    input  wire [31:0] i_dmem_rdata,
	// The output `retire` interface is used to signal to the testbench that
    // the CPU has completed and retired an instruction. A single cycle
    // implementation will assert this every cycle; however, a pipelined
    // implementation that needs to stall (due to internal hazards or waiting
    // on memory accesses) will not assert the signal on cycles where the
    // instruction in the writeback stage is not retiring.
    //
    // Asserted when an instruction is being retired this cycle. If this is
    // not asserted, the other retire signals are ignored and may be left invalid.
    output wire        o_retire_valid,
    // The 32 bit instruction word of the instrution being retired. This
    // should be the unmodified instruction word fetched from instruction
    // memory.
    output wire [31:0] o_retire_inst,
    // Asserted if the instruction produced a trap, due to an illegal
    // instruction, unaligned data memory access, or unaligned instruction
    // address on a taken branch or jump.
    output wire        o_retire_trap,
    // Asserted if the instruction is an `ebreak` instruction used to halt the
    // processor. This is used for debugging and testing purposes to end
    // a program.
    output wire        o_retire_halt,
    // The first register address read by the instruction being retired. If
    // the instruction does not read from a register (like `lui`), this
    // should be 5'd0.
    output wire [ 4:0] o_retire_rs1_raddr,
    // The second register address read by the instruction being retired. If
    // the instruction does not read from a second register (like `addi`), this
    // should be 5'd0.
    output wire [ 4:0] o_retire_rs2_raddr,
    // The first source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs1 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs1_rdata,
    // The second source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs2 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs2_rdata,
    // The destination register address written by the instruction being
    // retired. If the instruction does not write to a register (like `sw`),
    // this should be 5'd0.
    output wire [ 4:0] o_retire_rd_waddr,
    // The destination register data written to the register file in the
    // writeback stage by this instruction. If rd is 5'd0, this field is
    // ignored and can be treated as a don't care.
    output wire [31:0] o_retire_rd_wdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc,
    // Data memory address used by the instruction being retired. This should
    // match the aligned address placed on the data memory interface for loads
    // and stores. For instructions that do not access data memory, this may be
    // left as 32'd0.
    output wire [31:0] o_retire_dmem_addr,
    // Asserted if the retiring instruction performed a data memory read.
    output wire        o_retire_dmem_ren,
    // Asserted if the retiring instruction performed a data memory write.
    output wire        o_retire_dmem_wen,
    // The byte-enable mask used by the retiring instruction for the data
    // memory access. For instructions that do not access data memory, this may
    // be left as 4'd0.
    output wire [ 3:0] o_retire_dmem_mask,
    // The data written to memory by the retiring instruction. For instructions
    // that are not stores, this may be left as 32'd0.
    output wire [31:0] o_retire_dmem_wdata,
    // The raw 32-bit data word returned by memory for the retiring
    // instruction. For instructions that are not loads, this may be left as
    // 32'd0.
    output wire [31:0] o_retire_dmem_rdata

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);
    // Register signals

    // IF/ID
    reg ifid_valid;
    reg [31:0] ifid_pc, ifid_inst;

    // ID/EX
    reg idex_valid;
    reg [31:0] idex_pc, idex_inst;
    reg [4:0] idex_rs1_addr, idex_rs2_addr, idex_rd_addr;
    reg [31:0] idex_rs1_data, idex_rs2_data;
    reg [31:0] idex_immediate;
    reg [2:0] idex_alu_op;
    reg idex_alu_sub, idex_alu_unsigned, idex_alu_arith;
    reg idex_alu_src, idex_alu_pc;
    reg idex_mem_ren, idex_mem_wen;
    reg [2:0] idex_mem_op;
    reg [1:0] idex_wb_sel;
    reg idex_reg_wen;
    reg idex_branch, idex_jump, idex_is_jalr;
    reg [2:0] idex_branch_op;
    reg idex_halt, idex_trap;
    reg idex_uses_rs1, idex_uses_rs2;

    // EX/MEM
    reg exmem_valid;
    reg [31:0] exmem_pc, exmem_inst;
    reg [31:0] exmem_alu_result, exmem_branch_target;
    reg exmem_pc_set;
    reg [4:0] exmem_rs1_addr, exmem_rs2_addr, exmem_rd_addr;
    reg [31:0] exmem_rs1_data, exmem_rs2_data;
    reg [31:0] exmem_store_data;
    reg [31:0] exmem_immediate, exmem_pc_plus4;
    reg exmem_mem_ren, exmem_mem_wen;
    reg [2:0] exmem_mem_op;
    reg [1:0] exmem_wb_sel;
    reg exmem_reg_wen;
    reg exmem_halt, exmem_trap;
    reg exmem_uses_rs1, exmem_uses_rs2;

    // MEM/WB
    reg memwb_valid;
    reg [31:0] memwb_pc, memwb_inst;
    reg [31:0] memwb_alu_result, memwb_load_data;
    reg [31:0] memwb_pc_plus4, memwb_immediate;
    reg memwb_pc_set;
    reg [31:0] memwb_branch_target;
    reg [4:0] memwb_rs1_addr, memwb_rs2_addr, memwb_rd_addr;
    reg [31:0] memwb_rs1_data, memwb_rs2_data;
    reg [1:0] memwb_wb_sel;
    reg memwb_reg_wen;
    reg memwb_halt, memwb_trap;
    reg memwb_uses_rs1, memwb_uses_rs2;
    reg [31:0] memwb_dmem_addr;
    reg memwb_dmem_ren, memwb_dmem_wen;
    reg [ 3:0] memwb_dmem_mask;
    reg [31:0] memwb_dmem_wdata, memwb_dmem_rdata;


    // fetch
    wire [31:0] fetch_pc, fetch_inst;
    wire fetch_pc_misaligned;

    // decode
    wire [ 4:0] dec_rs1_addr, dec_rs2_addr, dec_rd_addr;
    wire [ 5:0] dec_imm_format;
    wire [ 2:0] dec_alu_op;
    wire dec_alu_sub, dec_alu_unsigned, dec_alu_arith;
    wire dec_alu_src, dec_alu_pc;
    wire dec_mem_ren, dec_mem_wen;
    wire [ 2:0] dec_mem_op;
    wire [ 1:0] dec_wb_sel;
    wire dec_reg_wen;
    wire dec_branch, dec_jump, dec_is_jalr;
    wire [ 2:0] dec_branch_op;
    wire dec_halt, dec_trap;
    wire dec_uses_rs1, dec_uses_rs2;

    wire [31:0] immediate;
    wire [31:0] rs1_data, rs2_data;

    // execute
    wire [31:0] exe_alu_result, exe_branch_target;
    wire exe_pc_set, exe_target_misaligned;

    // memory
    wire [31:0] mem_load_data;
    wire mem_misaligned;

    // writeback
    wire [31:0] wb_data;

    // BLTU/BGEU (funct3[1]=1), read from IF/ID reg
    wire alu_unsigned_final = dec_alu_unsigned | (dec_branch & ifid_inst[13]);

    // Branches predict not taken
    // Redirect PC and flush younger instructions when EX resolves taken branch/jump
    wire pc_redirect = exe_pc_set & ~exe_target_misaligned;
    wire flush = pc_redirect;

    // Hazard Detection (RAW)

    // rs1/rs2 in IF/ID depends on rd in ID/EX 
    wire hazard_rs1_idex =
        ifid_valid &&
        dec_uses_rs1 &&
        (dec_rs1_addr != 5'd0) &&
        idex_valid &&
        idex_mem_ren &&
        (idex_rd_addr != 5'd0) &&
        (dec_rs1_addr == idex_rd_addr);

    wire hazard_rs2_idex =
        ifid_valid &&
        dec_uses_rs2 &&
        ~dec_mem_wen &&
        (dec_rs2_addr != 5'd0) &&
        idex_valid &&
        idex_mem_ren &&
        (idex_rd_addr != 5'd0) &&
        (dec_rs2_addr == idex_rd_addr);

    // Overall hazard stall signal
    // With EX/EX and MEMEX forwarding, only load use from ID/EX stalls
    wire hazard_stall = hazard_rs1_idex |
                        hazard_rs2_idex;

    // EX/EX forwarding val for non loading instructions
    wire [31:0] exmem_wb_data_noload =
        (exmem_wb_sel == 2'b10) ? exmem_pc_plus4 :
        (exmem_wb_sel == 2'b11) ? exmem_immediate :
                                  exmem_alu_result;

    wire ex_fwd_rs1_exmem =
        idex_valid &&
        idex_uses_rs1 &&
        (idex_rs1_addr != 5'd0) &&
        exmem_valid &&
        exmem_reg_wen &&
        ~exmem_trap &&
        ~exmem_mem_ren &&
        (exmem_rd_addr != 5'd0) &&
        (idex_rs1_addr == exmem_rd_addr);

    wire ex_fwd_rs2_exmem =
        idex_valid &&
        idex_uses_rs2 &&
        (idex_rs2_addr != 5'd0) &&
        exmem_valid &&
        exmem_reg_wen &&
        ~exmem_trap &&
        ~exmem_mem_ren &&
        (exmem_rd_addr != 5'd0) &&
        (idex_rs2_addr == exmem_rd_addr);

    wire ex_fwd_rs1_memwb =
        idex_valid &&
        idex_uses_rs1 &&
        (idex_rs1_addr != 5'd0) &&
        memwb_valid &&
        memwb_reg_wen &&
        ~memwb_trap &&
        (memwb_rd_addr != 5'd0) &&
        (idex_rs1_addr == memwb_rd_addr) &&
        ~ex_fwd_rs1_exmem;

    wire ex_fwd_rs2_memwb =
        idex_valid &&
        idex_uses_rs2 &&
        (idex_rs2_addr != 5'd0) &&
        memwb_valid &&
        memwb_reg_wen &&
        ~memwb_trap &&
        (memwb_rd_addr != 5'd0) &&
        (idex_rs2_addr == memwb_rd_addr) &&
        ~ex_fwd_rs2_exmem;

    wire [31:0] ex_rs1_data = ex_fwd_rs1_exmem ? exmem_wb_data_noload :
                              ex_fwd_rs1_memwb ? wb_data :
                              idex_rs1_data;
    wire [31:0] ex_rs2_data = ex_fwd_rs2_exmem ? exmem_wb_data_noload :
                              ex_fwd_rs2_memwb ? wb_data :
                              idex_rs2_data;

    // Store data forwarding at MEM stage
    wire mem_fwd_store_memwb =
        exmem_valid &&
        exmem_mem_wen &&
        (exmem_rs2_addr != 5'd0) &&
        memwb_valid &&
        memwb_reg_wen &&
        ~memwb_trap &&
        (memwb_rd_addr != 5'd0) &&
        (exmem_rs2_addr == memwb_rd_addr);

    wire [31:0] mem_store_data = mem_fwd_store_memwb ? wb_data : exmem_store_data;

    // IF/ID pipeline register
    always @(posedge i_clk) begin
        if (i_rst) begin
            ifid_valid <= 1'b0;
            ifid_pc <= 32'd0;
            ifid_inst <= 32'h00000013; // nop
        end else if (flush) begin
            ifid_valid <= 1'b0;
            ifid_pc <= 32'd0;
            ifid_inst <= 32'h00000013; // nop
        end else if (hazard_stall) begin
            ifid_valid <= ifid_valid;   // hold
            ifid_pc <= ifid_pc;
            ifid_inst <= ifid_inst;
        end else begin
            ifid_valid <= 1'b1;
            ifid_pc <= fetch_pc;
            ifid_inst <= fetch_inst;
        end
    end

    // ID/EX pipeline register
    always @(posedge i_clk) begin
        if (i_rst) begin
            idex_valid <= 1'b0;
            idex_pc <= 32'd0;
            idex_inst <= 32'h00000013;
            idex_rs1_addr <= 5'd0;
            idex_rs2_addr <= 5'd0;
            idex_rd_addr <= 5'd0;
            idex_rs1_data <= 32'd0;
            idex_rs2_data <= 32'd0;
            idex_immediate <= 32'd0;
            idex_alu_op <= 3'd0;
            idex_alu_sub <= 1'b0;
            idex_alu_unsigned <= 1'b0;
            idex_alu_arith <= 1'b0;
            idex_alu_src <= 1'b0;
            idex_alu_pc <= 1'b0;
            idex_mem_ren <= 1'b0;
            idex_mem_wen <= 1'b0;
            idex_mem_op <= 3'd0;
            idex_wb_sel <= 2'd0;
            idex_reg_wen <= 1'b0;
            idex_branch <= 1'b0;
            idex_jump <= 1'b0;
            idex_is_jalr <= 1'b0;
            idex_branch_op <= 3'd0;
            idex_halt <= 1'b0;
            idex_trap <= 1'b0;
            idex_uses_rs1 <= 1'b0;
            idex_uses_rs2 <= 1'b0;
        end else if (flush || hazard_stall) begin
            idex_valid <= 1'b0;
            idex_pc <= 32'd0;
            idex_inst <= 32'h00000013;
            idex_rs1_addr <= 5'd0;
            idex_rs2_addr <= 5'd0;
            idex_rd_addr <= 5'd0;
            idex_rs1_data <= 32'd0;
            idex_rs2_data <= 32'd0;
            idex_immediate <= 32'd0;
            idex_alu_op <= 3'd0;
            idex_alu_sub <= 1'b0;
            idex_alu_unsigned <= 1'b0;
            idex_alu_arith <= 1'b0;
            idex_alu_src <= 1'b0;
            idex_alu_pc <= 1'b0;
            idex_mem_ren <= 1'b0;
            idex_mem_wen <= 1'b0;
            idex_mem_op <= 3'd0;
            idex_wb_sel <= 2'd0;
            idex_reg_wen <= 1'b0;
            idex_branch <= 1'b0;
            idex_jump <= 1'b0;
            idex_is_jalr <= 1'b0;
            idex_branch_op <= 3'd0;
            idex_halt <= 1'b0;
            idex_trap <= 1'b0;
            idex_uses_rs1 <= 1'b0;
            idex_uses_rs2 <= 1'b0;
        end else begin
            idex_valid <= ifid_valid;
            idex_pc <= ifid_pc;
            idex_inst <= ifid_inst;
            idex_rs1_addr <= dec_rs1_addr;
            idex_rs2_addr <= dec_rs2_addr;
            idex_rd_addr <= dec_rd_addr;
            idex_rs1_data <= rs1_data;
            idex_rs2_data <= rs2_data;
            idex_immediate <= immediate;
            idex_alu_op <= dec_alu_op;
            idex_alu_sub <= dec_alu_sub;
            idex_alu_unsigned <= alu_unsigned_final;
            idex_alu_arith <= dec_alu_arith;
            idex_alu_src <= dec_alu_src;
            idex_alu_pc <= dec_alu_pc;
            idex_mem_ren <= dec_mem_ren;
            idex_mem_wen <= dec_mem_wen;
            idex_mem_op <= dec_mem_op;
            idex_wb_sel <= dec_wb_sel;
            idex_reg_wen <= dec_reg_wen;
            idex_branch <= dec_branch;
            idex_jump <= dec_jump;
            idex_is_jalr <= dec_is_jalr;
            idex_branch_op <= dec_branch_op;
            idex_halt <= dec_halt;
            idex_trap <= dec_trap;
            idex_uses_rs1 <= dec_uses_rs1;
            idex_uses_rs2 <= dec_uses_rs2;
        end
    end

    // EX/MEM pipeline register
    always @(posedge i_clk) begin
        if (i_rst) begin
            exmem_valid <= 1'b0;
            exmem_pc <= 32'd0;
            exmem_inst <= 32'h00000013;
            exmem_alu_result <= 32'd0;
            exmem_branch_target <= 32'd0;
            exmem_pc_set <= 1'b0;
            exmem_rs1_addr <= 5'd0;
            exmem_rs2_addr <= 5'd0;
            exmem_rd_addr <= 5'd0;
            exmem_rs1_data <= 32'd0;
            exmem_rs2_data <= 32'd0;
            exmem_store_data <= 32'd0;
            exmem_immediate <= 32'd0;
            exmem_pc_plus4 <= 32'd0;
            exmem_mem_ren <= 1'b0;
            exmem_mem_wen <= 1'b0;
            exmem_mem_op <= 3'd0;
            exmem_wb_sel <= 2'd0;
            exmem_reg_wen <= 1'b0;
            exmem_halt <= 1'b0;
            exmem_trap <= 1'b0;
            exmem_uses_rs1 <= 1'b0;
            exmem_uses_rs2 <= 1'b0;
        end else begin
            exmem_valid <= idex_valid;
            exmem_pc <= idex_pc;
            exmem_inst <= idex_inst;
            exmem_alu_result <= exe_alu_result;
            exmem_branch_target <= exe_branch_target;
            exmem_pc_set <= exe_pc_set;
            exmem_rs1_addr <= idex_rs1_addr;
            exmem_rs2_addr <= idex_rs2_addr;
            exmem_rd_addr <= idex_rd_addr;
            exmem_rs1_data <= idex_rs1_data;
            exmem_rs2_data <= idex_rs2_data;
            exmem_store_data <= ex_rs2_data;
            exmem_immediate <= idex_immediate;
            exmem_pc_plus4 <= idex_pc + 32'd4;
            exmem_mem_ren <= idex_mem_ren;
            exmem_mem_wen <= idex_mem_wen;
            exmem_mem_op <= idex_mem_op;
            exmem_wb_sel <= idex_wb_sel;
            exmem_reg_wen <= idex_reg_wen;
            exmem_halt <= idex_halt;
            exmem_trap <= idex_trap | (exe_pc_set & exe_target_misaligned);
            exmem_uses_rs1 <= idex_uses_rs1;
            exmem_uses_rs2 <= idex_uses_rs2;
        end
    end

    // MEM/WB pipeline register
    always @(posedge i_clk) begin
        if (i_rst) begin
            memwb_valid <= 1'b0;
            memwb_pc <= 32'd0;
            memwb_inst <= 32'h00000013;
            memwb_alu_result <= 32'd0;
            memwb_load_data <= 32'd0;
            memwb_pc_plus4 <= 32'd0;
            memwb_immediate <= 32'd0;
            memwb_pc_set <= 1'b0;
            memwb_branch_target <= 32'd0;
            memwb_rs1_addr <= 5'd0;
            memwb_rs2_addr <= 5'd0;
            memwb_rd_addr <= 5'd0;
            memwb_rs1_data <= 32'd0;
            memwb_rs2_data <= 32'd0;
            memwb_wb_sel <= 2'd0;
            memwb_reg_wen <= 1'b0;
            memwb_halt <= 1'b0;
            memwb_trap <= 1'b0;
            memwb_uses_rs1 <= 1'b0;
            memwb_uses_rs2 <= 1'b0;
            memwb_dmem_addr <= 32'd0;
            memwb_dmem_ren <= 1'b0;
            memwb_dmem_wen <= 1'b0;
            memwb_dmem_mask <= 4'd0;
            memwb_dmem_wdata <= 32'd0;
            memwb_dmem_rdata <= 32'd0;
        end else begin
            memwb_valid <= exmem_valid;
            memwb_pc <= exmem_pc;
            memwb_inst <= exmem_inst;
            memwb_alu_result <= exmem_alu_result;
            memwb_load_data <= mem_load_data;
            memwb_pc_plus4 <= exmem_pc_plus4;
            memwb_immediate <= exmem_immediate;
            memwb_pc_set <= exmem_pc_set;
            memwb_branch_target <= exmem_branch_target;
            memwb_rs1_addr <= exmem_rs1_addr;
            memwb_rs2_addr <= exmem_rs2_addr;
            memwb_rd_addr <= exmem_rd_addr;
            memwb_rs1_data <= exmem_rs1_data;
            memwb_rs2_data <= exmem_rs2_data;
            memwb_wb_sel <= exmem_wb_sel;
            memwb_reg_wen <= exmem_reg_wen;
            memwb_halt <= exmem_halt;
            memwb_trap <= exmem_trap | mem_misaligned;
            memwb_uses_rs1 <= exmem_uses_rs1;
            memwb_uses_rs2 <= exmem_uses_rs2;
            memwb_dmem_addr <= o_dmem_addr;
            memwb_dmem_ren <= exmem_valid & exmem_mem_ren & ~exmem_trap;
            memwb_dmem_wen <= exmem_valid & exmem_mem_wen & ~exmem_trap;
            memwb_dmem_mask <= o_dmem_mask;
            memwb_dmem_wdata <= o_dmem_wdata;
            memwb_dmem_rdata <= i_dmem_rdata;
        end
    end

    // Fetch stage
    fetch #(
        .RESET_ADDR (RESET_ADDR)
    ) IF (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_stall(hazard_stall),
        .i_pc_set(pc_redirect),
        .i_pc_next(exe_branch_target),
        .o_imem_raddr(o_imem_raddr),
        .i_imem_rdata(i_imem_rdata),
        .o_pc(fetch_pc),
        .o_inst(fetch_inst),
        .o_pc_misaligned(fetch_pc_misaligned)
    );

    // Decode
    decode ID (
        .i_inst(ifid_inst),
        .o_rs1_addr(dec_rs1_addr),
        .o_rs2_addr(dec_rs2_addr),
        .o_rd_addr(dec_rd_addr),
        .o_imm_format(dec_imm_format),
        .o_alu_op(dec_alu_op),
        .o_alu_sub(dec_alu_sub),
        .o_alu_unsigned(dec_alu_unsigned),
        .o_alu_arith(dec_alu_arith),
        .o_alu_src(dec_alu_src),
        .o_alu_pc(dec_alu_pc),
        .o_mem_ren(dec_mem_ren),
        .o_mem_wen(dec_mem_wen),
        .o_mem_op(dec_mem_op),
        .o_wb_sel(dec_wb_sel),
        .o_reg_wen(dec_reg_wen),
        .o_branch(dec_branch),
        .o_jump(dec_jump),
        .o_is_jalr(dec_is_jalr),
        .o_branch_op(dec_branch_op),
        .o_halt(dec_halt),
        .o_trap(dec_trap),
        .o_uses_rs1(dec_uses_rs1),
        .o_uses_rs2(dec_uses_rs2)
    );

    imm imm_gen (
        .i_inst(ifid_inst),
        .i_format(dec_imm_format),
        .o_immediate(immediate)
    );

    rf #(
        .BYPASS_EN (1)
    ) regfile (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_rs1_raddr(dec_rs1_addr),
        .o_rs1_rdata(rs1_data),
        .i_rs2_raddr(dec_rs2_addr),
        .o_rs2_rdata(rs2_data),
        .i_rd_wen(memwb_valid & memwb_reg_wen & ~memwb_trap),   // gate with valid
        .i_rd_waddr(memwb_rd_addr),
        .i_rd_wdata(wb_data)
    );

    // Execute
    execute EX (
        .i_rs1_data(ex_rs1_data),
        .i_rs2_data(ex_rs2_data),
        .i_immediate(idex_immediate),
        .i_pc(idex_pc),
        .i_alu_op(idex_alu_op),
        .i_alu_sub(idex_alu_sub),
        .i_alu_unsigned(idex_alu_unsigned),
        .i_alu_arith(idex_alu_arith),
        .i_alu_src(idex_alu_src),
        .i_alu_pc(idex_alu_pc),
        .i_branch(idex_branch),
        .i_jump(idex_jump),
        .i_is_jalr(idex_is_jalr),
        .i_branch_op(idex_branch_op),
        .o_alu_result(exe_alu_result),
        .o_branch_target(exe_branch_target),
        .o_pc_set(exe_pc_set),
        .o_target_misaligned(exe_target_misaligned)
    );

    // Memory stage
    memory MEM (
        .i_addr(exmem_alu_result),
        .i_rs2_data(mem_store_data),
        .i_mem_ren(exmem_valid & exmem_mem_ren & ~exmem_trap),
        .i_mem_wen(exmem_valid & exmem_mem_wen & ~exmem_trap),
        .i_mem_op(exmem_mem_op),
        .o_dmem_addr(o_dmem_addr),
        .o_dmem_ren(o_dmem_ren),
        .o_dmem_wen(o_dmem_wen),
        .o_dmem_wdata(o_dmem_wdata),
        .o_dmem_mask(o_dmem_mask),
        .i_dmem_rdata(i_dmem_rdata),
        .o_load_data(mem_load_data),
        .o_misaligned(mem_misaligned)
    );

    // Writeback stage
    writeback WB (
        .i_wb_sel(memwb_wb_sel),
        .i_alu_result(memwb_alu_result),
        .i_mem_data(memwb_load_data),
        .i_pc_plus4(memwb_pc_plus4),
        .i_immediate(memwb_immediate),
        .o_wb_data(wb_data)
    );

    // Retire interface
    assign o_retire_valid = memwb_valid;
    assign o_retire_inst = memwb_inst;
    assign o_retire_trap = memwb_trap;
    assign o_retire_halt = memwb_halt;
    assign o_retire_pc = memwb_pc;
    assign o_retire_next_pc = (memwb_pc_set & ~memwb_trap) ? memwb_branch_target
                                                           : memwb_pc_plus4;

    assign o_retire_rs1_raddr = (memwb_valid && memwb_uses_rs1) ? memwb_rs1_addr : 5'd0;
    assign o_retire_rs2_raddr = (memwb_valid && memwb_uses_rs2) ? memwb_rs2_addr : 5'd0;
    assign o_retire_rs1_rdata = (o_retire_rs1_raddr == 5'd0) ? 32'd0 : memwb_rs1_data;
    assign o_retire_rs2_rdata = (o_retire_rs2_raddr == 5'd0) ? 32'd0 : memwb_rs2_data;

    assign o_retire_rd_waddr = (memwb_valid && memwb_reg_wen && ~memwb_trap) ? memwb_rd_addr : 5'd0;
    assign o_retire_rd_wdata = wb_data;

    assign o_retire_dmem_addr = memwb_dmem_addr;
    assign o_retire_dmem_ren = memwb_valid ? memwb_dmem_ren : 1'b0;
    assign o_retire_dmem_wen = memwb_valid ? memwb_dmem_wen : 1'b0;
    assign o_retire_dmem_mask = memwb_valid ? memwb_dmem_mask : 4'd0;
    assign o_retire_dmem_wdata = memwb_valid ? memwb_dmem_wdata : 32'd0;
    assign o_retire_dmem_rdata = memwb_valid ? memwb_dmem_rdata : 32'd0;
endmodule

`default_nettype wire