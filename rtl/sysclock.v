`timescale 1ns / 1ps

module sysclock(
    input wire clk_in,
    output wire clk_ddr,
    output wire clk_sys,
    input wire reset,
    output reg locked
);
    // Bypass clock input directly to clock outputs for simulation
    assign clk_ddr = clk_in;
    assign clk_sys = clk_in;

    // Generate startup reset pulse by holding locked low for 100 ns
    initial begin
        locked = 1'b0;
        #100;
        locked = 1'b1;
    end
endmodule
