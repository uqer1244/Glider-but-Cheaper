`timescale 1ns / 1ps
`default_nettype none
//
// sysclock.v
// Gowin rPLL based clock generation for the Tang Primer 20K.
//
// CLK_IN is the on-board 27 MHz oscillator.
//
//   FCLKOUT = FCLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1) = 27 * 3 / 2 = 40.5 MHz
//   PFD     = FCLKIN / (IDIV_SEL+1)                 = 27 / 2     = 13.5 MHz   (>= 3 MHz)
//   VCO     = FCLKOUT * ODIV_SEL                    = 40.5 * 16  =  648 MHz   (400..1200)
//
// 40.5 MHz drives one frame of 344 x 1927 = 662,888 clocks in 16.37 ms. The
// vsync period in top.v pads that to exactly 60.0 Hz.
//
// clk_ddr is kept as a separate port for the DDR3 controller. Until the real
// Gowin DDR3 IP replaces mig_wrapper it simply follows clk_sys - the memory
// clock has to come out of the DDR3 IP's own PLL, not from here.

module sysclock(
    input  wire clk_in,
    output wire clk_ddr,
    output wire clk_sys,
    input  wire reset,
    output wire locked
);

`ifdef SIMULATION
    assign clk_sys = clk_in;
    assign locked  = 1'b1;
`else
    rPLL #(
        .FCLKIN("27"),
        .DEVICE("GW2A-18C"),
        .IDIV_SEL(1),           // IDIV  = 2
        .FBDIV_SEL(2),          // FBDIV = 3
        .ODIV_SEL(16),
        .DYN_SDIV_SEL(2),
        .PSDA_SEL("0000"),
        .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1),
        .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"),
        .CLKOUT_BYPASS("false"),
        .CLKOUTP_BYPASS("false"),
        .CLKOUTD_BYPASS("false"),
        .DYN_FBDIV_SEL("false"),
        .DYN_IDIV_SEL("false"),
        .DYN_ODIV_SEL("false"),
        .CLKOUTD_SRC("CLKOUT"),
        .CLKOUTD3_SRC("CLKOUT")
    ) pll (
        .CLKOUT(clk_sys),
        .LOCK(locked),
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(reset),
        .RESET_P(1'b0),
        .CLKIN(clk_in),
        .CLKFB(1'b0),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0)
    );
`endif

    assign clk_ddr = clk_sys;

endmodule
`default_nettype wire
