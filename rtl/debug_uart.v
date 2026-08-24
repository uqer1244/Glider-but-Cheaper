`timescale 1ns / 1ps
`default_nettype none
//
// debug_uart.v
// Prints one fixed-width line of epd_selftest's counters per emitted frame.
//
//   G=787 S=787 A=096000 E=+000000 P=1 F=0 U=ff Z=0000 D=0000 V=0000 L=03c0 N=0 M=0
//   |     |     |        |         |   |   |    |      |      |      |      |   `- mode
//   |     |     |        |         |   |   |    |      |      |      |      `----- pattern
//   |     |     |        |         |   |   |    |      |      |      `- line pairs
//   |     |     |        |         |   |   |    |      |      `-------- pair misses
//   |     |     |        |         |   |   |    |      `- upscale-wiring misses
//   |     |     |        |         |   |   |    `-------- Hi-Z (2'b11) cycles
//   |     |     |        |         |   |   `------------- OR of SD[15:8]
//   |     |     |        |         |   `----------------- fail_code, 0 = passing
//                                          (1 gdclk 2 sdle 3 sdce0 4 sd-bus
//                                           5 vertical; see epd_verdict.v)
//   |     |     |        |         `--------------------- pass
//   |     |     |        `------------------------------- active_cnt - EXP_ACTIVE
//   |     |     `--------------------------------------- SDCE0 active-window cycles
//   |     `--------------------------------------------- SDLE rising edges
//   `--------------------------------------------------- GDCLK rising edges
//
// All numbers are hex. The expected healthy line is
//   G=787 S=787 A=096000 E=+000000 P=1 F=0 U=<nonzero> Z=0000 D=0000
// (0x787 = 1927, 0x96000 = 614400). U must not be 00: that would mean the
// top half of the bus is dead and OUTPUT_16B never took effect. See
// epd_sd_check.v for what Z and D mean, and epd_line_dup.v for V and L.
// L is the vertical half of the same story: 1920 panel lines is 960 pairs
// (0x3c0), and V counts the pairs that did not match.
//
// N and M are the front panel's pattern and mode selection. They are here
// because the LEDs cannot be trusted to report them: holding BTN2 hands the
// whole LED row to the self-test readout, so the pattern index is not even
// visible while the operator is pressing the button that changes it. Having
// them in the log removes a step where a human reads six LEDs and reports
// what they saw.
//
// Why hex and fixed width: no divider, no variable-length formatting, and the
// line is diffable -- a changing field is visually obvious in a log.
//
// One line is 39 bytes = 3.4 ms at 115200 baud. Frames arrive every 16.7 ms,
// so DECIMATE=1 already fits, but the default prints 4 lines/s to keep a live
// terminal readable; a log capture can turn it up.

