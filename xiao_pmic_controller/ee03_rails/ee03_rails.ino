// ee03_rails -- bring up the EE03 power rails for the Glider FPGA build.
//
// Why this exists
// ---------------
// The panel is driven by the Tang Primer 20K, not by the IT8951 on this board.
// But the TPS651851 that makes VPOS/VNEG/VGH/VGL/VCOM is not reachable from the
// XIAO: the schematic puts its SCL/SDA on ITE_I2C_*, a bus the IT8951 masters,
// while the XIAO's own I2C carries only the SHT40 at 0x44 (sheets 5, 6, 7).
// Writing to 0x68 from here goes nowhere.
//
// The IT8951 is reachable, over SPI, and it already owns that I2C bus and the
// PMIC's WAKEUP/PWRUP lines. So instead of taking control away from it -- which
// would mean soldering to TP2/TP3/TP57 -- ask it to do the work. No wiring.
//
// This does not conflict with bypassing the IT8951 for panel drive. The panel
// FPC is not plugged into EE03 at all (plan.md option A), so the IT8951's
// output pins drive nothing; only the seven power wires leave this board.
//
// VCOM
// ----
// -1.31 V, printed on the panel itself. Seeed_GFX's own init hardcodes 1400
// (-1.40 V) for the 10.3" panel it was written for, so it is overridden here.
// 90 mV of VCOM error shows up as poor contrast and ghosting.
//
// Serial commands: info, vcom <mV>, sleep, wake, help

#include "driver.h"
#include "TFT_eSPI.h"

// TFT_eSPI, not EPaper: the EPaper constructor allocates a full-frame sprite,
// which for 2760x2070 is several megabytes of PSRAM. No image is drawn here.
TFT_eSPI tft = TFT_eSPI();

// EE03 main power gate, ahead of the load switch the library drives.
// P-MOSFET gate: LOW turns it on. Not touched by Seeed_GFX.
#define PIN_PWR_SW 6

static const uint16_t VCOM_MV = 1310;   // magnitude in mV -> -1.31 V

static void report_vcom() {
  uint16_t v = tft.getTconVcom();
  Serial.print("VCOM readback: -");
  Serial.print(v / 1000.0f, 3);
  Serial.print(" V (");
  Serial.print(v);
  Serial.println(" mV)");
  if (v != VCOM_MV) {
    Serial.print("  WARNING: expected ");
    Serial.print(VCOM_MV);
    Serial.println(" mV. The write did not take, or the IT8951 clamped it.");
  }
}

void setup() {
  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && (millis() - t0 < 3000));

  Serial.println("\n==============================================");
  Serial.println("EE03 rails for Glider -- VCOM via IT8951 (SPI)");
  Serial.println("==============================================");

  // Main power gate first; the load switch and IT8951 reset are done by the
  // driver's init sequence.
  pinMode(PIN_PWR_SW, OUTPUT);
  digitalWrite(PIN_PWR_SW, LOW);
  delay(20);

  Serial.println("Initialising IT8951 over SPI...");
  tft.init();     // drives TFT_ENABLE, resets the TCON, runs hostTconInit()

  // hostTconInit() has just set VCOM to 1400. Correct it for this panel.
  Serial.print("Setting VCOM to ");
  Serial.print(VCOM_MV);
  Serial.println(" mV...");
  tft.setTconVcom(VCOM_MV);
  delay(50);
  report_vcom();

  Serial.println("\nRails should now be up. Measure before connecting a panel:");
  Serial.println("  VCOM  -1.31 V     VPOS +15 V     VNEG -15 V");
  Serial.println("Type 'help' for commands.");
  Serial.print("> ");
}

void loop() {
  if (!Serial.available()) return;

  String in = Serial.readStringUntil('\n');
  in.trim();
  if (in.length() == 0) { Serial.print("> "); return; }

  if (in.equalsIgnoreCase("help")) {
    Serial.println("  info        read VCOM back from the IT8951");
    Serial.println("  vcom <mV>   set VCOM magnitude, e.g. 'vcom 1310'");
    Serial.println("  sleep       put the TCON to sleep (rails drop)");
    Serial.println("  wake        wake the TCON");
  }
  else if (in.equalsIgnoreCase("info")) {
    report_vcom();
  }
  else if (in.startsWith("vcom ")) {
    long mv = in.substring(5).toInt();
    // The IT8951 takes a positive magnitude in mV. Refuse obvious nonsense
    // rather than pass it through to the PMIC.
    if (mv < 200 || mv > 5000) {
      Serial.println("  out of range: expected 200..5000 mV");
    } else {
      tft.setTconVcom((uint16_t)mv);
      delay(50);
      report_vcom();
    }
  }
  else if (in.equalsIgnoreCase("sleep")) {
    tft.tconSleep();
    Serial.println("  TCON asleep. Rails will drop -- do not drive the panel now.");
  }
  else if (in.equalsIgnoreCase("wake")) {
    tft.tconWake();
    delay(50);
    report_vcom();
  }
  else {
    Serial.println("  unknown command; try 'help'");
  }
  Serial.print("> ");
}
