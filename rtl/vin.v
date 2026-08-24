`timescale 1ns / 1ps
`default_nettype none
//
// vin.v
// Video input stage -- internal test pattern generator.
//
// There is no video receiver in this build. The HDMI/DVI path was removed so
// that the EPD output can be verified on its own; this module is the only
// source of pixels and it feeds the EPDC pipeline directly.
//
// The important property is that the source is *pulled* by the EPDC: the
// generator only advances when v_ready is asserted, so it stays word-for-word
// aligned with the scan no matter what the timing is. A generator that free-runs
// on its own raster and ignores v_ready makes the picture shear.
//
// One count of x_cnt is one 4-pixel word, matching the EPDC's 4 pixel/clock
// throughput. The frame restarts on the rising edge of vsync, which top.v
// generates locally at 60 Hz.
//
// Four patterns, selected at runtime by BTN2:
//   0  checkerboard with a walking marker -- geometry and liveness
//   1  horizontal grey ramp               -- dithering and greyscale modes
//   2  one-word vertical stripes          -- fastest SD toggling, worst case
//                                            for the source bus
//   3  solid white                        -- clear the panel

module vin #(
    parameter COLORMODE = "MONO"
)(
    input  wire clk,
    input  wire rst,
    input  wire vsync,
    input  wire [1:0] pattern,
    output wire v_vsync,
    output wire [31:0] v_pixel,
    output wire v_valid,
    input  wire v_ready
);

`include "defines.vh"

    // Pull-driven raster position, in units of one 4-pixel word.
    reg [11:0] x_cnt = 12'd0;
    reg [11:0] y_cnt = 12'd0;
    reg [7:0]  frame_cnt = 8'd0;

    reg vsync_d = 1'b0;
    wire vsync_rise = vsync && !vsync_d;

    always @(posedge clk) begin
        if (rst) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
            frame_cnt <= 8'd0;
            vsync_d <= 1'b0;
        end
        else begin
            vsync_d <= vsync;

            if (vsync_rise) begin
                x_cnt <= 12'd0;
                y_cnt <= 12'd0;
                frame_cnt <= frame_cnt + 1'b1;
            end
            else if (v_ready) begin
                if (x_cnt == (`INPUT_HACT - 1)) begin
                    x_cnt <= 12'd0;
                    if (y_cnt != (`INPUT_VACT - 1))
                        y_cnt <= y_cnt + 1'b1;
                end
                else begin
                    x_cnt <= x_cnt + 1'b1;
                end
            end
        end
    end

    // Pattern 0. x_cnt[5] flips every 32 words (128 source pixels), y_cnt[6]
    // every 64 source lines. With the 2x upscale that is a 256 x 128 block on
    // the panel. On top of it a mid-grey band walks down one step per frame, so
    // both the geometry and the liveness of the scan are visible at a glance.
    wire [7:0] checker_bar = (x_cnt[5] ^ y_cnt[6]) ? 8'hFF : 8'h00;
    wire       checker_mk  = (y_cnt[9:4] == frame_cnt[5:0]);
    wire [7:0] pat_checker = checker_mk ? 8'h80 : checker_bar;

    // Pattern 1. Left to right ramp over the full width. INPUT_HACT is 320
    // words, so the top 8 bits of x_cnt * 256 / 320 would need a divide; taking
    // x_cnt[7:0] and stretching by 5/4 is close enough and costs nothing.
    wire [9:0] ramp_scaled = {2'b0, x_cnt[7:0]} + {4'b0, x_cnt[7:2]};
    wire [7:0] pat_ramp    = ramp_scaled[9:2];

    // Pattern 2. One word black, one word white. After the 2x horizontal
    // upscale this is an 8 pixel period on the panel, the fastest the source
    // bus can be made to alternate from this side.
    wire [7:0] pat_stripe = x_cnt[0] ? 8'hFF : 8'h00;

    // Pattern 3. Solid white, i.e. drive the whole panel clear.
    wire [7:0] pat_white = 8'hFF;

    reg [7:0] shade;
    always @(*) begin
        case (pattern)
        2'd0:    shade = pat_checker;
        2'd1:    shade = pat_ramp;
        2'd2:    shade = pat_stripe;
        default: shade = pat_white;
        endcase
    end

    assign v_vsync = vsync;
    assign v_pixel = {shade, shade, shade, shade};
    // The generator always has a word available.
    assign v_valid = 1'b1;

endmodule
`default_nettype wire
