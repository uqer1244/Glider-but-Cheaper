`timescale 1ns / 1ps

module bi_fifo(
    input wire rst,
    input wire wr_clk,
    input wire [127:0] din,
    input wire wr_en,
    output reg full,
    input wire rd_clk,
    input wire rd_en,
    output reg [63:0] dout,
    output reg empty
);
    // Asymmetric FIFO: 128-bit write, 64-bit read
    reg [63:0] mem [0:255];
    reg [7:0] wr_ptr;
    reg [8:0] rd_ptr;

    always @(posedge wr_clk) begin
        if (wr_en && !full) begin
            mem[{wr_ptr, 1'b0}] <= din[63:0];
            mem[{wr_ptr, 1'b1}] <= din[127:64];
        end
    end

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            wr_ptr <= wr_ptr + 1;
        end
    end

    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            rd_ptr <= 0;
            dout <= 0;
        end else begin
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
            dout <= mem[rd_ptr[7:0]];
        end
    end

    always @(*) begin
        empty = (rd_ptr == {wr_ptr, 1'b0});
        full  = (wr_ptr + 1'b1 == rd_ptr[8:1]);
    end
endmodule
