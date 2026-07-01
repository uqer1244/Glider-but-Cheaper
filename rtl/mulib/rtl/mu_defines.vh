//
// mu_defines.vh: Project Mushroom common include file
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

`define APB_SLAVE_IF \
    input  wire         s_apb_pwrite,\
    input  wire [31:0]  s_apb_pwdata,\
    input  wire [31:0]  s_apb_paddr,\
    input  wire         s_apb_penable,\
    input  wire         s_apb_psel,\
    output wire         s_apb_pready,\
    output wire [31:0]  s_apb_prdata

`define APB_MASTER_IF \
    output wire         m_apb_pwrite,\
    output wire [31:0]  m_apb_pwdata,\
    output wire [31:0]  m_apb_paddr,\
    output wire         m_apb_penable,\
    input  wire         m_apb_pready,\
    input  wire [31:0]  m_apb_prdata

`define APB_SLAVE_CONN(prefix, n) \
    .s_apb_pwrite(``prefix``pwrite),\
    .s_apb_pwdata(``prefix``pwdata),\
    .s_apb_paddr(``prefix``paddr),\
    .s_apb_penable(``prefix``penable),\
    .s_apb_psel(``prefix``psel_vec[n]),\
    .s_apb_pready(``prefix``pready_vec[n]),\
    .s_apb_prdata(``prefix``prdata_vec[n*32+:32])

`define APB_MASTER_CONN(prefix) \
    .m_apb_pwrite(``prefix``pwrite),\
    .m_apb_pwdata(``prefix``pwdata),\
    .m_apb_paddr(``prefix``paddr),\
    .m_apb_penable(``prefix``penable),\
    .m_apb_pready(``prefix``pready),\
    .m_apb_prdata(``prefix``prdata)

`define AXI_SLAVE_IF(aw, dw, idw) \
    input  wire [idw-1:0]           s_axi_awid,\
    input  wire [aw-1:0]            s_axi_awaddr,\
    input  wire [7:0]               s_axi_awlen,\
    input  wire [2:0]               s_axi_awsize,\
    input  wire [1:0]               s_axi_awburst,\
    input  wire                     s_axi_awvalid,\
    output wire                     s_axi_awready,\
    input  wire [dw-1:0]            s_axi_wdata,\
    input  wire [(dw/8)-1:0]        s_axi_wstrb,\
    input  wire                     s_axi_wlast,\
    input  wire                     s_axi_wvalid,\
    output wire                     s_axi_wready,\
    output wire [idw-1:0]           s_axi_bid,\
    output wire [1:0]               s_axi_bresp,\
    output wire                     s_axi_bvalid,\
    input  wire                     s_axi_bready,\
    input  wire [idw-1:0]           s_axi_arid,\
    input  wire [aw-1:0]            s_axi_araddr,\
    input  wire [7:0]               s_axi_arlen,\
    input  wire [2:0]               s_axi_arsize,\
    input  wire [1:0]               s_axi_arburst,\
    input  wire                     s_axi_arvalid,\
    output wire                     s_axi_arready,\
    output wire [idw-1:0]           s_axi_rid,\
    output wire [dw-1:0]            s_axi_rdata,\
    output wire [1:0]               s_axi_rresp,\
    output wire                     s_axi_rlast,\
    output wire                     s_axi_rvalid,\
    input  wire                     s_axi_rready

`define AXI_MASTER_IF(aw, dw, idw) \
    output wire [idw-1:0]           m_axi_awid,\
    output wire [aw-1:0]            m_axi_awaddr,\
    output wire [7:0]               m_axi_awlen,\
    output wire [2:0]               m_axi_awsize,\
    output wire [1:0]               m_axi_awburst,\
    output wire                     m_axi_awvalid,\
    input  wire                     m_axi_awready,\
    output wire [dw-1:0]            m_axi_wdata,\
    output wire [(dw/8)-1:0]        m_axi_wstrb,\
    output wire                     m_axi_wlast,\
    output wire                     m_axi_wvalid,\
    input  wire                     m_axi_wready,\
    input  wire [idw-1:0]           m_axi_bid,\
    input  wire [1:0]               m_axi_bresp,\
    input  wire                     m_axi_bvalid,\
    output wire                     m_axi_bready,\
    output wire [idw-1:0]           m_axi_arid,\
    output wire [aw-1:0]            m_axi_araddr,\
    output wire [7:0]               m_axi_arlen,\
    output wire [2:0]               m_axi_arsize,\
    output wire [1:0]               m_axi_arburst,\
    output wire                     m_axi_arvalid,\
    input  wire                     m_axi_arready,\
    input  wire [idw-1:0]           m_axi_rid,\
    input  wire [dw-1:0]            m_axi_rdata,\
    input  wire [1:0]               m_axi_rresp,\
    input  wire                     m_axi_rlast,\
    input  wire                     m_axi_rvalid,\
    output wire                     m_axi_rready

