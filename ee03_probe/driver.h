#ifndef DRIVER_H
#define DRIVER_H

// Pin map only. This sketch deliberately does not pull in Seeed_GFX or any
// IT8951 driver -- instantiating one drives TFT_RST and the SPI bus, which is
// exactly what must not happen here. The numbers below are copied from
// Seeed_GFX's User_Setups/EPaper_Board_Pins_Setups.h, EE03 branch.

#define TFT_SCLK   D8
#define TFT_MISO   D9
#define TFT_MOSI   D10
#define TFT_CS     44   // D7
#define TFT_BUSY   4    // D3   -- IT8951 HRDY
#define TFT_RST    38   // D11  -- IT8951 reset, active low
#define TFT_ENABLE 43   // load switch for the board's low-voltage logic rail

// EE03's I2C is not on the XIAO defaults. Schematic sheet 5 puts it on
// GPIO41/GPIO42; GPIO5 and GPIO6 are BUTTON3 and ADC_EN on this board.
#define EE03_SDA   42
#define EE03_SCL   41

#endif
