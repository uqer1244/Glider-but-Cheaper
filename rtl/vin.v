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
    // Internal 60Hz Animated Video Test Pattern Generator
    reg [11:0] x_cnt = 12'd0;
    reg [11:0] y_cnt = 12'd0;
    reg [7:0]  frame_cnt = 8'd0; // Advances every VSYNC (60Hz)
    reg [11:0] anim_pos = 12'd0;  // Moving bar X position
    reg test_de = 1'b0;
    reg [31:0] test_pixel = 32'd0;

    // VSYNC edge detector to advance animation frame at 60Hz
    reg vsync_d = 1'b0;
    always @(posedge dpi_pclk or posedge rst) begin
        if (rst) begin
            vsync_d <= 1'b0;
            frame_cnt <= 8'd0;
            anim_pos <= 12'd0;
        end else begin
            vsync_d <= dpi_vsync;
            if (dpi_vsync && !vsync_d) begin
                frame_cnt <= frame_cnt + 1'b1;
                // Move bar across screen at 60fps
                if (anim_pos + 12'd16 >= 12'd2760)
                    anim_pos <= 12'd0;
                else
                    anim_pos <= anim_pos + 12'd16;
            end
        end
    end

    // Raster generation for 2760x2070 panel
    always @(posedge dpi_pclk or posedge rst) begin
        if (rst) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
            test_de <= 1'b0;
        end else begin
            if (dpi_vsync) begin
                x_cnt <= 12'd0;
                y_cnt <= 12'd0;
                test_de <= 1'b0;
            end else begin
                if (x_cnt < 12'd2760) begin
                    x_cnt <= x_cnt + 1'b1;
                    test_de <= 1'b1;
                end else if (x_cnt < 12'd2800) begin
                    x_cnt <= x_cnt + 1'b1;
                    test_de <= 1'b0;
                end else begin
                    x_cnt <= 12'd0;
                    test_de <= 1'b0;
                    if (y_cnt < 12'd2070)
                        y_cnt <= y_cnt + 1'b1;
                end
            end
        end
    end

    // Generate 60Hz Animated Video Test Pattern (Moving Bar + Animated Checkerboard)
    always @(*) begin
        if (x_cnt >= anim_pos && x_cnt < anim_pos + 12'd120) begin
            // Moving vertical bar (White)
            test_pixel = 32'hFFFFFFFF;
        end else begin
            // Dynamic Checkerboard / Grayscale pattern moving at 60Hz
            test_pixel = (x_cnt[6] ^ y_cnt[6] ^ frame_cnt[3]) ? 32'hFFFFFFFF : 32'h00000000;
        end
    end

    // Route decoded DVI/HDMI (mapped to dpi_* inputs) video data directly to EPD engine outputs if present,
    // otherwise use internal 60Hz video test pattern
    assign v_vsync = dpi_vsync;
    assign v_pclk  = dpi_pclk;
    assign v_pixel = dpi_de ? {14'b0, dpi_pixel} : test_pixel;
    assign v_valid = dpi_de ? dpi_de : test_de;
    assign debug   = 8'b0;
endmodule

 