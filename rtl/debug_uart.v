`timescale 1ns / 1ps
`default_nettype none
//
// debug_uart.v
// Prints one fixed-width line of epd_selftest's counters per emitted frame.
//
//   G=787 S=787 A=096000 E=+000000 P=1 F=0 U=ff Z=0000 D=0000
//   |     |     |        |         |   |   |    |      `- upscale-wiring misses
//   |     |     |        |         |   |   |    `-------- Hi-Z (2'b11) cycles
//   |     |     |        |         |   |   `------------- OR of SD[15:8]
//   |     |     |        |         |   `----------------- fail_code, 0 = passing
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
// epd_sd_check.v for what Z and D mean.
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
    input  wire [1:0]  fail_code,
    input  wire [7:0]  sd_or,
    input  wire [15:0] hiz_cnt,
    input  wire [15:0] dup_cnt,

    output wire        tx
);

    localparam LINE_LEN = 58;

    // ---- snapshot ----
    // Latched when a line starts so the fields cannot change mid-line and
    // produce a number that never actually existed.
    reg [11:0] s_gdclk, s_sdle;
    reg [20:0] s_active;
    reg [23:0] s_errmag;
    reg        s_errneg, s_pass;
    reg [1:0]  s_fail;
    reg [7:0]  s_sdor;
    reg [15:0] s_hiz, s_dup;

    reg [7:0]  frame_div;
    reg [5:0]  char_idx;
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
            6'd0:  ch = "G";
            6'd1:  ch = "=";
            6'd2:  ch = hex(s_gdclk[11:8]);
            6'd3:  ch = hex(s_gdclk[7:4]);
            6'd4:  ch = hex(s_gdclk[3:0]);
            6'd5:  ch = " ";
            6'd6:  ch = "S";
            6'd7:  ch = "=";
            6'd8:  ch = hex(s_sdle[11:8]);
            6'd9:  ch = hex(s_sdle[7:4]);
            6'd10: ch = hex(s_sdle[3:0]);
            6'd11: ch = " ";
            6'd12: ch = "A";
            6'd13: ch = "=";
            6'd14: ch = hex({3'd0, s_active[20]});
            6'd15: ch = hex(s_active[19:16]);
            6'd16: ch = hex(s_active[15:12]);
            6'd17: ch = hex(s_active[11:8]);
            6'd18: ch = hex(s_active[7:4]);
            6'd19: ch = hex(s_active[3:0]);
            6'd20: ch = " ";
            6'd21: ch = "E";
            6'd22: ch = "=";
            6'd23: ch = s_errneg ? "-" : "+";
            6'd24: ch = hex(s_errmag[23:20]);
            6'd25: ch = hex(s_errmag[19:16]);
            6'd26: ch = hex(s_errmag[15:12]);
            6'd27: ch = hex(s_errmag[11:8]);
            6'd28: ch = hex(s_errmag[7:4]);
            6'd29: ch = hex(s_errmag[3:0]);
            6'd30: ch = " ";
            6'd31: ch = "P";
            6'd32: ch = "=";
            6'd33: ch = hex({3'd0, s_pass});
            6'd34: ch = " ";
            6'd35: ch = "F";
            6'd36: ch = "=";
            6'd37: ch = hex({2'd0, s_fail});
            6'd38: ch = " ";
            6'd39: ch = "U";
            6'd40: ch = "=";
            6'd41: ch = hex(s_sdor[7:4]);
            6'd42: ch = hex(s_sdor[3:0]);
            6'd43: ch = " ";
            6'd44: ch = "Z";
            6'd45: ch = "=";
            6'd46: ch = hex(s_hiz[15:12]);
            6'd47: ch = hex(s_hiz[11:8]);
            6'd48: ch = hex(s_hiz[7:4]);
            6'd49: ch = hex(s_hiz[3:0]);
            6'd50: ch = " ";
            6'd51: ch = "D";
            6'd52: ch = "=";
            6'd53: ch = hex(s_dup[15:12]);
            6'd54: ch = hex(s_dup[11:8]);
            6'd55: ch = hex(s_dup[7:4]);
            6'd56: ch = hex(s_dup[3:0]);
            6'd57: ch = 8'h0a;               // '\n'
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
            char_idx  <= 6'd0;
            sending   <= 1'b0;
            uart_load <= 1'b0;
            tx_byte   <= 8'd0;
            s_gdclk   <= 12'd0;
            s_sdle    <= 12'd0;
            s_active  <= 21'd0;
            s_errmag  <= 24'd0;
            s_errneg  <= 1'b0;
            s_pass    <= 1'b0;
            s_fail    <= 2'd0;
            s_sdor    <= 8'd0;
            s_hiz     <= 16'd0;
            s_dup     <= 16'd0;
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
                        sending  <= 1'b1;
                        char_idx <= 6'd0;
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
                    char_idx <= 6'd0;
                end
                else begin
                    char_idx <= char_idx + 6'd1;
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
