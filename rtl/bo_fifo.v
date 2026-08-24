`timescale 1ns / 1ps
`default_nettype none
//
// bo_fifo.v
// EPDC -> VRAM asynchronous FIFO. 64 bit in on wr_clk, 128 bit out on rd_clk.
//
// Mirror image of bi_fifo. Same synchronous-read timing contract, same gray
// coded pointer crossing.

module bo_fifo #(
    parameter AW = 8            // 2**AW entries of 128 bit (default 256 x 128b)
)(
    input  wire         rst,
    // Write port, 64 bit
    input  wire         wr_clk,
    input  wire [63:0]  din,
    input  wire         wr_en,
    output wire         full,
    // Read port, 128 bit
    input  wire         rd_clk,
    input  wire         rd_en,
    output reg  [127:0] dout,
    output wire         empty
);

    reg [63:0] mem_lo [0:(1<<AW)-1];
    reg [63:0] mem_hi [0:(1<<AW)-1];

    // wr_ptr counts 64 bit words, rd_ptr counts 128 bit words.
    reg [AW+1:0] wr_ptr;
    reg [AW:0]   rd_ptr;

    // ---------------- write side ----------------
    wire do_wr = wr_en && !full;

    always @(posedge wr_clk) begin
        if (do_wr) begin
            if (wr_ptr[0]) mem_hi[wr_ptr[AW:1]] <= din;
            else           mem_lo[wr_ptr[AW:1]] <= din;
        end
    end

    reg [AW+1:0] wr_gray;
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wr_ptr  <= 0;
            wr_gray <= 0;
        end
        else if (do_wr) begin
            wr_ptr  <= wr_ptr + 1'b1;
            wr_gray <= (wr_ptr + 1'b1) ^ ((wr_ptr + 1'b1) >> 1);
        end
    end

    // ---------------- read side ----------------
    wire do_rd = rd_en && !empty;

    always @(posedge rd_clk) begin
        dout <= {mem_hi[rd_ptr[AW-1:0]], mem_lo[rd_ptr[AW-1:0]]};
    end

    reg [AW:0] rd_gray;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            rd_ptr  <= 0;
            rd_gray <= 0;
        end
        else if (do_rd) begin
            rd_ptr  <= rd_ptr + 1'b1;
            rd_gray <= (rd_ptr + 1'b1) ^ ((rd_ptr + 1'b1) >> 1);
        end
    end

    // ---------------- pointer crossing ----------------
    integer k;

    // wr_ptr -> rd domain
    reg [AW+1:0] wr_gray_s1, wr_gray_s2;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin wr_gray_s1 <= 0; wr_gray_s2 <= 0; end
        else begin wr_gray_s1 <= wr_gray; wr_gray_s2 <= wr_gray_s1; end
    end
    reg [AW+1:0] wr_ptr_rd;
    always @(*) begin
        wr_ptr_rd[AW+1] = wr_gray_s2[AW+1];
        for (k = AW; k >= 0; k = k - 1)
            wr_ptr_rd[k] = wr_ptr_rd[k+1] ^ wr_gray_s2[k];
    end

    // rd_ptr -> wr domain
    reg [AW:0] rd_gray_s1, rd_gray_s2;
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin rd_gray_s1 <= 0; rd_gray_s2 <= 0; end
        else begin rd_gray_s1 <= rd_gray; rd_gray_s2 <= rd_gray_s1; end
    end
    reg [AW:0] rd_ptr_wr;
    always @(*) begin
        rd_ptr_wr[AW] = rd_gray_s2[AW];
        for (k = AW-1; k >= 0; k = k - 1)
            rd_ptr_wr[k] = rd_ptr_wr[k+1] ^ rd_gray_s2[k];
    end

    // ---------------- flags ----------------
    // A 128 bit word is only readable once both of its halves are in, so the
    // writer's LSB is dropped. Conservative by at most one 64 bit word.
    wire [AW:0] wr_ptr_rd_128 = wr_ptr_rd[AW+1:1];
    assign empty = (rd_ptr == wr_ptr_rd_128);

    assign full = (wr_ptr[AW:0] == {rd_ptr_wr[AW-1:0], 1'b0}) &&
                  (wr_ptr[AW+1] != rd_ptr_wr[AW]);

endmodule
`default_nettype wire
