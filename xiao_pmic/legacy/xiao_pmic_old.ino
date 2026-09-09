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
#include <Wire.h>

// TFT_eSPI, not EPaper: the EPaper constructor allocates a full-frame sprite,
// which for 2760x2070 is several megabytes of PSRAM. No image is drawn here.
TFT_eSPI tft = TFT_eSPI();

// EE03's I2C is not on the XIAO's default pins. Schematic sheet 5 puts it on
// GPIO41 (SCL) / GPIO42 (SDA); the defaults, GPIO5 and GPIO6, are BUTTON3 and
// ADC_EN on this board. Calling Wire.begin() with no arguments drives those
// two as an I2C bus, which is both wrong and rude to the battery ADC gate --
// and it makes every address appear to ACK, because nothing is holding SDA up.
#define EE03_SDA 42
#define EE03_SCL 41

// The older sketch in this folder defines PIN_PWR_SW as GPIO6 and calls it a
// P-MOSFET gate. Sheet 5 says GPIO6 is ADC_EN. There is a PWR_SW net, but it
// comes from Q5 off TYPEC_5V, not from a XIAO pin. Nothing is driven here for
// it; the load switch that matters is TFT_ENABLE (GPIO43), and the library's
// init sequence already raises that.

static const uint16_t VCOM_MV = 1310;   // magnitude in mV -> -1.31 V

// Two things at once. The SHT40 at 0x44 sits on the XIAO's own I2C and only
// exists on the EE03 board, so seeing it proves the XIAO is actually seated on
// the board and that the board has power -- the first thing to rule out when
// the TCON does not answer. And 0x68 is the PMIC: the schematic says its I2C
// hangs off the IT8951's bus, not this one, so it should be absent. If it does
// appear, that reading was wrong and the PMIC can be driven directly.
static void i2c_scan() {
  Wire.begin(EE03_SDA, EE03_SCL);
  Serial.print("I2C scan (SDA=GPIO"); Serial.print(EE03_SDA);
  Serial.print(", SCL=GPIO"); Serial.print(EE03_SCL); Serial.println("):");
  bool sht40 = false, pmic = false;
  int count = 0;
  for (uint8_t a = 0x08; a < 0x78; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      count++;
      Serial.print("  0x"); Serial.print(a, HEX);
      if (a == 0x44) { Serial.print("  SHT40 -- XIAO is seated on EE03"); sht40 = true; }
      if (a == 0x68) { Serial.print("  TPS651851 PMIC"); pmic = true; }
      Serial.println();
    }
  }
  if (!sht40) {
    Serial.println("  SHT40 (0x44) MISSING -- is the XIAO actually on the EE03");
    Serial.println("  board? Over USB alone there is no IT8951 to talk to.");
  }
  Serial.print("  PMIC at 0x68: ");
  Serial.println(pmic ? "present (schematic reading was wrong)"
                      : "absent, as the schematic predicts");
  if (count > 8) {
    Serial.println("  NOTE: almost everything ACKed. That is not a bus full of");
    Serial.println("  devices, it is a broken bus -- wrong pins, or SDA held low.");
  }
}

// The library's own failure message for this ("Invalid panel size!") goes to
// TFT_eSPI::println, which draws text on the panel rather than printing to the
// serial port, so it is invisible here. Read the device info directly instead.
// A live IT8951 reports its panel geometry and firmware strings; a dead SPI
// link reports zeros or 0xFFFF.
// Two headers define these: Setup511 (written for the 10.3" board) and
// EPaper_Board_Pins_Setups.h (for EE03). They disagree -- TFT_CS D7 vs 44,
// TFT_DC 10 vs -1 -- so print what the compiler actually settled on rather
// than reasoning about include order.
static void report_pins() {
  Serial.println("Effective pin macros:");
  Serial.print("  TFT_SCLK "); Serial.println(TFT_SCLK);
  Serial.print("  TFT_MISO "); Serial.println(TFT_MISO);
  Serial.print("  TFT_MOSI "); Serial.println(TFT_MOSI);
  Serial.print("  TFT_CS   "); Serial.println(TFT_CS);
  Serial.print("  TFT_RST  "); Serial.println(TFT_RST);
  Serial.print("  TFT_BUSY "); Serial.println(TFT_BUSY);
#ifdef TFT_DC
  Serial.print("  TFT_DC   "); Serial.println(TFT_DC);
#endif
#ifdef TFT_ENABLE
  Serial.print("  TFT_ENABLE "); Serial.println(TFT_ENABLE);
#endif
#ifdef SPI_FREQUENCY
  Serial.print("  SPI_FREQUENCY "); Serial.println(SPI_FREQUENCY);
#else
  Serial.println("  SPI_FREQUENCY (library default)");
#endif
  Serial.print("  ED103TC2_DRIVER ");
#ifdef ED103TC2_DRIVER
  Serial.println("yes");
#else
  Serial.println("NO -- the IT8951 driver was not selected!");
#endif
}

