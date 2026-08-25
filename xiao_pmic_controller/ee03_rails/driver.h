#ifndef DRIVER_H
#define DRIVER_H

// Same board and controller as Seeed_GFX's ED115OC1_Test example. The screen
// combo selects the IT8951 driver; the resolution overrides below match the
// panel this project drives.
//
// Nothing here draws to the panel. The FPGA does that. This sketch exists only
// to bring the PMIC rails up with the right VCOM and prove the SPI link works.
#define BOARD_SCREEN_COMBO 511
#define USE_XIAO_EPAPER_DISPLAY_BOARD_EE03

#define TFT_WIDTH  2760
#define TFT_HEIGHT 2070
#define EPD_WIDTH  2760
#define EPD_HEIGHT 2070
#define IT8951_PANEL_WIDTH  2760
#define IT8951_PANEL_HEIGHT 2070

// The library ends up at 40 MHz here, which is past what the IT8951's SPI
// slave will take -- the part is generally run at 12 to 24 MHz. At 40 MHz the
// TCON answers with zeros, which is exactly what the first bring-up saw.
// Start slow; once it talks, this can be raised to find the real ceiling.
#define SPI_FREQUENCY       10000000
#define SPI_READ_FREQUENCY  10000000

#endif
