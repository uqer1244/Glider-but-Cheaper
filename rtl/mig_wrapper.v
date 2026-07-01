`timescale 1ns / 1ps
`default_nettype none

module mig_wrapper(
    // Clock and reset
    input  wire         clk_sys,
    output wire         clk_mif,
    input  wire         rst_in,
    output wire         sys_rst,
    // DDR RAM interface
    inout  wire [15:0]  ddr_dq,
    output wire [12:0]  ddr_a,
    output wire [2:0]   ddr_ba,
    output wire         ddr_ras_n,
    output wire         ddr_cas_n,
    output wire         ddr_we_n,
    output wire         ddr_odt,
    output wire         ddr_reset_n,
    output wire         ddr_cke,
    output wire         ddr_ldm,
    output wire         ddr_udm,
    inout  wire         ddr_udqs_p,
    inout  wire         ddr_udqs_n,
    inout  wire         ddr_ldqs_p,
    inout  wire         ddr_ldqs_n,
    output wire         ddr_ck_p,
    output wire         ddr_ck_n,
    inout  wire         ddr_rzq,
    inout  wire         ddr_zio,
    // Control interface
    output wire         ddr_calib_done,
    // User interface
    input  wire         mig_cmd_en,
    input  wire [2:0]   mig_cmd_instr,
    input  wire [5:0]   mig_cmd_bl,
    input  wire [29:0]  mig_cmd_byte_addr,
    output wire         mig_cmd_empty,
    output wire         mig_cmd_full,
    input  wire         mig_wr_en,
    input  wire [15:0]  mig_wr_mask,
    input  wire [127:0] mig_wr_data,
    output wire         mig_wr_empty,
    output wire         mig_wr_full,
    output wire [6:0]   mig_wr_count,
    output wire         mig_wr_underrun,
    input  wire         mig_rd_en,
    output wire [127:0] mig_rd_data,
    output wire         mig_rd_full,
    output wire         mig_rd_empty,
    output wire         mig_rd_overflow,
    output wire [6:0]   mig_rd_count,
    // Error
    output wire         error
);

    parameter SIMULATION = "FALSE";
    parameter CALIB_SOFT_IP = "TRUE";

    // Loop clocks and resets
    assign clk_mif = clk_sys;
    assign sys_rst = rst_in;
    assign ddr_calib_done = 1'b1; // Calibration is mock-completed immediately

    // Stub FIFO states
    assign mig_cmd_empty = 1'b1;
    assign mig_cmd_full  = 1'b0;
    assign mig_wr_empty  = 1'b1;
    assign mig_wr_full   = 1'b0;
    assign mig_wr_count  = 7'b0;
    assign mig_wr_underrun = 1'b0;

    assign mig_rd_full   = 1'b0;
    assign mig_rd_empty  = 1'b0; // Mock not empty to respond to read enables
    assign mig_rd_overflow = 1'b0;
    assign mig_rd_count  = 7'd1;

    // Simple loopback register to return written data upon read command
    reg [127:0] data_reg;
    initial begin
        data_reg = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    end
    always @(posedge clk_mif) begin
        if (mig_wr_en) begin
            data_reg <= mig_wr_data;
        end
    end

    assign mig_rd_data = data_reg;
    assign error = 1'b0;

endmodule
`default_nettype wire
