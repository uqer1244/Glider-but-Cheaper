`timescale 1ns / 1ps
`default_nettype none
// `include "mu_defines.vh" // Unused, commented out to avoid Gowin EDA include path errors

//
// mu_dbsync.v: Data bus synchronizer
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
module mu_dbsync #(
    parameter W = 8
) (
    input  wire         iclk,
    input  wire         oclk,
    input  wire [W-1:0] in,
    output wire [W-1:0] out
);

    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin
            mu_dsync dsync (
                .iclk(iclk),
                .oclk(oclk),
                .in(in[i]),
                .out(out[i])
            );
        end
    endgenerate

endmodule

`default_nettype wire
