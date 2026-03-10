`default_nettype none

module memory (
    input wire [31:0] i_addr,
    input wire [31:0] i_rs2_data,
    input wire i_mem_ren,
    input wire i_mem_wen,
    input wire [ 2:0] i_mem_op,  
    output wire [31:0] o_dmem_addr,
    output wire o_dmem_ren,
    output wire o_dmem_wen,
    output wire [31:0] o_dmem_wdata,
    output wire [ 3:0] o_dmem_mask,
    input wire [31:0] i_dmem_rdata,
    output wire [31:0] o_load_data,
    output wire o_misaligned
);

    wire [31:0] addr_aligned = {i_addr[31:2], 2'b00};
    wire [ 1:0] byte_off = i_addr[1:0];

    wire size_byte = (i_mem_op[1:0] == 2'b00);
    wire size_half = (i_mem_op[1:0] == 2'b01);
    wire size_word = (i_mem_op[1:0] == 2'b10);
    wire load_unsigned = i_mem_op[2];

    wire half_misaligned = size_half & byte_off[0];
    wire word_misaligned = size_word & (|byte_off);
    assign o_misaligned = (i_mem_ren | i_mem_wen) & (half_misaligned | word_misaligned);

    assign o_dmem_addr = addr_aligned;
    assign o_dmem_ren = i_mem_ren;
    assign o_dmem_wen = i_mem_wen;

    // Byte mask gen
    reg [3:0] mask;
    always @(*) begin
        case ({i_mem_op[1:0], byte_off})
            // Byte access
            {2'b00, 2'b00}: mask = 4'b0001;
            {2'b00, 2'b01}: mask = 4'b0010;
            {2'b00, 2'b10}: mask = 4'b0100;
            {2'b00, 2'b11}: mask = 4'b1000;
            // Half-word access
            {2'b01, 2'b00}: mask = 4'b0011;
            {2'b01, 2'b10}: mask = 4'b1100;
            // Word access
            {2'b10, 2'b00}: mask = 4'b1111;
            default: mask = 4'b0000;
        endcase
    end
    assign o_dmem_mask = mask;

    // Store data: shift rs2 into the correct byte lane
    // SB: place byte in the lane indicated by byte_off
    // SH: place half in the lane indicated by byte_off 
    // SW: place word directly
    reg [31:0] wdata;
    always @(*) begin
        case ({i_mem_op[1:0], byte_off})
            // Byte store
            {2'b00, 2'b00}: wdata = i_rs2_data;
            {2'b00, 2'b01}: wdata = i_rs2_data << 8;
            {2'b00, 2'b10}: wdata = i_rs2_data << 16;
            {2'b00, 2'b11}: wdata = i_rs2_data << 24;
            // Half-word store
            {2'b01, 2'b00}: wdata = i_rs2_data;
            {2'b01, 2'b10}: wdata = i_rs2_data << 16;
            // Word store
            {2'b10, 2'b00}: wdata = i_rs2_data;
            default: wdata = 32'b0;
        endcase
    end
    assign o_dmem_wdata = wdata;

    // Load data, extract from correct byte lane, sign/zero extend
    // Shift the relevant bytes down to bits [7:0] or [15:0]
    reg [7:0] load_byte;
    reg [15:0] load_half;

    always @(*) begin
        case (byte_off)
            2'b00: load_byte = i_dmem_rdata[ 7: 0];
            2'b01: load_byte = i_dmem_rdata[15: 8];
            2'b10: load_byte = i_dmem_rdata[23:16];
            2'b11: load_byte = i_dmem_rdata[31:24];
            default: load_byte = i_dmem_rdata[ 7: 0];
        endcase
    end

    always @(*) begin
        case (byte_off[1])
            1'b0: load_half = i_dmem_rdata[15: 0];
            1'b1: load_half = i_dmem_rdata[31:16];
            default: load_half = i_dmem_rdata[15: 0];
        endcase
    end

    // Sign/zero extension
    wire [31:0] load_byte_ext = load_unsigned ? {24'b0, load_byte}
                                : {{24{load_byte[7]}}, load_byte};
    wire [31:0] load_half_ext = load_unsigned ? {16'b0, load_half}
                                : {{16{load_half[15]}}, load_half};

    // Final load data mux
    assign o_load_data = size_byte ? load_byte_ext :
                         size_half ? load_half_ext : i_dmem_rdata;  

endmodule

`default_nettype wire