static bool report_tcon() {
  uint16_t w = tft._gstI80DevInfo.usPanelW;
  uint16_t h = tft._gstI80DevInfo.usPanelH;

  Serial.print("IT8951 panel geometry: ");
  Serial.print(w); Serial.print(" x "); Serial.println(h);

  Serial.print("IT8951 FW  : ");
  Serial.println((const char*)tft._gstI80DevInfo.usFWVersion);
  Serial.print("IT8951 LUT : ");
  Serial.println((const char*)tft._gstI80DevInfo.usLUTVersion);

  bool alive = (w != 0 && h != 0 && w != 0xFFFF && h != 0xFFFF);
  Serial.print("SPI link   : ");
  Serial.println(alive ? "ALIVE" : "DEAD -- nothing sensible came back");
  if (!alive) {
    Serial.println("  Check: TFT_BUSY/HRDY stuck, IT8951 held in reset, or the");
    Serial.println("  board's main power gate (GPIO6) not actually enabling VSYS.");
  }
  return alive;
}

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

  i2c_scan();
  Serial.println();

  Serial.print("HRDY/BUSY pin (GPIO"); Serial.print(TFT_BUSY);
  Serial.print(") reads: ");
  pinMode(TFT_BUSY, INPUT);
  Serial.println(digitalRead(TFT_BUSY) ? "HIGH (ready)" : "LOW (busy/held)");
  Serial.println();

  Serial.println("Initialising IT8951 over SPI...");
  tft.init();     // drives TFT_ENABLE, resets the TCON, runs hostTconInit()

  Serial.println();
  bool alive = report_tcon();
  Serial.println();

  if (!alive) {
    Serial.println("Not setting VCOM: the TCON is not answering, so the write");
    Serial.println("would go nowhere and the readback would mean nothing.");
    Serial.println("Type 'help' for commands.");
    Serial.print("> ");
    return;
  }

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

// Line-level probe without the SPI peripheral. The library's device-info
// read returns zeros both when the link is misconfigured and when the IT8951
// has no power; this distinguishes them by looking at what MISO actually does.
// A driven MISO changes with the clock; a stuck line holds one level; a
// floating line usually tracks noise rather than MOSI.
static void spi_probe() {
  Serial.println("Low-level SPI probe:");

  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);  delay(20);
  digitalWrite(TFT_RST, HIGH);
  Serial.print("  waiting for HRDY/BUSY release after HW reset (GPIO");
  Serial.print(TFT_RST);
  Serial.print("): ");
  unsigned long t0 = millis();
  bool ready = false;
  while (millis() - t0 < 5000) {
    if (digitalRead(TFT_BUSY)) { ready = true; break; }
    delay(10);
  }
  Serial.print(ready ? "released" : "TIMEOUT -- still LOW after 5 s");
  Serial.print(" (");
  Serial.print(millis() - t0);
  Serial.println(" ms)");
  if (!ready) {
    Serial.println("  A TCON that pulls BUSY but never releases it usually has");
    Serial.println("  power and reset, but no working crystal or firmware boot.");
  }

  pinMode(TFT_SCLK, OUTPUT); digitalWrite(TFT_SCLK, LOW);
  pinMode(TFT_MOSI, OUTPUT); digitalWrite(TFT_MOSI, LOW);
  pinMode(TFT_CS,   OUTPUT); digitalWrite(TFT_CS,   HIGH);
  pinMode(TFT_MISO, INPUT);

  const int NBITS = 64;
  for (int mosi = 0; mosi <= 1; mosi++) {
    digitalWrite(TFT_MOSI, mosi);
    digitalWrite(TFT_CS, LOW);
    uint8_t bytes[NBITS / 8] = {0};
    for (int i = 0; i < NBITS; i++) {
      digitalWrite(TFT_SCLK, HIGH);
      if (digitalRead(TFT_MISO)) bytes[i / 8] |= 0x80 >> (i % 8);
      digitalWrite(TFT_SCLK, LOW);
      delayMicroseconds(2);
    }
    digitalWrite(TFT_CS, HIGH);
    Serial.print("  MOSI=");
    Serial.print(mosi);
    Serial.print(" -> MISO sampled: ");
    char buf[3];
    for (unsigned b = 0; b < sizeof(bytes); b++) {
      sprintf(buf, "%02X", bytes[b]);
      Serial.print(buf);
    }
    Serial.println();
  }
  Serial.println("  identical 00/FF patterns = line stuck;");
  Serial.println("  differing/noisy patterns = MISO driven (TCON alive) or floating.");
}

