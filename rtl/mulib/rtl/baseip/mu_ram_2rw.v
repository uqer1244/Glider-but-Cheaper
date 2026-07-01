`timescale 1ns / 1ps
`default_nettype none
//
// mu_ram_2rw.v: True dual port RAM model
//
// Copyright 2024 Wenting Zhang <zephray@outlook.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

module mu_ram_2rw #(
    parameter AW = 12,
    parameter DW = 8,
    parameter INITIALIZE = 0,
    parameter INIT_FILE = ""
) (
    input wire clka,
    input wire wea,
    input wire [AW-1:0] addra,
    input wire [DW-1:0] dina,
    output reg [DW-1:0] douta,
    input wire clkb,
    input wire web,
    input wire [AW-1:0] addrb,
    input wire [DW-1:0] dinb,
    output reg [DW-1:0] doutb
);

    localparam DEPTH = 1 << AW;
    reg [DW-1:0] mem [0:DEPTH-1];

    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;
        douta <= mem[addra];
    end

    always @(posedge clkb) begin
        if (web)
            mem[addrb] <= dinb;
        doutb <= mem[addrb];
    end

    generate
        if (INITIALIZE == 1) begin: gen_bram_init
            initial begin
                $readmemh(INIT_FILE, mem);
            end
        end
    endgenerate

endmodule
