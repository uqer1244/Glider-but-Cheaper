`timescale 1ns / 1ps
`default_nettype none
//
// mu_dsync.v: Synchronizer
//
// This file is adapted from the lambdalib project
// Copyright Lambda Project Authors. All rights Reserved.
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
module mu_dsync (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire iclk,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire oclk,
    input  wire in,   // input data
    output wire out   // synchronized data
);

    localparam STAGES = 2;
    localparam RND = 1;

    (* srl_style = "register" *)
    reg     [STAGES:0] shiftreg;
    integer            sync_delay;

    always @(posedge oclk) begin
        shiftreg[STAGES:0] <= {shiftreg[STAGES-1:0], in};
`ifdef SIMULATION
        sync_delay <= {$random} % 2;
`endif
    end

`ifndef SIMULATION
    assign out = shiftreg[STAGES-1];
`else
    assign out = (|sync_delay & (|RND)) ? shiftreg[STAGES] : shiftreg[STAGES-1];
`endif

endmodule

`default_nettype wire
