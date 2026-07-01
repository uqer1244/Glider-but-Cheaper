`timescale 1ns / 1ps

module vin #(
    parameter COLORMODE = "MONO"
)(
    input wire rst,
    input wire dpi_vsync,
    input wire dpi_hsync,
    input wire dpi_pclk,
    input wire dpi_de,
    input wire [17:0] dpi_pixel,
    input wire fpdlink_cp,
    input wire fpdlink_cn,
    input wire [2:0] fpdlink_odd_p,
    input wire [2:0] fpdlink_odd_n,
    input wire [2:0] fpdlink_even_p,
    input wire [2:0] fpdlink_even_n,
    output wire v_vsync,
    output wire v_pclk,
    output wire [31:0] v_pixel,
    output wire v_valid,
    input wire v_ready,
    output wire [7:0] debug
);
    // Route decoded DVI/HDMI (mapped to dpi_* inputs) video data directly to EPD engine outputs
    assign v_vsync = dpi_vsync;
    assign v_pclk  = dpi_pclk;
    assign v_pixel = {14'b0, dpi_pixel}; // Pad to 32 bits
    assign v_valid = dpi_de;
    assign debug   = 8'b0;
endmodule
 