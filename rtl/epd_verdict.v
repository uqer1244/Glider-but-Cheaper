`timescale 1ns / 1ps
`default_nettype none
//
// epd_verdict.v
// Folds every EPD bus check into one pass flag, one fail code, and one LED.
//
// The checks grew one module at a time -- epd_selftest counts control edges,
// epd_sd_check watches the data bus, epd_line_dup compares line pairs -- and
// each of them only ever reported over UART. That is fine at a desk with a
// laptop attached and useless at a bench, or once the board is in a case. This
// module gives them a single indicator again.
//
//   led solid   everything below passed on the last complete frame
//   1 pulse     GDCLK count      (epd_selftest)
//   2 pulses    SDLE count       (epd_selftest)
//   3 pulses    SDCE0 window     (epd_selftest)
//   4 pulses    SD bus           (epd_sd_check: Hi-Z, or 2x duplication)
//   5 pulses    vertical upscale (epd_line_dup: pair mismatch, or pair count)
//
// Ordered by layer, not severity: a broken scan makes every later check
// meaningless, so the first thing that is wrong is the thing worth reporting.
//
// Sixteen 0.25 s slots per 4 s cycle. The old code had eight, which was enough
// for three pulses but not five: six pulses need twelve slots plus a gap.
//
// Note what is deliberately NOT a fail here. epd_sd_check's sd_or says whether
// anything was driven at all, and Caster stops driving a pixel once it reaches
// its target, so an idle frame is normal and not an error. It is reported over
// UART and left out of the verdict.

module epd_verdict #(
    parameter BLINK_DIV  = 10125000,   // 0.25 s at 40.5 MHz
    parameter EXP_PAIRS  = 960         // VACT / 2
)(
    input  wire        clk,
    input  wire        rst,

    // epd_selftest
    input  wire        st_pass,
    input  wire [1:0]  st_fail,        // 0 ok, 1 gdclk, 2 sdle, 3 sdce0
    // epd_sd_check
    input  wire [15:0] hiz_cnt,
    input  wire [15:0] dup_cnt,
    // epd_line_dup
    input  wire [15:0] vpair_err,
    input  wire [15:0] vpair_cnt,

    output reg         pass,
    output reg  [2:0]  fail_code,
    output wire        led            // active high; debug_ctrl inverts
);

    wire bus_bad  = (hiz_cnt != 16'd0) || (dup_cnt != 16'd0);
    wire vert_bad = (vpair_err != 16'd0) || (vpair_cnt != EXP_PAIRS[15:0]);

    always @(posedge clk) begin
        if (rst) begin
            pass      <= 1'b0;
            fail_code <= 3'd0;
        end
        else if (!st_pass) begin
            pass      <= 1'b0;
            fail_code <= {1'b0, st_fail};
        end
        else if (bus_bad) begin
            pass      <= 1'b0;
            fail_code <= 3'd4;
        end
        else if (vert_bad) begin
            pass      <= 1'b0;
            fail_code <= 3'd5;
        end
        else begin
            pass      <= 1'b1;
            fail_code <= 3'd0;
        end
    end

    // ---- blink code ----
    reg [24:0] blink_div;
    reg [3:0]  slot;
    always @(posedge clk) begin
        if (rst) begin
            blink_div <= 25'd0;
            slot      <= 4'd0;
        end
        else if (blink_div == BLINK_DIV - 1) begin
            blink_div <= 25'd0;
            slot      <= slot + 4'd1;
        end
        else begin
            blink_div <= blink_div + 25'd1;
        end
    end

    // One pulse per unit of fail_code, in the first slots of each cycle: the
    // LED is on for even slots below 2*fail_code and off for odd ones, so the
    // count is what the eye sees.
    wire [4:0] pulse_slots = {2'b0, fail_code} << 1;   // 1->2 ... 5->10
    assign led = pass ? 1'b1
                      : (({1'b0, slot} < pulse_slots) && !slot[0]);

endmodule
`default_nettype wire
