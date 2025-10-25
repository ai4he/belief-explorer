/*
 * PYNQ Z2 Top-Level Module
 * Multi-Base HFT Optimizer System
 *
 * Interfaces:
 * - AXI4-Lite slave for ARM processor communication
 * - LED indicators for status
 * - Performance monitoring outputs
 */

module pynq_z2_top #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 12
)(
    // System signals
    input wire clk,
    input wire rst_n,

    // AXI4-Lite Slave Interface
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output wire s_axi_awready,

    input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,

    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,

    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output wire s_axi_arready,

    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,

    // PYNQ Z2 Board LEDs for status indication
    output wire [3:0] led,

    // Performance monitoring (optional debug outputs)
    output wire optimizer_busy,
    output wire trade_signal
);

    // Register addresses
    localparam ADDR_CONTROL       = 12'h000;  // Control register
    localparam ADDR_STATUS        = 12'h004;  // Status register
    localparam ADDR_BID_PRICE_H   = 12'h008;  // Bid price high 32 bits
    localparam ADDR_BID_PRICE_L   = 12'h00C;  // Bid price low 32 bits
    localparam ADDR_ASK_PRICE_H   = 12'h010;  // Ask price high 32 bits
    localparam ADDR_ASK_PRICE_L   = 12'h014;  // Ask price low 32 bits
    localparam ADDR_LAST_PRICE_H  = 12'h018;  // Last price high 32 bits
    localparam ADDR_LAST_PRICE_L  = 12'h01C;  // Last price low 32 bits
    localparam ADDR_BID_SIZE      = 12'h020;  // Bid size
    localparam ADDR_ASK_SIZE      = 12'h024;  // Ask size
    localparam ADDR_BASE_SELECT   = 12'h028;  // Base selection
    localparam ADDR_RISK_LIMIT    = 12'h02C;  // Risk limit
    localparam ADDR_LATENCY_BUDG  = 12'h030;  // Latency budget
    localparam ADDR_STRATEGY_ID   = 12'h034;  // Strategy ID
    localparam ADDR_RESULT_PRICE_H = 12'h038; // Result entry price high
    localparam ADDR_RESULT_PRICE_L = 12'h03C; // Result entry price low
    localparam ADDR_EXIT_PRICE_H  = 12'h040;  // Result exit price high
    localparam ADDR_EXIT_PRICE_L  = 12'h044;  // Result exit price low
    localparam ADDR_QUANTITY      = 12'h048;  // Optimal quantity
    localparam ADDR_EXPECTED_PROFIT = 12'h04C; // Expected profit
    localparam ADDR_CONFIDENCE    = 12'h050;  // Confidence score
    localparam ADDR_BASE_USED     = 12'h054;  // Base used in calculation
    localparam ADDR_CYCLES_TAKEN  = 12'h058;  // Computation cycles
    localparam ADDR_BASE12_ADV    = 12'h05C;  // Base-12 advantage
    localparam ADDR_COMP_PER_SEC  = 12'h060;  // Computations per second

    // AXI4-Lite signals
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg axi_rvalid;

    // Register bank
    reg [31:0] control_reg;
    reg [31:0] status_reg;
    reg [31:0] bid_price_h;
    reg [31:0] bid_price_l;
    reg [31:0] ask_price_h;
    reg [31:0] ask_price_l;
    reg [31:0] last_price_h;
    reg [31:0] last_price_l;
    reg [31:0] bid_size_reg;
    reg [31:0] ask_size_reg;
    reg [31:0] base_select_reg;
    reg [31:0] risk_limit_reg;
    reg [31:0] latency_budget_reg;
    reg [31:0] strategy_id_reg;

    // Result registers (read-only from ARM side)
    wire [31:0] result_price_h;
    wire [31:0] result_price_l;
    wire [31:0] exit_price_h;
    wire [31:0] exit_price_l;
    wire [31:0] quantity_result;
    wire [31:0] expected_profit_result;
    wire [31:0] confidence_result;
    wire [31:0] base_used_result;
    wire [31:0] cycles_taken_result;
    wire [31:0] base12_adv_result;
    wire [31:0] comp_per_sec_result;

    // Control bits
    wire start_optimization;
    wire enable;
    assign start_optimization = control_reg[0];
    assign enable = control_reg[1];

    // Status bits
    wire optimization_complete;
    wire trade_signal_valid;
    assign status_reg = {14'd0, optimizer_busy, trade_signal_valid,
                        14'd0, optimization_complete, 1'b1}; // Bit 0: ready

    // HFT Optimizer Core connections
    wire [47:0] bid_price_full;
    wire [47:0] ask_price_full;
    wire [47:0] last_price_full;
    wire [47:0] optimal_entry_price;
    wire [47:0] optimal_exit_price;
    wire [31:0] optimal_quantity;
    wire [1:0] optimal_base_used;
    wire [31:0] expected_profit;
    wire [15:0] confidence_score;
    wire [31:0] cycles_taken;
    wire [31:0] base12_advantage;
    wire [31:0] computations_per_sec;

    // Combine high and low registers for 48-bit prices
    assign bid_price_full = {bid_price_h[15:0], bid_price_l};
    assign ask_price_full = {ask_price_h[15:0], ask_price_l};
    assign last_price_full = {last_price_h[15:0], last_price_l};

    // Split 48-bit results into 32-bit registers
    assign result_price_h = {16'd0, optimal_entry_price[47:32]};
    assign result_price_l = optimal_entry_price[31:0];
    assign exit_price_h = {16'd0, optimal_exit_price[47:32]};
    assign exit_price_l = optimal_exit_price[31:0];
    assign quantity_result = optimal_quantity;
    assign expected_profit_result = expected_profit;
    assign confidence_result = {16'd0, confidence_score};
    assign base_used_result = {30'd0, optimal_base_used};
    assign cycles_taken_result = cycles_taken;
    assign base12_adv_result = base12_advantage;
    assign comp_per_sec_result = computations_per_sec;

    // Instantiate HFT Optimizer Core
    hft_optimizer_core #(
        .DATA_WIDTH(64),
        .PRICE_WIDTH(48),
        .QTY_WIDTH(32),
        .NUM_EXECUTION_UNITS(4),
        .STRATEGY_DEPTH(8)
    ) optimizer (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .bid_price(bid_price_full),
        .ask_price(ask_price_full),
        .bid_size(bid_size_reg),
        .ask_size(ask_size_reg),
        .last_price(last_price_full),
        .market_data_valid(1'b1),
        .base_select(base_select_reg[1:0]),
        .risk_limit(risk_limit_reg),
        .latency_budget_ns(latency_budget_reg[15:0]),
        .strategy_id(strategy_id_reg[7:0]),
        .start_optimization(start_optimization),
        .optimization_complete(optimization_complete),
        .cycles_taken(cycles_taken),
        .optimal_entry_price(optimal_entry_price),
        .optimal_exit_price(optimal_exit_price),
        .optimal_quantity(optimal_quantity),
        .optimal_base_used(optimal_base_used),
        .expected_profit(expected_profit),
        .confidence_score(confidence_score),
        .trade_signal_valid(trade_signal_valid),
        .base12_advantage(base12_advantage),
        .computations_per_sec(computations_per_sec)
    );

    // LED status indicators
    assign led[0] = enable;                    // LED0: System enabled
    assign led[1] = optimization_complete;     // LED1: Optimization done
    assign led[2] = trade_signal_valid;        // LED2: Valid trade signal
    assign led[3] = optimizer_busy;            // LED3: Optimizer busy

    assign optimizer_busy = !optimization_complete && start_optimization;
    assign trade_signal = trade_signal_valid;

    // AXI4-Lite Interface Implementation
    assign s_axi_awready = axi_awready;
    assign s_axi_wready = axi_wready;
    assign s_axi_bresp = axi_bresp;
    assign s_axi_bvalid = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata = axi_rdata;
    assign s_axi_rresp = axi_rresp;
    assign s_axi_rvalid = axi_rvalid;

    // AXI Write Address Channel
    always @(posedge clk) begin
        if (!rst_n) begin
            axi_awready <= 1'b0;
            axi_awaddr <= 0;
        end else begin
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_awaddr <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // AXI Write Data Channel
    always @(posedge clk) begin
        if (!rst_n) begin
            axi_wready <= 1'b0;
        end else begin
            if (~axi_wready && s_axi_wvalid && s_axi_awvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end
    end

    // AXI Write Response Channel
    always @(posedge clk) begin
        if (!rst_n) begin
            axi_bvalid <= 0;
            axi_bresp <= 2'b0;
        end else begin
            if (axi_awready && s_axi_awvalid && ~axi_bvalid && axi_wready && s_axi_wvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp <= 2'b0; // OKAY response
            end else begin
                if (s_axi_bready && axi_bvalid) begin
                    axi_bvalid <= 1'b0;
                end
            end
        end
    end

    // AXI Read Address Channel
    always @(posedge clk) begin
        if (!rst_n) begin
            axi_arready <= 1'b0;
            axi_araddr <= 0;
        end else begin
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // AXI Read Data Channel
    always @(posedge clk) begin
        if (!rst_n) begin
            axi_rvalid <= 0;
            axi_rresp <= 0;
        end else begin
            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b0; // OKAY response
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // Register write logic
    always @(posedge clk) begin
        if (!rst_n) begin
            control_reg <= 32'd0;
            bid_price_h <= 32'd0;
            bid_price_l <= 32'd0;
            ask_price_h <= 32'd0;
            ask_price_l <= 32'd0;
            last_price_h <= 32'd0;
            last_price_l <= 32'd0;
            bid_size_reg <= 32'd0;
            ask_size_reg <= 32'd0;
            base_select_reg <= 32'd0;
            risk_limit_reg <= 32'd100000;
            latency_budget_reg <= 32'd100;
            strategy_id_reg <= 32'd0;
        end else begin
            // Auto-clear start bit after one cycle
            if (control_reg[0])
                control_reg[0] <= 1'b0;

            if (axi_wready && s_axi_wvalid && axi_awready && s_axi_awvalid) begin
                case (axi_awaddr)
                    ADDR_CONTROL:      control_reg <= s_axi_wdata;
                    ADDR_BID_PRICE_H:  bid_price_h <= s_axi_wdata;
                    ADDR_BID_PRICE_L:  bid_price_l <= s_axi_wdata;
                    ADDR_ASK_PRICE_H:  ask_price_h <= s_axi_wdata;
                    ADDR_ASK_PRICE_L:  ask_price_l <= s_axi_wdata;
                    ADDR_LAST_PRICE_H: last_price_h <= s_axi_wdata;
                    ADDR_LAST_PRICE_L: last_price_l <= s_axi_wdata;
                    ADDR_BID_SIZE:     bid_size_reg <= s_axi_wdata;
                    ADDR_ASK_SIZE:     ask_size_reg <= s_axi_wdata;
                    ADDR_BASE_SELECT:  base_select_reg <= s_axi_wdata;
                    ADDR_RISK_LIMIT:   risk_limit_reg <= s_axi_wdata;
                    ADDR_LATENCY_BUDG: latency_budget_reg <= s_axi_wdata;
                    ADDR_STRATEGY_ID:  strategy_id_reg <= s_axi_wdata;
                    default: begin end
                endcase
            end
        end
    end

    // Register read logic
    always @(*) begin
        case (axi_araddr)
            ADDR_CONTROL:       axi_rdata = control_reg;
            ADDR_STATUS:        axi_rdata = status_reg;
            ADDR_BID_PRICE_H:   axi_rdata = bid_price_h;
            ADDR_BID_PRICE_L:   axi_rdata = bid_price_l;
            ADDR_ASK_PRICE_H:   axi_rdata = ask_price_h;
            ADDR_ASK_PRICE_L:   axi_rdata = ask_price_l;
            ADDR_LAST_PRICE_H:  axi_rdata = last_price_h;
            ADDR_LAST_PRICE_L:  axi_rdata = last_price_l;
            ADDR_BID_SIZE:      axi_rdata = bid_size_reg;
            ADDR_ASK_SIZE:      axi_rdata = ask_size_reg;
            ADDR_BASE_SELECT:   axi_rdata = base_select_reg;
            ADDR_RISK_LIMIT:    axi_rdata = risk_limit_reg;
            ADDR_LATENCY_BUDG:  axi_rdata = latency_budget_reg;
            ADDR_STRATEGY_ID:   axi_rdata = strategy_id_reg;
            ADDR_RESULT_PRICE_H: axi_rdata = result_price_h;
            ADDR_RESULT_PRICE_L: axi_rdata = result_price_l;
            ADDR_EXIT_PRICE_H:  axi_rdata = exit_price_h;
            ADDR_EXIT_PRICE_L:  axi_rdata = exit_price_l;
            ADDR_QUANTITY:      axi_rdata = quantity_result;
            ADDR_EXPECTED_PROFIT: axi_rdata = expected_profit_result;
            ADDR_CONFIDENCE:    axi_rdata = confidence_result;
            ADDR_BASE_USED:     axi_rdata = base_used_result;
            ADDR_CYCLES_TAKEN:  axi_rdata = cycles_taken_result;
            ADDR_BASE12_ADV:    axi_rdata = base12_adv_result;
            ADDR_COMP_PER_SEC:  axi_rdata = comp_per_sec_result;
            default:            axi_rdata = 32'd0;
        endcase
    end

endmodule
