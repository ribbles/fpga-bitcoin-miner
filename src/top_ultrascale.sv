`default_nettype wire

module top_ultrascale #(
    parameter CLK_FREQ = 100000000,
    parameter INPUT_CLK_FREQ = 700000000,
    parameter BAUD_RATE = 115200,
    parameter CORES = 2,
    parameter LEDS = 5
)(
    input clk_p,
    input clk_n,
    input uart_rx_pin,
    output uart_tx_pin,
    output [LEDS-1:0] led
);

    wire input_clk_ibuf, output_clk_mmcm, output_clk, mmcm_fb, mmcm_locked, sys_rst;

    // 1. Differential SSTL12 to single-ended input buffer
    IBUFDS #(
        .IOSTANDARD("DIFF_SSTL12")
    ) u_ibufds_clk (
        .O  (input_clk_ibuf),
        .I  (clk_p),
        .IB (clk_n)
    );

    // 2. MMCM: 700 MHz -> 100 MHz (PFD = 100 MHz, VCO = 1200 MHz).
    // Output speed is input clock (MHz) × CLKFBOUT_MULT_F ÷ DIVCLK_DIVIDE ÷ CLKOUT0_DIVIDE_F
    // i.e. 700 × 12 ÷ 7 ÷ 12 = 100 MHz
    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(12.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(1.428571),
        .CLKOUT0_DIVIDE_F(12.0),
        .CLKOUT0_DUTY_CYCLE(0.5),  // High time / period: 5.0 ns / 10.0 ns = 0.5 (50%)
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(7),
        .REF_JITTER1(0.010),        // Jitter in UI: 14.3 ps / 1.4286 ns = 0.010
        .STARTUP_WAIT("FALSE")
    ) u_mmcme4_base (
        .CLKOUT0  (output_clk_mmcm),
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUT (mmcm_fb),
        .CLKFBOUTB(),
        .LOCKED   (mmcm_locked),
        .CLKIN1   (input_clk_ibuf),
        .PWRDWN   (1'b0),
        .RST      (1'b0),
        .CLKFBIN  (mmcm_fb)
    );

    // 3. Global clock buffer for the 100 MHz MMCM output.
    BUFG u_bufg_100m (
        .O (output_clk),
        .I (output_clk_mmcm)
    );

    assign sys_rst = ~mmcm_locked;


    // 4. Submodule Instantiation
    top #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .CORES(CORES),
        .LEDS(LEDS)
    ) top_i (
        .clk(output_clk),
        .reset(sys_rst),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .led(led)
    );

endmodule
