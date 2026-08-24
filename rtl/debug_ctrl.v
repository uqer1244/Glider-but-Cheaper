`timescale 1ns / 1ps
`default_nettype none
//
// debug_ctrl.v
// Button and LED front panel for panel bring-up.
//
// This build has no video input and no working PMIC handshake, so the five
// on-board buttons are the whole user interface and the six LEDs are the whole
// status readout. Everything the operator needs during bring-up is here.
//
// Buttons are active low and debounced. All of them are edge triggered except
// BTN3, whose held level also selects what the two rightmost LEDs display.
//
//   BTN0  DRIVE   toggle the panel drive gate. Starts OFF, so the EPD bus is
//                 idle at power-up and the panel is only driven deliberately.
//   BTN1  STEP    run exactly one frame. Only meaningful when FREERUN is off.
//   BTN2  PATTERN cycle the test pattern (4).
//   BTN3  MODE    cycle the drive mode (4) and issue a SETMODE op. Hold to
//                 read the current mode on LED5:4 instead of the pattern.
//   BTN4  FREERUN toggle 60 Hz free running vs single stepping.
//
//   LED0  heartbeat, ~1 Hz. Proves the PLL is locked and reset is released.
//   LED1  EPD bus self-test, driven straight from epd_selftest.v:
//           solid = pass, N blinks = fail (1 GDCLK, 2 SDLE, 3 SDCE0)
//   LED2  DRIVE is enabled
//   LED3  FREERUN is on
//   LED5:4  pattern index, or mode index while BTN3 is held
//
// Holding BTN2 replaces the whole LED row with epd_selftest's readout of how
// far the SDCE0 active-window count missed its expected value: the index pair
// counts nibble 0..3 and the value four show that nibble, one per second,
// cycling, LSB first. The number is signed, so a frame that scans exactly
// right reads 0, 0, 0, 0. See epd_selftest.v for the encoding and for why the
// error is shown instead of the raw count.
//
// The LED outputs are already inverted here, so they drive the active-low
// board LEDs directly.

module debug_ctrl #(
    parameter CLK_HZ = 40_500_000,
    // ~10 ms. A button has to be stable this long before its level is taken.
    parameter DEBOUNCE = CLK_HZ / 100
)(
    input  wire clk,
    input  wire rst,
    input  wire [4:0] btn_n,        // active low, asynchronous

    input  wire selftest_led,       // from epd_selftest.v, active high
    input  wire [5:0] selftest_diag,// active-window readout, shown on BTN2 held

    output reg  drive_en,
    output reg  freerun,
    output wire step_pulse,
    output reg  [1:0] pattern,
    output reg  [1:0] mode_sel,
    // Toggles on every mode change. A level, not a pulse, so it survives the
    // clock crossing in top.v -- a single cycle pulse through a two flop level
    // synchroniser can be swallowed whole.
    output reg  mode_toggle,

    output wire [5:0] led           // active low, straight to the pins
);

    // ---- synchronise and debounce -------------------------------------------

    reg [4:0] btn_meta = 5'b11111;
    reg [4:0] btn_sync = 5'b11111;
    always @(posedge clk) begin
        btn_meta <= btn_n;
        btn_sync <= btn_meta;
    end

    // btn_level is active high: 1 means pressed.
    reg  [4:0] btn_level = 5'd0;
    reg  [4:0] btn_prev  = 5'd0;
    wire [4:0] btn_press = btn_level & ~btn_prev;

    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin: gen_debounce
            reg [$clog2(DEBOUNCE+1)-1:0] cnt = 0;
            wire raw = ~btn_sync[i];
            always @(posedge clk) begin
                if (rst) begin
                    cnt <= 0;
                    btn_level[i] <= 1'b0;
                end
                else if (raw == btn_level[i]) begin
                    // Already settled at this level, restart the window.
                    cnt <= 0;
                end
                else if (cnt == DEBOUNCE) begin
                    btn_level[i] <= raw;
                    cnt <= 0;
                end
                else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    endgenerate

    always @(posedge clk)
        btn_prev <= rst ? 5'd0 : btn_level;

    // ---- control state -------------------------------------------------------

    assign step_pulse = btn_press[1];

    always @(posedge clk) begin
        if (rst) begin
            // Drive off at power-up. Nothing reaches the panel until BTN0.
            drive_en <= 1'b0;
            freerun  <= 1'b1;
            pattern  <= 2'd0;
            // Mode 0 is fast mono bayer, which is what OP_INIT already leaves
            // every pixel in, so LED5:4 = 00 is truthful before any SETMODE.
            mode_sel <= 2'd0;
            mode_toggle <= 1'b0;
        end
        else begin
            if (btn_press[0]) drive_en <= ~drive_en;
            if (btn_press[4]) freerun  <= ~freerun;
            if (btn_press[2]) pattern  <= pattern + 1'b1;
            if (btn_press[3]) begin
                mode_sel <= mode_sel + 1'b1;
                mode_toggle <= ~mode_toggle;
            end
        end
    end

    // ---- LEDs ----------------------------------------------------------------

    // 8 slots per second, same time base epd_selftest.v uses for its blink code.
    localparam integer SLOT_DIV = CLK_HZ / 8;

    reg [$clog2(SLOT_DIV+1)-1:0] slot_div = 0;
    reg [2:0] slot = 3'd0;
    always @(posedge clk) begin
        if (rst) begin
            slot_div <= 0;
            slot <= 3'd0;
        end
        else if (slot_div == SLOT_DIV - 1) begin
            slot_div <= 0;
            slot <= slot + 1'b1;
        end
        else begin
            slot_div <= slot_div + 1'b1;
        end
    end

    // Toggles every 4 slots -> 1 Hz.
    wire heartbeat = slot[2];

    // BTN3 held swaps LED5:4 from the pattern index to the mode index.
    wire [1:0] sel_display = btn_level[3] ? mode_sel : pattern;

    // BTN2 held hands the row over to the self-test readout. BTN2 is edge
    // triggered for the pattern, so holding it is otherwise unused.
    assign led = btn_level[2] ? ~selftest_diag
                              : ~{sel_display, freerun, drive_en, selftest_led, heartbeat};

endmodule
`default_nettype wire
