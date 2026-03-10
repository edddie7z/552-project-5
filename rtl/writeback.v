`default_nettype none

module writeback (
    input  ire [ 1:0] i_wb_sel,
    input wire [31:0] i_alu_result,
    input wire [31:0] i_mem_data,
    input wire [31:0] i_pc_plus4,
    input wire [31:0] i_immediate,
    output wire [31:0] o_wb_data
);

    reg [31:0] wb_r;

    // Writeback mux
    always @(*) begin
        case (i_wb_sel)
            2'b00: wb_r = i_alu_result; // R-type, IALU, AUIPC
            2'b01: wb_r = i_mem_data; // loads
            2'b10: wb_r = i_pc_plus4; // JAL/JALR return address
            2'b11: wb_r = i_immediate; // LUI
            default: wb_r = i_alu_result;
        endcase
    end

    assign o_wb_data = wb_r;

endmodule

`default_nettype wire