module debug_uart #(
    parameter DECIMATE = 15         // emit one line per N frames
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        frame_tick,  // one pulse per completed frame
    input  wire [11:0] gdclk_cnt,
    input  wire [11:0] sdle_cnt,
    input  wire [20:0] active_cnt,
    input  wire signed [21:0] err,
    input  wire        pass,
    input  wire [2:0]  fail_code,
    input  wire [7:0]  sd_or,
    input  wire [15:0] hiz_cnt,
    input  wire [15:0] dup_cnt,
    input  wire [15:0] vpair_err,
    input  wire [15:0] vpair_cnt,
    input  wire [1:0]  pattern,
    input  wire [1:0]  mode_sel,

    output wire        tx
);

    localparam LINE_LEN = 80;

    // ---- snapshot ----
    // Latched when a line starts so the fields cannot change mid-line and
    // produce a number that never actually existed.
    reg [11:0] s_gdclk, s_sdle;
    reg [20:0] s_active;
    reg [23:0] s_errmag;
    reg        s_errneg, s_pass;
    reg [2:0]  s_fail;
    reg [7:0]  s_sdor;
    reg [15:0] s_hiz, s_dup;
    reg [15:0] s_verr, s_vcnt;
    reg [1:0]  s_pat, s_mode;

    reg [7:0]  frame_div;
    reg [6:0]  char_idx;   // LINE_LEN is 72, so 6 bits is not enough
    reg        sending;

    wire       due = (frame_div == DECIMATE - 1);

    // ---- character source ----
    function [7:0] hex;
        input [3:0] n;
        hex = (n < 4'd10) ? (8'd48 + {4'd0, n})        // '0'
                          : (8'd87 + {4'd0, n});       // 'a'-10
    endfunction

    reg [7:0] ch;
    always @(*) begin
        case (char_idx)
            7'd0:  ch = "G";
            7'd1:  ch = "=";
            7'd2:  ch = hex(s_gdclk[11:8]);
            7'd3:  ch = hex(s_gdclk[7:4]);
            7'd4:  ch = hex(s_gdclk[3:0]);
            7'd5:  ch = " ";
            7'd6:  ch = "S";
            7'd7:  ch = "=";
            7'd8:  ch = hex(s_sdle[11:8]);
            7'd9:  ch = hex(s_sdle[7:4]);
            7'd10: ch = hex(s_sdle[3:0]);
            7'd11: ch = " ";
            7'd12: ch = "A";
            7'd13: ch = "=";
            7'd14: ch = hex({3'd0, s_active[20]});
            7'd15: ch = hex(s_active[19:16]);
            7'd16: ch = hex(s_active[15:12]);
            7'd17: ch = hex(s_active[11:8]);
            7'd18: ch = hex(s_active[7:4]);
            7'd19: ch = hex(s_active[3:0]);
            7'd20: ch = " ";
            7'd21: ch = "E";
            7'd22: ch = "=";
            7'd23: ch = s_errneg ? "-" : "+";
            7'd24: ch = hex(s_errmag[23:20]);
            7'd25: ch = hex(s_errmag[19:16]);
            7'd26: ch = hex(s_errmag[15:12]);
            7'd27: ch = hex(s_errmag[11:8]);
            7'd28: ch = hex(s_errmag[7:4]);
            7'd29: ch = hex(s_errmag[3:0]);
            7'd30: ch = " ";
            7'd31: ch = "P";
            7'd32: ch = "=";
            7'd33: ch = hex({3'd0, s_pass});
            7'd34: ch = " ";
            7'd35: ch = "F";
            7'd36: ch = "=";
            7'd37: ch = hex({1'd0, s_fail});
            7'd38: ch = " ";
            7'd39: ch = "U";
            7'd40: ch = "=";
            7'd41: ch = hex(s_sdor[7:4]);
            7'd42: ch = hex(s_sdor[3:0]);
            7'd43: ch = " ";
            7'd44: ch = "Z";
            7'd45: ch = "=";
            7'd46: ch = hex(s_hiz[15:12]);
            7'd47: ch = hex(s_hiz[11:8]);
            7'd48: ch = hex(s_hiz[7:4]);
            7'd49: ch = hex(s_hiz[3:0]);
            7'd50: ch = " ";
            7'd51: ch = "D";
            7'd52: ch = "=";
            7'd53: ch = hex(s_dup[15:12]);
            7'd54: ch = hex(s_dup[11:8]);
            7'd55: ch = hex(s_dup[7:4]);
            7'd56: ch = hex(s_dup[3:0]);
            7'd57: ch = " ";
            7'd58: ch = "V";
            7'd59: ch = "=";
            7'd60: ch = hex(s_verr[15:12]);
            7'd61: ch = hex(s_verr[11:8]);
            7'd62: ch = hex(s_verr[7:4]);
            7'd63: ch = hex(s_verr[3:0]);
            7'd64: ch = " ";
            7'd65: ch = "L";
            7'd66: ch = "=";
            7'd67: ch = hex(s_vcnt[15:12]);
            7'd68: ch = hex(s_vcnt[11:8]);
            7'd69: ch = hex(s_vcnt[7:4]);
            7'd70: ch = hex(s_vcnt[3:0]);
            7'd71: ch = " ";
            7'd72: ch = "N";
            7'd73: ch = "=";
            7'd74: ch = hex({2'd0, s_pat});
            7'd75: ch = " ";
            7'd76: ch = "M";
            7'd77: ch = "=";
            7'd78: ch = hex({2'd0, s_mode});
            7'd79: ch = 8'h0a;               // '\n'
            default: ch = " ";
        endcase
    end

    // ---- sequencer ----
    wire uart_busy;
    reg  uart_load;
    reg  [7:0] tx_byte;

    always @(posedge clk) begin
        if (rst) begin
            frame_div <= 8'd0;
            char_idx  <= 7'd0;
            sending   <= 1'b0;
            uart_load <= 1'b0;
            tx_byte   <= 8'd0;
            s_gdclk   <= 12'd0;
            s_sdle    <= 12'd0;
            s_active  <= 21'd0;
            s_errmag  <= 24'd0;
            s_errneg  <= 1'b0;
            s_pass    <= 1'b0;
            s_fail    <= 3'd0;
            s_sdor    <= 8'd0;
            s_hiz     <= 16'd0;
            s_dup     <= 16'd0;
            s_verr    <= 16'd0;
            s_vcnt    <= 16'd0;
            s_pat     <= 2'd0;
            s_mode    <= 2'd0;
        end
        else begin
            uart_load <= 1'b0;

            if (frame_tick) begin
                if (due) begin
                    frame_div <= 8'd0;
                    // A frame arriving while a line is still going out is
                    // dropped rather than queued: the next one is 16.7 ms
                    // away and stale interleaved output is worse than a gap.
                    if (!sending) begin
                        s_gdclk  <= gdclk_cnt;
                        s_sdle   <= sdle_cnt;
                        s_active <= active_cnt;
                        s_errneg <= err[21];
                        s_errmag <= err[21] ? {2'd0, (~err + 22'd1)}
                                            : {2'd0, err};
                        s_pass   <= pass;
                        s_fail   <= fail_code;
                        s_sdor   <= sd_or;
                        s_hiz    <= hiz_cnt;
                        s_dup    <= dup_cnt;
                        s_verr   <= vpair_err;
                        s_vcnt   <= vpair_cnt;
                        s_pat    <= pattern;
                        s_mode   <= mode_sel;
                        sending  <= 1'b1;
                        char_idx <= 7'd0;
                    end
                end
                else begin
                    frame_div <= frame_div + 8'd1;
                end
            end

            if (sending && !uart_busy && !uart_load) begin
                uart_load <= 1'b1;
                tx_byte   <= ch;
                if (char_idx == LINE_LEN - 1) begin
                    sending  <= 1'b0;
                    char_idx <= 7'd0;
                end
                else begin
                    char_idx <= char_idx + 7'd1;
                end
            end
        end
    end

    uart_tx #(
        .DIVISOR(352)
    ) uart_tx (
        .clk(clk),
        .rst(rst),
        .data(tx_byte),
        .load(uart_load),
        .busy(uart_busy),
        .tx(tx)
    );

endmodule
`default_nettype wire
