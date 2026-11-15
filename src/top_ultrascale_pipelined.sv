`default_nettype wire

module top_ultrascale_pipelined #(
    parameter CLK_FREQ = 200000000,
    parameter INPUT_CLK_FREQ = 700000000,
    parameter BAUD_RATE = 115200,
    parameter CORES = 3,
    parameter LEDS = 5
) (
    input clk_p,
    input clk_n,
    input uart_rx_pin,
    output uart_tx_pin,
    output [LEDS-1:0] led
);
    localparam longint MMCM_TARGET_PFD_FREQ = 100000000;
    localparam longint MMCM_TARGET_VCO_FREQ = 1200000000;
    localparam integer MMCM_DIVCLK_DIVIDE =
        (INPUT_CLK_FREQ + (MMCM_TARGET_PFD_FREQ / 2)) / MMCM_TARGET_PFD_FREQ;
    localparam longint MMCM_MULT_X8 =
        ((MMCM_TARGET_VCO_FREQ * MMCM_DIVCLK_DIVIDE * 8) + (INPUT_CLK_FREQ / 2)) /
        INPUT_CLK_FREQ;
    localparam real MMCM_CLKFBOUT_MULT_F = MMCM_MULT_X8 / 8.0;
    localparam longint MMCM_VCO_FREQ =
        (INPUT_CLK_FREQ * MMCM_MULT_X8) / (MMCM_DIVCLK_DIVIDE * 8);
    localparam integer MMCM_CLKOUT0_DIVIDE =
        (MMCM_VCO_FREQ + (CLK_FREQ / 2)) / CLK_FREQ;
    localparam integer ACTUAL_CLK_FREQ = MMCM_VCO_FREQ / MMCM_CLKOUT0_DIVIDE;
    localparam real MMCM_CLKIN1_PERIOD = 1000000000.0 / INPUT_CLK_FREQ;

    wire input_clk_ibuf;
    wire output_clk_mmcm;
    wire output_clk;
    wire mmcm_fb;
    wire mmcm_locked;

    IBUFDS #(.IOSTANDARD("DIFF_SSTL12")) u_ibufds_clk (
        .O(input_clk_ibuf), .I(clk_p), .IB(clk_n)
    );

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(MMCM_CLKFBOUT_MULT_F),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(MMCM_CLKIN1_PERIOD),
        .CLKOUT0_DIVIDE_F(MMCM_CLKOUT0_DIVIDE),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(MMCM_DIVCLK_DIVIDE),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcme4_base (
        .CLKOUT0(output_clk_mmcm), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(),
        .CLKOUT5(), .CLKOUT6(), .CLKFBOUT(mmcm_fb), .CLKFBOUTB(),
        .LOCKED(mmcm_locked), .CLKIN1(input_clk_ibuf), .PWRDWN(1'b0),
        .RST(1'b0), .CLKFBIN(mmcm_fb)
    );

    BUFG u_bufg_output (.O(output_clk), .I(output_clk_mmcm));

    top_pipelined #(
        .CLK_FREQ(ACTUAL_CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .CORES(CORES), .LEDS(LEDS)
    ) top_i (
        .clk(output_clk), .reset(~mmcm_locked),
        .uart_rx_pin(uart_rx_pin), .uart_tx_pin(uart_tx_pin), .led(led)
    );
endmodule
`default_nettype wire
