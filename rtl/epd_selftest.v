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
    output wire       led          // ready to drive an active-low LED pin
);

    reg gdsp_d, gdclk_d, sdle_d;

    reg [11:0] gdclk_cnt;
    reg [11:0] sdle_cnt;
    reg [20:0] active_cnt;

    // Rising edge of GDSP = vsync just ended = start of a new frame
    wire frame_tick = epd_gdsp && !gdsp_d;

    always @(posedge clk) begin
        if (rst) begin
            gdsp_d     <= 1'b1;
            gdclk_d    <= 1'b0;
            sdle_d     <= 1'b0;
            gdclk_cnt  <= 12'd0;
            sdle_cnt   <= 12'd0;
            active_cnt <= 21'd0;
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