`define AXI_WIRES(prefix, aw, dw, idw) \
    wire [idw-1:0]          ``prefix``axi_awid;\
    wire [aw-1:0]           ``prefix``axi_awaddr;\
    wire [7:0]              ``prefix``axi_awlen;\
    wire [2:0]              ``prefix``axi_awsize;\
    wire [1:0]              ``prefix``axi_awburst;\
    wire                    ``prefix``axi_awvalid;\
    wire                    ``prefix``axi_awready;\
    wire [dw-1:0]           ``prefix``axi_wdata;\
    wire [(dw/8)-1:0]       ``prefix``axi_wstrb;\
    wire                    ``prefix``axi_wlast;\
    wire                    ``prefix``axi_wvalid;\
    wire                    ``prefix``axi_wready;\
    wire [idw-1:0]          ``prefix``axi_bid;\
    wire [1:0]              ``prefix``axi_bresp;\
    wire                    ``prefix``axi_bvalid;\
    wire                    ``prefix``axi_bready;\
    wire [idw-1:0]          ``prefix``axi_arid;\
    wire [aw-1:0]           ``prefix``axi_araddr;\
    wire [7:0]              ``prefix``axi_arlen;\
    wire [2:0]              ``prefix``axi_arsize;\
    wire [1:0]              ``prefix``axi_arburst;\
    wire                    ``prefix``axi_arvalid;\
    wire                    ``prefix``axi_arready;\
    wire [idw-1:0]          ``prefix``axi_rid;\
    wire [dw-1:0]           ``prefix``axi_rdata;\
    wire [1:0]              ``prefix``axi_rresp;\
    wire                    ``prefix``axi_rlast;\
    wire                    ``prefix``axi_rvalid;\
    wire                    ``prefix``axi_rready

`define AXI_CONN(prefix_left, prefix_right) \
    .``prefix_left``axi_awid(``prefix_right``axi_awid),\
    .``prefix_left``axi_awaddr(``prefix_right``axi_awaddr),\
    .``prefix_left``axi_awlen(``prefix_right``axi_awlen),\
    .``prefix_left``axi_awsize(``prefix_right``axi_awsize),\
    .``prefix_left``axi_awburst(``prefix_right``axi_awburst),\
    .``prefix_left``axi_awvalid(``prefix_right``axi_awvalid),\
    .``prefix_left``axi_awready(``prefix_right``axi_awready),\
    .``prefix_left``axi_wdata(``prefix_right``axi_wdata),\
    .``prefix_left``axi_wstrb(``prefix_right``axi_wstrb),\
    .``prefix_left``axi_wlast(``prefix_right``axi_wlast),\
    .``prefix_left``axi_wvalid(``prefix_right``axi_wvalid),\
    .``prefix_left``axi_wready(``prefix_right``axi_wready),\
    .``prefix_left``axi_bid(``prefix_right``axi_bid),\
    .``prefix_left``axi_bresp(``prefix_right``axi_bresp),\
    .``prefix_left``axi_bvalid(``prefix_right``axi_bvalid),\
    .``prefix_left``axi_bready(``prefix_right``axi_bready),\
    .``prefix_left``axi_arid(``prefix_right``axi_arid),\
    .``prefix_left``axi_araddr(``prefix_right``axi_araddr),\
    .``prefix_left``axi_arlen(``prefix_right``axi_arlen),\
    .``prefix_left``axi_arsize(``prefix_right``axi_arsize),\
    .``prefix_left``axi_arburst(``prefix_right``axi_arburst),\
    .``prefix_left``axi_arvalid(``prefix_right``axi_arvalid),\
    .``prefix_left``axi_arready(``prefix_right``axi_arready),\
    .``prefix_left``axi_rid(``prefix_right``axi_rid),\
    .``prefix_left``axi_rdata(``prefix_right``axi_rdata),\
    .``prefix_left``axi_rresp(``prefix_right``axi_rresp),\
    .``prefix_left``axi_rlast(``prefix_right``axi_rlast),\
    .``prefix_left``axi_rvalid(``prefix_right``axi_rvalid),\
    .``prefix_left``axi_rready(``prefix_right``axi_rready)

`define AXI_BURST_FIXED     2'd0
`define AXI_BURST_INCR      2'd1
`define AXI_BURST_WRAP      2'd2

`define AXI_RESP_OKAY       2'd0
`define AXI_RESP_EXOKAY     2'd1
`define AXI_RESP_SLVERR     2'd2
`define AXI_RESP_DECERR     2'd3
