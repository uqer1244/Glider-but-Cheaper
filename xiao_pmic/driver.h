#ifndef DRIVER_H
#define DRIVER_H

// Pin map only -- lifted from ee03_probe/driver.h, which took it from
// Seeed_GFX's User_Setups/EPaper_Board_Pins_Setups.h, EE03 branch.
// Nothing here pulls in Seeed_GFX: this sketch talks to the IT8951 directly
// so that the exact framing that was proven on this board (PROGRESS.md 1.19)
// is the framing that runs, with no library layer to re-debug.

#define TFT_SCLK   D8
#define TFT_MISO   D9
#define TFT_MOSI   D10
#define TFT_CS     44   // D7
#define TFT_BUSY   4    // D3   -- IT8951 HRDY, active high = ready
#define TFT_RST    38   // D11  -- IT8951 reset, active low
#define TFT_ENABLE 43   // PWR_EN: logic rail AND the PMIC's VIN load switch

// EE03's I2C (SHT40 only -- the PMIC is NOT on this bus, PROGRESS.md 1.13)
#define EE03_SDA   42
#define EE03_SCL   41

#endif
