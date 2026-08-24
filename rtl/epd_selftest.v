`timescale 1ns / 1ps
`default_nettype none
//
// epd_selftest.v
// Self-check on the EPD output bus.
//
// Watches the pins the FPGA actually drives and counts, over one frame:
//   - GDCLK rising edges   should equal vtotal (one gate clock per line)
//   - SDLE rising edges    should equal vtotal (one latch per line)
//   - SDCE0 low cycles     should equal hact * vact (the active data window)
//
// This is what a logic analyser would be used for, done in the fabric instead,
// so the EPD bus can be verified with nothing but the on-board LED.
//
//   pass = 1            all three counts matched on the last complete frame
//   pass = 0            led blinks a code: 1 = GDCLK, 2 = SDLE, 3 = SDCE0
//
// The frame boundary is taken from GDSP, which goes low for exactly the vsync
// lines once per frame.

module epd_selftest #(
    parameter EXP_VTOTAL = 1927,
    parameter EXP_ACTIVE = 614400,
    parameter BLINK_DIV  = 10125000   // 0.25 s at 40.5 MHz
)(
    input  wire clk,
    input  wire rst,
    // EPD outputs under test
    input  wire epd_gdsp,
    input  wire epd_gdclk,
    input  wire epd_sdle,
    input  wire epd_sdce0,
    // Result
    output reg        pass,
    output reg  [1:0] fail_code,   // 0 ok, 1 gdclk, 2 sdle, 3 sdce0
    output wire [5:0] diag,        // readout of the last active-window error
    output wire       frame_done,  // one pulse per completed frame, for logging
    // Latched counts for the frame frame_done just announced, for a logger
    output wire [11:0] last_gdclk_o,
    output wire [11:0] last_sdle_o,
    output wire [20:0] last_active_o,
    output wire signed [21:0] err_o,
    output wire       led          // ready to drive an active-low LED pin
);

    reg gdsp_d, gdclk_d, sdle_d;

    reg [11:0] gdclk_cnt;
    reg [11:0] sdle_cnt;
    reg [20:0] active_cnt;
    // Snapshot taken at each frame boundary. The live counter sweeps 0..
    // EXP_ACTIVE every frame, far too fast for the eye -- the readout below
    // must show the completed frame's count, which holds still until the
    // next frame ends.
    reg [20:0] last_active;
    reg [11:0] last_gdclk;
    reg [11:0] last_sdle;

    // Rising edge of GDSP = vsync just ended = start of a new frame
    wire frame_tick = epd_gdsp && !gdsp_d;

    // Exported so a logger can sample the latched counters exactly when they
    // are refreshed, rather than guessing at a frame boundary of its own.
    // Delayed one cycle: on frame_tick itself the last_* registers are still
    // being written and hold the previous frame, so a logger sampling then
    // would report every frame one late.
    reg frame_done_r;
    always @(posedge clk) frame_done_r <= rst ? 1'b0 : frame_tick;
    assign frame_done = frame_done_r;

    assign last_gdclk_o  = last_gdclk;
    assign last_sdle_o   = last_sdle;
    assign last_active_o = last_active;
    // err_o is assigned below, where err_full is declared.

    always @(posedge clk) begin
        if (rst) begin
            gdsp_d     <= 1'b1;
            gdclk_d    <= 1'b0;
            sdle_d     <= 1'b0;
            gdclk_cnt  <= 12'd0;
            sdle_cnt   <= 12'd0;
            active_cnt <= 21'd0;
            last_active <= 21'd0;
            last_gdclk  <= 12'd0;
            last_sdle   <= 12'd0;
            pass       <= 1'b0;
            fail_code  <= 2'd0;
        end
        else begin
            gdsp_d  <= epd_gdsp;
            gdclk_d <= epd_gdclk;
            sdle_d  <= epd_sdle;

            if (frame_tick) begin
                // Evaluate the frame that just ended, then restart the counters.
                // The edge that lands on this very cycle belongs to the new
                // frame, so seed the counters with it.
                last_gdclk  <= gdclk_cnt;
                last_sdle   <= sdle_cnt;
                last_active <= active_cnt;

                if (gdclk_cnt != EXP_VTOTAL) begin
                    pass <= 1'b0; fail_code <= 2'd1;
                end
                else if (sdle_cnt != EXP_VTOTAL) begin
                    pass <= 1'b0; fail_code <= 2'd2;
                end
                else if (active_cnt != EXP_ACTIVE) begin
                    pass <= 1'b0; fail_code <= 2'd3;
                end
                else begin
                    pass <= 1'b1; fail_code <= 2'd0;
                end

                gdclk_cnt  <= (epd_gdclk && !gdclk_d) ? 12'd1 : 12'd0;
                sdle_cnt   <= (epd_sdle  && !sdle_d)  ? 12'd1 : 12'd0;
                active_cnt <= (!epd_sdce0)            ? 21'd1 : 21'd0;
            end
            else begin
                if (epd_gdclk && !gdclk_d) gdclk_cnt  <= gdclk_cnt + 1'b1;
                if (epd_sdle  && !sdle_d)  sdle_cnt   <= sdle_cnt + 1'b1;
                if (!epd_sdce0)            active_cnt <= active_cnt + 1'b1;
            end
        end
    end

    // ---- active window readout ----
    // A blink code cannot express the size of a count mismatch, so while the
    // operator holds the readout button the six LEDs show a hex number one
    // nibble at a time:
    //
    //   index pair  = nibble index 0..3, LSB first
    //   value four  = that nibble
    //
    // What is shown is the *error*, last_active - EXP_ACTIVE, in two's
    // complement -- not the raw count. The raw count needs 21 bits (614400 =
    // 0x96000, five nibbles) but only four fit here: two LEDs index plus four
    // LEDs value already uses all six, so a raw readout would silently drop
    // the top bits and could not tell 0x96000 from 0x06000. The error is the
    // number actually wanted anyway, and it is small when the scan is close.
    //
    //   all four nibbles 0   counts match exactly
    //   0x0140               140 hex = 320 cycles long = one extra line
    //   0xFEC0               -320, i.e. one line short
    //   0x7FFF / 0x8000      error too large for 16 bits (saturated)
    //
    // Divide the error by the per-line active width (320 for the ED115) to get
    // whole lines; a non-integer result means the miss is inside a line rather
    // than a whole line going missing.
    //
    // Polarity: these six bits are logic-high-means-lit. debug_ctrl inverts
    // them for the active-low board LEDs, so a lit LED is a 1 here.
    localparam signed [21:0] EXP_ACTIVE_S = EXP_ACTIVE;

    wire signed [21:0] err_full = $signed({1'b0, last_active}) - EXP_ACTIVE_S;

    // Saturate rather than wrap: a wrapped value would look like a small,
    // believable error and send the next session chasing the wrong number.
    wire err_fits = (err_full[21:15] == {7{err_full[15]}});
    wire [15:0] err16 = err_fits ? err_full[15:0]
                      : (err_full[21] ? 16'h8000 : 16'h7FFF);

    assign err_o = err_full;

    reg [25:0] nib_div;
    reg [1:0]  nib_idx;
    always @(posedge clk) begin
        if (rst) begin
            nib_div <= 26'd0;
            nib_idx <= 2'd0;
        end
        else if (nib_div == BLINK_DIV * 4 - 1) begin
            nib_div <= 26'd0;
            nib_idx <= nib_idx + 2'd1;
        end
        else begin
            nib_div <= nib_div + 26'd1;
        end
    end

    wire [3:0] nib_val = err16 >> (nib_idx * 4);
    assign diag = {nib_idx, nib_val};

    // ---- blink code ----
    // Eight 0.25 s slots per 2 s cycle. Solid when passing, otherwise one
    // pulse per fail_code in the first slots of each cycle.
    reg [24:0] blink_div;
    reg [2:0]  slot;
    always @(posedge clk) begin
        if (rst) begin
            blink_div <= 25'd0;
            slot      <= 3'd0;
        end
        else if (blink_div == BLINK_DIV - 1) begin
            blink_div <= 25'd0;
            slot      <= slot + 1'b1;
        end
        else begin
            blink_div <= blink_div + 1'b1;
        end
    end

    wire [3:0] pulse_slots = {2'b0, fail_code} << 1; // 1->2, 2->4, 3->6
    assign led = pass ? 1'b1
                      : (({1'b0, slot} < pulse_slots) && !slot[0]);

endmodule
`default_nettype wire