// Bit-banged IT8951 GET_DEV_INFO. The raw-clock probe above cannot tell a
// healthy TCON from a dead one, because the TCON only drives MISO in response
// to a properly framed read command. This speaks just enough of the real
// protocol (mode 0, 16-bit big-endian words) to get an answer that means
// something even at GPIO toggle speeds.
static void bb_w16(uint16_t v) {
  for (int i = 15; i >= 0; i--) {
    digitalWrite(TFT_MOSI, (v >> i) & 1);
    digitalWrite(TFT_SCLK, HIGH);
    digitalWrite(TFT_SCLK, LOW);
  }
}

static uint16_t bb_r16(void) {
  uint16_t v = 0;
  for (int i = 15; i >= 0; i--) {
    digitalWrite(TFT_SCLK, HIGH);
    if (digitalRead(TFT_MISO)) v |= 1 << i;
    digitalWrite(TFT_SCLK, LOW);
  }
  return v;
}

static void spi_devinfo() {
  Serial.println("Bit-banged GET_DEV_INFO (0x0302), three framings:");

  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);  delay(20);
  digitalWrite(TFT_RST, HIGH);
  unsigned long t0 = millis();
  while (!digitalRead(TFT_BUSY) && millis() - t0 < 5000) delay(10);

  pinMode(TFT_SCLK, OUTPUT); digitalWrite(TFT_SCLK, LOW);
  pinMode(TFT_MOSI, OUTPUT); digitalWrite(TFT_MOSI, LOW);
  pinMode(TFT_CS,   OUTPUT); digitalWrite(TFT_CS,   HIGH);
  pinMode(TFT_MISO, INPUT);

  char buf[5];
  // A: CS toggles between command phase and data phase (reference driver).
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x6000); bb_w16(0x0302);
  digitalWrite(TFT_CS, HIGH);
  delay(50);
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x1000);
  Serial.print("  A (CS toggle)      :");
  for (int w = 0; w < 4; w++) { sprintf(buf, " %04X", bb_r16()); Serial.print(buf); }
  Serial.println();
  digitalWrite(TFT_CS, HIGH);

  // B: one continuous CS frame for command + data.
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x6000); bb_w16(0x0302); bb_w16(0x1000);
  Serial.print("  B (CS held)        :");
  for (int w = 0; w < 4; w++) { sprintf(buf, " %04X", bb_r16()); Serial.print(buf); }
  digitalWrite(TFT_CS, HIGH);
  Serial.println();

  // C: like A but skips a dummy word after the read prefix.
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x6000); bb_w16(0x0302);
  digitalWrite(TFT_CS, HIGH);
  delay(50);
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x1000); bb_r16();
  Serial.print("  C (dummy skipped)  :");
  for (int w = 0; w < 4; w++) { sprintf(buf, " %04X", bb_r16()); Serial.print(buf); }
  Serial.println();
  digitalWrite(TFT_CS, HIGH);
  Serial.println("  (word[0]/word[1] should be the panel width/height)");
}

