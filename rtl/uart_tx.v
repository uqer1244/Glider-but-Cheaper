`timescale 1ns / 1ps
`default_nettype none
//
// uart_tx.v
// Minimal 8N1 transmitter. One byte in on `load`, `busy` until it is out.
//
// DIVISOR is clocks per bit: 40.5 MHz / 115200 = 351.56, so 352 gives
// 115057 baud, 0.12% slow. UART tolerates a few percent, so no PLL needed.

module uart_tx #(
    parameter DIVISOR = 352
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       load,     // pulse; ignored while busy
    output reg        busy,
    output reg        tx        // idles high
);

    reg [15:0] div_cnt;
    reg [3:0]  bit_idx;         // 0 = start, 1..8 = data, 9 = stop
    reg [7:0]  shifter;

    wire bit_done = (div_cnt == DIVISOR - 1);

    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 16'd0;
            bit_idx <= 4'd0;
            shifter <= 8'd0;
            busy    <= 1'b0;
            tx      <= 1'b1;
        end
        else if (!busy) begin
            tx      <= 1'b1;
            div_cnt <= 16'd0;
            if (load) begin
                shifter <= data;
                bit_idx <= 4'd0;
                busy    <= 1'b1;
                tx      <= 1'b0;   // start bit begins immediately
            end
        end
        else begin
            if (bit_done) begin
                div_cnt <= 16'd0;
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;  // stop bit has been held a full bit time
                    tx   <= 1'b1;
                end
                else begin
                    bit_idx <= bit_idx + 4'd1;
                    tx      <= (bit_idx == 4'd8) ? 1'b1        // stop
                                                 : shifter[0];
                    shifter <= {1'b0, shifter[7:1]};
                end
            end
            else begin
                div_cnt <= div_cnt + 16'd1;
            end
        end
    end

endmodule
`default_nettype wire
