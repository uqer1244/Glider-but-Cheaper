`timescale 1ns / 1ps
`default_nettype none
//
// epd_sd_check.v
// Checks the source-driver data bus itself, which epd_selftest.v does not --
// that one counts control edges and never looks at what is on SD[15:0].
//
// Three things are checked over each frame's active window:
//
//   1. sd_or  bitwise OR of SD[15:8]. In 8-bit mode caster drives
//             {8'd0, pixel}, so a constant zero here means OUTPUT_16B did not
//             actually take effect. plan.md 7.4 calls this out as the evidence
//             that the 16-bit conversion is live.
//
//   2. hiz    cycles where any of the eight 2-bit fields is 2'b11. That code
//             floats the source driver; plan.md's expected table says zero.
//
//   3. dup    cycles where the 2x horizontal upscale wiring is inconsistent.
//             caster emits {p3,p3, p2,p2, p1,p1, p0,p0}, so each adjacent pair
//             of fields must be equal. This checks the upscale wiring itself,
//             not just that the bus is busy -- a swapped or shorted line in
//             the top byte shows up here even when sd_or looks healthy.
//
// Counts saturate at 16 bits: any non-zero is already a failure, and a
// saturated value cannot be mistaken for a small one.

module epd_sd_check (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_tick,     // same frame boundary epd_selftest uses
    input  wire [15:0] epd_sd,
    input  wire        epd_sdce0,      // low during the active data window

    output reg  [7:0]  sd_or_o,
    output reg  [15:0] hiz_cnt_o,
    output reg  [15:0] dup_cnt_o
);

    wire active = !epd_sdce0;

    // The eight 2-bit fields, most significant first.
    wire [1:0] f7 = epd_sd[15:14];
    wire [1:0] f6 = epd_sd[13:12];
    wire [1:0] f5 = epd_sd[11:10];
    wire [1:0] f4 = epd_sd[9:8];
    wire [1:0] f3 = epd_sd[7:6];
    wire [1:0] f2 = epd_sd[5:4];
    wire [1:0] f1 = epd_sd[3:2];
    wire [1:0] f0 = epd_sd[1:0];

    wire hiz_now = (f7 == 2'b11) || (f6 == 2'b11) || (f5 == 2'b11) || (f4 == 2'b11) ||
                   (f3 == 2'b11) || (f2 == 2'b11) || (f1 == 2'b11) || (f0 == 2'b11);

    wire dup_now = (f7 != f6) || (f5 != f4) || (f3 != f2) || (f1 != f0);

    reg [7:0]  sd_or;
    reg [15:0] hiz_cnt;
    reg [15:0] dup_cnt;

    always @(posedge clk) begin
        if (rst) begin
            sd_or     <= 8'd0;
            hiz_cnt   <= 16'd0;
            dup_cnt   <= 16'd0;
            sd_or_o   <= 8'd0;
            hiz_cnt_o <= 16'd0;
            dup_cnt_o <= 16'd0;
        end
        else if (frame_tick) begin
            sd_or_o   <= sd_or;
            hiz_cnt_o <= hiz_cnt;
            dup_cnt_o <= dup_cnt;
            // Reseed with this cycle, which already belongs to the new frame.
            sd_or   <= active ? epd_sd[15:8] : 8'd0;
            hiz_cnt <= (active && hiz_now) ? 16'd1 : 16'd0;
            dup_cnt <= (active && dup_now) ? 16'd1 : 16'd0;
        end
        else if (active) begin
            sd_or <= sd_or | epd_sd[15:8];
            if (hiz_now && !(&hiz_cnt)) hiz_cnt <= hiz_cnt + 16'd1;
            if (dup_now && !(&dup_cnt)) dup_cnt <= dup_cnt + 16'd1;
        end
    end

endmodule
`default_nettype wire
