`timescale 1ns / 1ps
`default_nettype none
//
// epd_line_dup.v
// Checks the vertical half of the 2x upscale, which epd_sd_check.v cannot see.
//
// caster does vertical doubling through a line buffer:
//
//   even line (v_cnt_offset[0]==0)  output current_pixel, and store it
//   odd line  (v_cnt_offset[0]==1)  output scale_line_buf[scale_ptr + 1]
//
// so every odd line must repeat the even line before it, word for word. That
// is a property of the emitted bus, so it can be checked in fabric with no
// panel and no knowledge of what the picture is supposed to be.
//
// Each line's active words are folded into a CRC-32 style signature. On even
// lines the signature is kept; on odd lines it is compared. A mismatch means
// the line buffer, its read pointer, or the +1 delay compensation is wrong --
// exactly the class of bug that produces a picture squashed or torn
// vertically while every control-signal count still looks perfect.
//
//   pairs  number of line pairs compared in the frame. 1920 panel lines
//          means 960 pairs (0x3c0). A short count means lines are going
//          missing even though GDCLK still counts 1927.
//   errs   pairs whose signatures differed. Expected 0.
//
// Both counters saturate at 16 bits.

module epd_line_dup (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_tick,
    input  wire [15:0] epd_sd,
    input  wire        epd_sdce0,     // low during the active data window
    input  wire        epd_sdle,      // one pulse per line

    output reg  [15:0] pairs_o,
    output reg  [15:0] errs_o
);

    localparam [31:0] POLY = 32'h04C11DB7;

    wire active = !epd_sdce0;

    reg  sdle_d;
    wire line_end = epd_sdle && !sdle_d;

    reg [31:0] sig;          // signature of the line being scanned
    reg [31:0] even_sig;     // kept from the last even line
    reg        parity;       // 0 = next completed line is an even one
    reg        had_data;     // this line carried active words

    reg [15:0] pairs, errs;

    wire [31:0] sig_next = {sig[30:0], 1'b0}
                         ^ (sig[31] ? POLY : 32'd0)
                         ^ {16'd0, epd_sd};

    always @(posedge clk) begin
        if (rst) begin
            sdle_d   <= 1'b0;
            sig      <= 32'd0;
            even_sig <= 32'd0;
            parity   <= 1'b0;
            had_data <= 1'b0;
            pairs    <= 16'd0;
            errs     <= 16'd0;
            pairs_o  <= 16'd0;
            errs_o   <= 16'd0;
        end
        else begin
            sdle_d <= epd_sdle;

            if (frame_tick) begin
                pairs_o  <= pairs;
                errs_o   <= errs;
                pairs    <= 16'd0;
                errs     <= 16'd0;
                sig      <= 32'd0;
                parity   <= 1'b0;
                had_data <= 1'b0;
            end
            else if (line_end) begin
                // Blanking lines carry no active words; they must not consume
                // a parity slot or every pair after the first would compare
                // an even line against another even line.
                if (had_data) begin
                    if (!parity) begin
                        even_sig <= sig;
                    end
                    else begin
                        if (!(&pairs)) pairs <= pairs + 16'd1;
                        if ((sig != even_sig) && !(&errs)) errs <= errs + 16'd1;
                    end
                    parity <= ~parity;
                end
                sig      <= 32'd0;
                had_data <= 1'b0;
            end
            else if (active) begin
                sig      <= sig_next;
                had_data <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
