`default_nettype wire

// Compatibility wrapper lets the existing UART protocol test drive reset in
// the same way as the original standalone top-level test.
module top #(
    parameter CLK_FREQ = 27000000,
    parameter BAUD_RATE = 115200,
    parameter CORES = 1,
    parameter LEDS = 6
) (
    input clk,
    input uart_rx_pin,
    output uart_tx_pin,
    output [LEDS-1:0] led
);
    reg [23:0] reset_counter = 24'd0;
    wire reset = !reset_counter[23];

    always @(posedge clk) begin
        if (!reset_counter[23]) begin
            reset_counter <= reset_counter + 24'd1;
        end
    end

    top_pipelined #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .CORES(CORES), .LEDS(LEDS)
    ) impl (
        .clk(clk), .reset(reset), .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin), .led(led)
    );
endmodule
`default_nettype wire
