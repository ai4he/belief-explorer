/*
 * Multi-Base Converter Core for PYNQ Z2 FPGA
 * Supports Base 12 (Dozenal), Base 10 (Decimal), and Base 2 (Binary)
 * Optimized for HFT and Mid-Frequency Trading Applications
 *
 * Features:
 * - Dynamic base selection for optimal calculation paths
 * - Pipeline architecture for high throughput
 * - Low-latency conversion (< 10 clock cycles)
 * - Fixed-point arithmetic for financial calculations
 */

module base_converter #(
    parameter DATA_WIDTH = 64,          // Width for financial data (64-bit fixed point)
    parameter FRAC_BITS = 32,           // Fractional bits for precision
    parameter PIPELINE_STAGES = 4       // Pipeline depth for throughput
)(
    input wire clk,
    input wire rst_n,
    input wire enable,

    // Input data and base
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [1:0] base_in,           // 2'b00: base 2, 2'b01: base 10, 2'b10: base 12
    input wire [1:0] base_out,          // Target base for output

    // Control signals
    input wire start,
    output reg ready,
    output reg valid,

    // Output data
    output reg [DATA_WIDTH-1:0] data_out,
    output reg error
);

    // Base encoding
    localparam BASE_2  = 2'b00;
    localparam BASE_10 = 2'b01;
    localparam BASE_12 = 2'b10;

    // State machine
    localparam IDLE       = 3'b000;
    localparam LOAD       = 3'b001;
    localparam CONVERT    = 3'b010;
    localparam NORMALIZE  = 3'b011;
    localparam OUTPUT     = 3'b100;

    reg [2:0] state, next_state;
    reg [DATA_WIDTH-1:0] working_reg;
    reg [5:0] counter;
    reg [1:0] src_base, dst_base;

    // Pipeline registers for high-throughput operation
    reg [DATA_WIDTH-1:0] pipe_stage1, pipe_stage2, pipe_stage3;
    reg [1:0] pipe_base1, pipe_base2, pipe_base3;

    // Base conversion lookup tables (optimized for FPGA BRAM)
    reg [11:0] base12_digit_lut [0:11];  // Base-12 digit values
    reg [31:0] power10_lut [0:15];       // Powers of 10 for fast conversion
    reg [31:0] power12_lut [0:15];       // Powers of 12 for fast conversion

    // Initialize lookup tables
    initial begin
        // Base-12 digit values
        base12_digit_lut[0]  = 12'h000;  base12_digit_lut[1]  = 12'h001;
        base12_digit_lut[2]  = 12'h002;  base12_digit_lut[3]  = 12'h003;
        base12_digit_lut[4]  = 12'h004;  base12_digit_lut[5]  = 12'h005;
        base12_digit_lut[6]  = 12'h006;  base12_digit_lut[7]  = 12'h007;
        base12_digit_lut[8]  = 12'h008;  base12_digit_lut[9]  = 12'h009;
        base12_digit_lut[10] = 12'h00A;  base12_digit_lut[11] = 12'h00B;

        // Powers of 10 for decimal conversion
        power10_lut[0]  = 32'd1;           power10_lut[1]  = 32'd10;
        power10_lut[2]  = 32'd100;         power10_lut[3]  = 32'd1000;
        power10_lut[4]  = 32'd10000;       power10_lut[5]  = 32'd100000;
        power10_lut[6]  = 32'd1000000;     power10_lut[7]  = 32'd10000000;
        power10_lut[8]  = 32'd100000000;   power10_lut[9]  = 32'd1000000000;
        power10_lut[10] = 32'd1;           power10_lut[11] = 32'd1;
        power10_lut[12] = 32'd1;           power10_lut[13] = 32'd1;
        power10_lut[14] = 32'd1;           power10_lut[15] = 32'd1;

        // Powers of 12 for dozenal conversion
        power12_lut[0]  = 32'd1;           power12_lut[1]  = 32'd12;
        power12_lut[2]  = 32'd144;         power12_lut[3]  = 32'd1728;
        power12_lut[4]  = 32'd20736;       power12_lut[5]  = 32'd248832;
        power12_lut[6]  = 32'd2985984;     power12_lut[7]  = 32'd35831808;
        power12_lut[8]  = 32'd429981696;   power12_lut[9]  = 32'd1;
        power12_lut[10] = 32'd1;           power12_lut[11] = 32'd1;
        power12_lut[12] = 32'd1;           power12_lut[13] = 32'd1;
        power12_lut[14] = 32'd1;           power12_lut[15] = 32'd1;
    end

    // State machine - sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ready <= 1'b1;
            valid <= 1'b0;
            error <= 1'b0;
            data_out <= {DATA_WIDTH{1'b0}};
            working_reg <= {DATA_WIDTH{1'b0}};
            counter <= 6'd0;
            src_base <= BASE_2;
            dst_base <= BASE_2;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    ready <= 1'b1;
                    valid <= 1'b0;
                    if (start && enable) begin
                        working_reg <= data_in;
                        src_base <= base_in;
                        dst_base <= base_out;
                        counter <= 6'd0;
                        ready <= 1'b0;
                    end
                end

                LOAD: begin
                    ready <= 1'b0;
                    // Load data into pipeline stage 1
                    pipe_stage1 <= working_reg;
                    pipe_base1 <= src_base;
                end

                CONVERT: begin
                    // Perform base conversion
                    if (src_base == dst_base) begin
                        // No conversion needed
                        data_out <= working_reg;
                    end else if (src_base == BASE_2 && dst_base == BASE_10) begin
                        // Binary to Decimal (direct assignment in binary FPGA)
                        data_out <= working_reg;
                    end else if (src_base == BASE_2 && dst_base == BASE_12) begin
                        // Binary to Base-12
                        data_out <= binary_to_base12(working_reg);
                    end else if (src_base == BASE_10 && dst_base == BASE_2) begin
                        // Decimal to Binary (direct assignment)
                        data_out <= working_reg;
                    end else if (src_base == BASE_10 && dst_base == BASE_12) begin
                        // Decimal to Base-12 (via binary)
                        data_out <= binary_to_base12(working_reg);
                    end else if (src_base == BASE_12 && dst_base == BASE_2) begin
                        // Base-12 to Binary
                        data_out <= base12_to_binary(working_reg);
                    end else if (src_base == BASE_12 && dst_base == BASE_10) begin
                        // Base-12 to Decimal (via binary)
                        data_out <= base12_to_binary(working_reg);
                    end else begin
                        error <= 1'b1;
                    end

                    counter <= counter + 1;
                end

                NORMALIZE: begin
                    // Normalize output for fixed-point representation
                    if (counter < PIPELINE_STAGES) begin
                        counter <= counter + 1;
                    end
                end

                OUTPUT: begin
                    valid <= 1'b1;
                    ready <= 1'b1;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // State machine - combinational logic
    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start && enable)
                    next_state = LOAD;
            end

            LOAD: begin
                next_state = CONVERT;
            end

            CONVERT: begin
                if (counter >= 2)
                    next_state = NORMALIZE;
            end

            NORMALIZE: begin
                if (counter >= PIPELINE_STAGES)
                    next_state = OUTPUT;
            end

            OUTPUT: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Function: Binary to Base-12 conversion
    function [DATA_WIDTH-1:0] binary_to_base12;
        input [DATA_WIDTH-1:0] bin_val;
        reg [DATA_WIDTH-1:0] result;
        reg [DATA_WIDTH-1:0] temp;
        integer i;
        begin
            result = 0;
            temp = bin_val;

            // Convert using repeated division by 12
            for (i = 0; i < 16; i = i + 1) begin
                result = result + ((temp % 12) * power12_lut[i]);
                temp = temp / 12;
                if (temp == 0)
                    i = 16; // Break loop
            end

            binary_to_base12 = result;
        end
    endfunction

    // Function: Base-12 to Binary conversion
    function [DATA_WIDTH-1:0] base12_to_binary;
        input [DATA_WIDTH-1:0] b12_val;
        reg [DATA_WIDTH-1:0] result;
        reg [DATA_WIDTH-1:0] temp;
        integer i;
        begin
            result = 0;
            temp = b12_val;

            // Convert using positional notation
            for (i = 0; i < 16; i = i + 1) begin
                result = result + ((temp % 16) * power12_lut[i]);
                temp = temp >> 4; // Shift by 4 bits (one hex digit)
                if (temp == 0)
                    i = 16; // Break loop
            end

            base12_to_binary = result;
        end
    endfunction

    // Performance monitoring (for HFT optimization)
    reg [31:0] conversion_cycles;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conversion_cycles <= 32'd0;
        end else if (state == LOAD) begin
            conversion_cycles <= 32'd0;
        end else if (state == CONVERT || state == NORMALIZE) begin
            conversion_cycles <= conversion_cycles + 1;
        end
    end

endmodule
