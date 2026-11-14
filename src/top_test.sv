`default_nettype wire

// Clock and LED test for the UltraScale+ carrier.
module top_test #(
    parameter CLK_FREQ = 27000000,
    parameter BAUD_RATE = 115200,
    parameter CORES = 1,
    parameter LEDS = 4
)(
    input  clk,
    input reset,
    input  uart_rx_pin,
    output  uart_tx_pin,
    output [LEDS-1:0] led
);
    reg [31:0] blink_count = 'd0;
    reg blink_state = 'b0;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    wire [7:0] rx_data;
    wire rx_valid;
    reg tx_start = 1'b0;
    reg [7:0] tx_data = 8'd0;
    wire tx_busy;
    reg echo_pending = 1'b0;
    reg [7:0] echo_data = 8'd0;

    always @(posedge clk) begin
        if (reset) begin
            blink_count <= 'd0;
            blink_state <= 'b0;
        end else if (blink_count == (CLK_FREQ / 2) - 1) begin
            blink_count <= 'd0;
            blink_state <= ~blink_state;
        end else begin
            blink_count <= blink_count + 'd1;
        end
    end

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) echo_rx (
        .clk(clk),
        .reset(reset),
        .rx(uart_rx_pin),
        .data(rx_data),
        .valid(rx_valid)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) echo_tx (
        .clk(clk),
        .reset(reset),
        .start(tx_start),
        .data(tx_data),
        .tx(uart_tx_pin),
        .busy(tx_busy)
    );

    // Buffer each decoded byte until the transmitter is ready, then send the
    // same byte back as a newly generated 115200-baud UART frame.
    always @(posedge clk) begin
        if (reset) begin
            tx_start <= 1'b0;
            tx_data <= 8'd0;
            echo_pending <= 1'b0;
            echo_data <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            if (!tx_busy && echo_pending) begin
                tx_data <= echo_data;
                tx_start <= 1'b1;
                echo_pending <= 1'b0;
            end

            if (rx_valid) begin
                echo_data <= rx_data;
                echo_pending <= 1'b1;
            end
        end
    end

    // LEDs are active low. The known-working A9 LED is a heartbeat driven by
    // the same MMCM output clock as the UART square-wave counter.
    assign led[0] = ~blink_state;
    assign led[1] = 1'b0;
    assign led[2] = 1'b1;
    assign led[4:3] = 2'b00;

endmodule
