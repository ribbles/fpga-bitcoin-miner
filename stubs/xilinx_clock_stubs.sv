// Lightweight simulation stubs for Xilinx clocking primitives.

`default_nettype wire

module IBUFDS #(
    parameter DIFF_TERM = "FALSE",
    parameter IBUF_LOW_PWR = "TRUE",
    parameter IOSTANDARD = "DEFAULT"
)(
    input I,
    input IB,
    output O
);
    assign O = I;
endmodule

module MMCME2_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter real CLKIN1_PERIOD = 0.0,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter real CLKFBOUT_MULT_F = 1.0,
    parameter real CLKOUT0_DIVIDE_F = 1.0,
    parameter real CLKOUT0_DUTY_CYCLE = 0.5,
    parameter real CLKOUT0_PHASE = 0.0,
    parameter integer CLKOUT1_DIVIDE = 1,
    parameter integer CLKOUT2_DIVIDE = 1,
    parameter integer CLKOUT3_DIVIDE = 1,
    parameter integer CLKOUT4_DIVIDE = 1,
    parameter integer CLKOUT5_DIVIDE = 1,
    parameter integer CLKOUT6_DIVIDE = 1,
    parameter real REF_JITTER1 = 0.0,
    parameter STARTUP_WAIT = "FALSE"
)(
    input CLKIN1,
    input CLKFBIN,
    input RST,
    input PWRDWN,
    output CLKFBOUT,
    output CLKFBOUTB,
    output CLKOUT0,
    output CLKOUT0B,
    output CLKOUT1,
    output CLKOUT1B,
    output CLKOUT2,
    output CLKOUT2B,
    output CLKOUT3,
    output CLKOUT3B,
    output CLKOUT4,
    output CLKOUT5,
    output CLKOUT6,
    output LOCKED
);
    assign CLKFBOUT = CLKIN1;
    assign CLKOUT0 = CLKIN1;
    assign LOCKED = !RST && !PWRDWN;
endmodule

module MMCME3_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter real CLKIN1_PERIOD = 0.0,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter real CLKFBOUT_MULT_F = 1.0,
    parameter real CLKOUT0_DIVIDE_F = 1.0,
    parameter real CLKOUT0_DUTY_CYCLE = 0.5,
    parameter real CLKOUT0_PHASE = 0.0,
    parameter real REF_JITTER1 = 0.0,
    parameter STARTUP_WAIT = "FALSE"
)(
    input CLKIN1,
    input CLKFBIN,
    input RST,
    input PWRDWN,
    output CLKFBOUT,
    output CLKFBOUTB,
    output CLKOUT0,
    output CLKOUT0B,
    output CLKOUT1,
    output CLKOUT1B,
    output CLKOUT2,
    output CLKOUT2B,
    output CLKOUT3,
    output CLKOUT3B,
    output CLKOUT4,
    output CLKOUT5,
    output CLKOUT6,
    output LOCKED
);
    assign CLKFBOUT = CLKIN1;
    assign CLKOUT0 = CLKIN1;
    assign LOCKED = !RST && !PWRDWN;
endmodule

module MMCME4_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter real CLKFBOUT_MULT_F = 5.0,
    parameter real CLKFBOUT_PHASE = 0.0,
    parameter real CLKIN1_PERIOD = 0.0,
    parameter real CLKOUT0_DIVIDE_F = 1.0,
    parameter real CLKOUT0_DUTY_CYCLE = 0.5,
    parameter real CLKOUT0_PHASE = 0.0,
    parameter integer CLKOUT1_DIVIDE = 1,
    parameter real CLKOUT1_DUTY_CYCLE = 0.5,
    parameter real CLKOUT1_PHASE = 0.0,
    parameter integer CLKOUT2_DIVIDE = 1,
    parameter real CLKOUT2_DUTY_CYCLE = 0.5,
    parameter real CLKOUT2_PHASE = 0.0,
    parameter integer CLKOUT3_DIVIDE = 1,
    parameter real CLKOUT3_DUTY_CYCLE = 0.5,
    parameter real CLKOUT3_PHASE = 0.0,
    parameter CLKOUT4_CASCADE = "FALSE",
    parameter integer CLKOUT4_DIVIDE = 1,
    parameter real CLKOUT4_DUTY_CYCLE = 0.5,
    parameter real CLKOUT4_PHASE = 0.0,
    parameter integer CLKOUT5_DIVIDE = 1,
    parameter real CLKOUT5_DUTY_CYCLE = 0.5,
    parameter real CLKOUT5_PHASE = 0.0,
    parameter integer CLKOUT6_DIVIDE = 1,
    parameter real CLKOUT6_DUTY_CYCLE = 0.5,
    parameter real CLKOUT6_PHASE = 0.0,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter IS_CLKFBIN_INVERTED = 1'b0,
    parameter IS_CLKIN1_INVERTED = 1'b0,
    parameter IS_PWRDWN_INVERTED = 1'b0,
    parameter IS_RST_INVERTED = 1'b0,
    parameter real REF_JITTER1 = 0.010,
    parameter STARTUP_WAIT = "FALSE"
)(
    input CLKIN1,
    input CLKFBIN,
    input RST,
    input PWRDWN,
    output CLKFBOUT,
    output CLKFBOUTB,
    output CLKOUT0,
    output CLKOUT0B,
    output CLKOUT1,
    output CLKOUT1B,
    output CLKOUT2,
    output CLKOUT2B,
    output CLKOUT3,
    output CLKOUT3B,
    output CLKOUT4,
    output CLKOUT5,
    output CLKOUT6,
    output LOCKED
);
    assign CLKFBOUT = CLKIN1;
    assign CLKOUT0 = CLKIN1;
    assign LOCKED = !RST && !PWRDWN;
endmodule

// Lightweight behavioral model for the UltraScale global clock divider.
// The hardware test uses the supported even divide value of 8.
module BUFGCE_DIV #(
    parameter integer BUFGCE_DIVIDE = 1,
    parameter CE_TYPE = "SYNC",
    parameter HARDSYNC_CLR = "FALSE",
    parameter IS_CE_INVERTED = 1'b0,
    parameter IS_CLR_INVERTED = 1'b0,
    parameter IS_I_INVERTED = 1'b0,
    parameter SIM_DEVICE = "ULTRASCALE",
    parameter STARTUP_SYNC = "FALSE"
)(
    output O,
    input CE,
    input CLR,
    input I
);
    integer divide_count = 0;
    reg divided_clock = 1'b0;

    always @(posedge I or posedge CLR) begin
        if (CLR) begin
            divide_count <= 0;
            divided_clock <= 1'b0;
        end else if (CE && BUFGCE_DIVIDE > 1) begin
            if (divide_count == (BUFGCE_DIVIDE / 2) - 1) begin
                divide_count <= 0;
                divided_clock <= ~divided_clock;
            end else begin
                divide_count <= divide_count + 1;
            end
        end
    end

    assign O = (BUFGCE_DIVIDE == 1) ? I : divided_clock;
endmodule

`default_nettype wire
