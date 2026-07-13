`timescale 1ns / 1ps

module tb_top;

    // Inputs
    reg CLK_IN;
    reg LVDS_ODD_CK_P;
    wire LVDS_ODD_CK_N;
    reg [2:0] LVDS_ODD_P;
    wire [2:0] LVDS_ODD_N;
    reg [2:0] LVDS_EVEN_P;
    wire [2:0] LVDS_EVEN_N;
    reg DPI_PCLK;
    reg DPI_DE;
    reg DPI_VSYNC;
    reg DPI_HSYNC;
    reg [17:0] DPI_PIXEL;
    reg SPI_CS;
    reg SPI_SCK;
    reg SPI_MOSI;

    // Outputs
    wire [12:0] DDR_A;
    wire [2:0] DDR_BA;
    wire DDR_RAS_N;
    wire DDR_CAS_N;
    wire DDR_WE_N;
    wire DDR_ODT;
    wire DDR_RESET_N;
    wire DDR_CKE;
    wire DDR_LDM;
    wire DDR_UDM;
    wire DDR_CK_P;
    wire DDR_CK_N;
    wire EPD_GDOE;
    wire EPD_GDCLK;
    wire EPD_GDSP;
    wire EPD_SDCLK;
    wire EPD_SDLE;
    wire EPD_SDOE;
    wire [15:0] EPD_SD;
    wire EPD_SDCE0;
    wire SPI_MISO;
    wire [5:0] LED;

    // Bidirs
    wire [15:0] DDR_DQ;
    wire DDR_UDQS_P;
    wire DDR_UDQS_N;
    wire DDR_LDQS_P;
    wire DDR_LDQS_N;
    wire DDR_RZQ;
    wire DDR_ZIO;

    // LVDS differential logic
    assign LVDS_ODD_CK_N = ~LVDS_ODD_CK_P;
    assign LVDS_ODD_N    = ~LVDS_ODD_P;
    assign LVDS_EVEN_N   = ~LVDS_EVEN_P;

    // Instantiate the Unit Under Test (UUT)
    top #(
        .COLORMODE("MONO"),
        .SIMULATION("FALSE")
    ) uut (
        .CLK_IN(CLK_IN),
        .DDR_DQ(DDR_DQ),
        .DDR_A(DDR_A),
        .DDR_BA(DDR_BA),
        .DDR_RAS_N(DDR_RAS_N),
        .DDR_CAS_N(DDR_CAS_N),
        .DDR_WE_N(DDR_WE_N),
        .DDR_ODT(DDR_ODT),
        .DDR_RESET_N(DDR_RESET_N),
        .DDR_CKE(DDR_CKE),
        .DDR_LDM(DDR_LDM),
        .DDR_UDM(DDR_UDM),
        .DDR_UDQS_P(DDR_UDQS_P),
        .DDR_UDQS_N(DDR_UDQS_N),
        .DDR_LDQS_P(DDR_LDQS_P),
        .DDR_LDQS_N(DDR_LDQS_N),
        .DDR_CK_P(DDR_CK_P),
        .DDR_CK_N(DDR_CK_N),
        .DDR_RZQ(DDR_RZQ),
        .DDR_ZIO(DDR_ZIO),
        .EPD_GDOE(EPD_GDOE),
        .EPD_GDCLK(EPD_GDCLK),
        .EPD_GDSP(EPD_GDSP),
        .EPD_SDCLK(EPD_SDCLK),
        .EPD_SDLE(EPD_SDLE),
        .EPD_SDOE(EPD_SDOE),
        .EPD_SD(EPD_SD),
        .EPD_SDCE0(EPD_SDCE0),
        .LVDS_ODD_CK_P(LVDS_ODD_CK_P),
        .LVDS_ODD_CK_N(LVDS_ODD_CK_N),
        .LVDS_ODD_P(LVDS_ODD_P),
        .LVDS_ODD_N(LVDS_ODD_N),
        .LVDS_EVEN_P(LVDS_EVEN_P),
        .LVDS_EVEN_N(LVDS_EVEN_N),
        .DPI_PCLK(DPI_PCLK),
        .DPI_DE(DPI_DE),
        .DPI_VSYNC(DPI_VSYNC),
        .DPI_HSYNC(DPI_HSYNC),
        .DPI_PIXEL(DPI_PIXEL),
        .SPI_CS(SPI_CS),
        .SPI_SCK(SPI_SCK),
        .SPI_MOSI(SPI_MOSI),
        .SPI_MISO(SPI_MISO),
        .LED(LED)
    );

    // Clock generators
    initial begin
        CLK_IN = 0;
        forever #10 CLK_IN = ~CLK_IN; // 50 MHz
    end

    initial begin
        DPI_PCLK = 0;
        forever #20 DPI_PCLK = ~DPI_PCLK; // 25 MHz
    end

    // SPI tasks for configuration
    task spi_write_byte(input [7:0] data);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                SPI_MOSI = data[i];
                #100; // SPI SCK half period
                SPI_SCK = 1;
                #100;
                SPI_SCK = 0;
            end
        end
    endtask

    task spi_write_reg8(input [7:0] addr, input [7:0] data);
        begin
            SPI_CS = 0;
            #100;
            spi_write_byte(addr);
            spi_write_byte(data);
            #100;
            SPI_CS = 1;
            #200; // CS high duration
        end
    endtask

    task spi_write_reg16(input [7:0] addr, input [15:0] data);
        begin
            SPI_CS = 0;
            #100;
            spi_write_byte(addr);
            spi_write_byte(data[15:8]);
            spi_write_byte(data[7:0]);
            #100;
            SPI_CS = 1;
            #200; // CS high duration
        end
    endtask

    // Continuous DPI Generator synchronous to DPI_PCLK
    initial begin : dpi_gen
        integer line_idx;
        DPI_VSYNC = 0;
        DPI_HSYNC = 0;
        DPI_DE = 0;
        DPI_PIXEL = 0;
        LVDS_ODD_CK_P = 0;
        LVDS_ODD_P = 3'b0;
        LVDS_EVEN_P = 3'b0;

        // Wait for SPI configuration to complete (about 50 us)
        #100000;
        
        forever begin
            // VSYNC pulse & Vertical Front Porch: 7 lines total (VSYNC 2 lines, VFP 5 lines)
            for (line_idx = 0; line_idx < 7; line_idx = line_idx + 1) begin
                DPI_VSYNC = (line_idx < 2) ? 1 : 0; // First 2 lines active VSYNC
                // Send dummy line timing (87 PCLK cycles)
                DPI_HSYNC = 1;
                repeat (2) @(posedge DPI_PCLK);
                DPI_HSYNC = 0;
                repeat (85) @(posedge DPI_PCLK);
            end
            
            // 240 Active lines
            repeat (240) begin
                // HSYNC pulse: 2 PCLK cycles
                DPI_HSYNC = 1;
                repeat (2) @(posedge DPI_PCLK);
                DPI_HSYNC = 0;
                
                // Horizontal Back Porch: 2 PCLK cycles
                repeat (2) @(posedge DPI_PCLK);
                
                // Active pixels: 80 pixels (80 PCLK cycles)
                DPI_DE = 1;
                DPI_PIXEL = 18'h12345;
                repeat (80) @(posedge DPI_PCLK);
                DPI_DE = 0;
                
                // Horizontal Front Porch: 3 PCLK cycles
                repeat (3) @(posedge DPI_PCLK);
            end
            
            // Vertical Back Porch: 5 lines
            repeat (5) begin
                DPI_HSYNC = 1;
                repeat (2) @(posedge DPI_PCLK);
                DPI_HSYNC = 0;
                repeat (85) @(posedge DPI_PCLK);
            end
        end
    end

    // Simulation control and SPI configuration
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_top);
        
        SPI_CS = 1;
        SPI_SCK = 0;
        SPI_MOSI = 0;

        // Wait for system reset to release (at 100 ns)
        #200;
        
        $display("[TB] Writing registers over SPI...");
        spi_write_reg8(16, 5);    // CSR_CFG_V_FP
        spi_write_reg8(17, 2);    // CSR_CFG_V_SYNC
        spi_write_reg8(18, 5);    // CSR_CFG_V_BP
        spi_write_reg16(19, 240); // CSR_CFG_V_ACT
        
        spi_write_reg8(21, 3);    // CSR_CFG_H_FP
        spi_write_reg8(22, 2);    // CSR_CFG_H_SYNC
        spi_write_reg8(23, 2);    // CSR_CFG_H_BP
        spi_write_reg16(24, 80);  // CSR_CFG_H_ACT
        
        spi_write_reg8(30, 1);    // CSR_CFG_MINDRV
        
        // Enable controller
        spi_write_reg8(15, 1);    // CSR_ENABLE
        $display("[TB] SPI configuration complete. Controller enabled.");

        // Let the simulation run for 2.5 ms to capture multiple frames
        #2500000;
        $display("[TB] Simulation finished.");
        $finish;
    end

endmodule