// Everything that could plausibly wake an unresponsive host port, in one
// command: clean power cycle, reset, patient boot wait, then a pull-up /
// pull-down test on MISO that distinguishes a floating (never driven) line
// from one that is actively held -- which points at different failure sites.
static void tcon_revive() {
  char buf[5];

  Serial.println("Revive sequence:");

  Serial.println("  [1] power-cycling TCON rail via TFT_ENABLE...");
  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, LOW);
  delay(2000);
  digitalWrite(TFT_ENABLE, HIGH);
  delay(500);

  Serial.println("  [2] hardware reset...");
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);  delay(50);
  digitalWrite(TFT_RST, HIGH);
  unsigned long t0 = millis();
  bool ready = false;
  while (millis() - t0 < 10000) {
    if (digitalRead(TFT_BUSY)) { ready = true; break; }
    delay(20);
  }
  Serial.print("      BUSY ");
  Serial.print(ready ? "released" : "TIMEOUT");
  Serial.print(" after ");
  Serial.print(millis() - t0);
  Serial.println(" ms");
  if (!ready) { Serial.println("      aborting"); return; }

  Serial.println("  [3] MISO bias test (idle, no clocks):");
  pinMode(TFT_MISO, INPUT_PULLUP);   delayMicroseconds(5000);
  int pu = digitalRead(TFT_MISO);
  pinMode(TFT_MISO, INPUT_PULLDOWN); delayMicroseconds(5000);
  int pd = digitalRead(TFT_MISO);
  pinMode(TFT_MISO, INPUT);
  Serial.print("      pull-up reads "); Serial.println(pu ? "HIGH" : "LOW");
  Serial.print("      pull-down reads "); Serial.println(pd ? "HIGH" : "LOW");
  if (pu != pd) {
    Serial.println("      -> line FLOATS freely: nothing is driving it.");
    Serial.println("         Either the trace/socket contact to the TCON is");
    Serial.println("         open, or its host port is electrically dead.");
  } else {
    Serial.println("      -> line holds against both biases: driven or strongly");
    Serial.println("         loaded (stuck at that level, or heavy capacitive load).");
  }

  Serial.println("  [4] GET_DEV_INFO retry with pull-up biased MISO:");
  pinMode(TFT_SCLK, OUTPUT); digitalWrite(TFT_SCLK, LOW);
  pinMode(TFT_MOSI, OUTPUT); digitalWrite(TFT_MOSI, LOW);
  pinMode(TFT_CS,   OUTPUT); digitalWrite(TFT_CS,   HIGH);
  pinMode(TFT_MISO, INPUT_PULLUP);

  digitalWrite(TFT_CS, LOW);
  bb_w16(0x6000); bb_w16(0x0302);
  digitalWrite(TFT_CS, HIGH);
  delay(100);
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x1000);
  Serial.print("      ");
  for (int w = 0; w < 4; w++) { sprintf(buf, "%04X ", bb_r16()); Serial.print(buf); }
  Serial.println();
  digitalWrite(TFT_CS, HIGH);
}

void loop() {
  if (!Serial.available()) return;

  String in = Serial.readStringUntil('\n');
  in.trim();
  if (in.length() == 0) { Serial.print("> "); return; }

  if (in.equalsIgnoreCase("help")) {
    Serial.println("  info        device info + VCOM readback");
    Serial.println("  vcom <mV>   set VCOM magnitude, e.g. 'vcom 1310'");
    Serial.println("  sleep       put the TCON to sleep (rails drop)");
    Serial.println("  wake        wake the TCON");
    Serial.println("  retry       re-run the IT8951 init sequence");
    Serial.println("  probe       low-level SPI line diagnostics");
    Serial.println("  devinfo     bit-banged IT8951 GET_DEV_INFO");
    Serial.println("  revive      power cycle + reset + MISO bias test");
  }
  else if (in.equalsIgnoreCase("info")) {
    // Everything setup() prints, on demand. The native USB port re-enumerates
    // on reset, so boot output is usually gone before a terminal reconnects.
    report_pins();
    Serial.println();
    i2c_scan();
    Serial.println();
    Serial.print("HRDY/BUSY pin (GPIO"); Serial.print(TFT_BUSY);
    Serial.print(") reads: ");
    Serial.println(digitalRead(TFT_BUSY) ? "HIGH (ready)" : "LOW (busy/held)");
    Serial.println();
    report_tcon();
    report_vcom();
  }
  else if (in.equalsIgnoreCase("retry")) {
    Serial.println("Re-running IT8951 init...");
    tft.init();
    report_tcon();
  }
  else if (in.equalsIgnoreCase("probe")) {
    spi_probe();
  }
  else if (in.equalsIgnoreCase("devinfo")) {
    spi_devinfo();
  }
  else if (in.equalsIgnoreCase("revive")) {
    tcon_revive();
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
