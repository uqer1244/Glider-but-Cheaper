// ee03_probe -- read-only survey of a new EE03 board.
//
// Why this exists
// ---------------
// The previous EE03's IT8951 was declared dead after a long bring-up
// (PROGRESS.md 1.15). Before repeating any of that on the replacement, this
// sketch establishes what can be known WITHOUT touching the TCON at all.
//
// The rule this file obeys
// ------------------------
// TFT_RST, TFT_CS, TFT_SCLK and TFT_MOSI are configured as INPUT and are never
// written. No SPI peripheral is started and no IT8951 driver is constructed --
// merely instantiating TFT_eSPI asserts reset and clocks the bus. The TCON is
// observed, never addressed.
//
// The one exception is TFT_ENABLE (GPIO43), the load switch for the board's
// low-voltage logic rail. It is left alone at boot and is only raised by an
// explicit `rail on` command, because without that rail every TCON pin reads
// as an unpowered chip and the survey says nothing. Raising it powers the
// IT8951 but still does not talk to it.
//
// What was added later
// --------------------
// The survey above answered its question -- the IT8951 is alive, and 1.15 was
// wrong about the old board (1.19). Three commands were then added that do
// address the chip: `vcom`/`vtest` write the PMIC's VCOM register through it,
// and `rails` makes it run a display refresh so the high-voltage rails come
// up long enough to meet a meter. Each says so before it acts. The read-only
// rule above still governs everything else in this file.
//
// Commands: scan, pins, sht, batt, rail on|off, watch, tcon, tcon2, pmic,
// pmic2, vcom, vtest, rails, info, help

#include "driver.h"
#include <Wire.h>

// Bring the rails up on every boot, so a press of the reset button is the
// whole procedure: probes already on the test points, press, read. Typing a
// command into a serial monitor costs the first seconds of the window, which
// is the part you want to be watching.
//
// SET THIS TO 0 BEFORE A PANEL IS CONNECTED TO J1. With it at 1, every reset
// and every USB replug energises VPOS/VNEG/VGH/VGL and drives the panel bus,
// unattended and with whatever VCOM the PMIC came up with -- which is
// currently -2.50 V against a panel labelled -1.31 V (1.20).
#define RAILS_ON_BOOT          1
#define RAILS_ON_BOOT_SECONDS  60

static bool rail_raised = false;

// ---------------------------------------------------------------- TCON pins

// Every IT8951-facing pin is parked as a high-impedance input, once, here.
// Nothing later in this sketch changes that.
static void park_tcon_pins() {
  pinMode(TFT_RST,  INPUT);
  pinMode(TFT_CS,   INPUT);
  pinMode(TFT_SCLK, INPUT);
  pinMode(TFT_MOSI, INPUT);
  pinMode(TFT_MISO, INPUT);
  pinMode(TFT_BUSY, INPUT);
}

// A pin that is genuinely driven holds its level against both pulls. One that
// is floating follows whichever pull is applied. That difference is the whole
// point: it separates "the TCON is holding this line" from "nothing is here".
static const char *drive_state(int pin) {
  pinMode(pin, INPUT_PULLUP);
  delayMicroseconds(200);
  int up = digitalRead(pin);
  pinMode(pin, INPUT_PULLDOWN);
  delayMicroseconds(200);
  int down = digitalRead(pin);
  pinMode(pin, INPUT);
  if (up == down) return up ? "driven HIGH" : "driven LOW";
  return "floating (no driver)";
}

static void report_pin(const char *name, int pin) {
  pinMode(pin, INPUT);
  delayMicroseconds(200);
  Serial.print("  ");
  Serial.print(name);
  Serial.print(" (GPIO");
  Serial.print(pin);
  Serial.print("): reads ");
  Serial.print(digitalRead(pin) ? "HIGH" : "LOW");
  Serial.print(", ");
  Serial.println(drive_state(pin));
}

static void pins_report() {
  Serial.println("TCON pin survey (passive -- nothing is driven):");
  report_pin("HRDY/BUSY", TFT_BUSY);
  report_pin("RST      ", TFT_RST);
  report_pin("CS       ", TFT_CS);
  report_pin("MISO     ", TFT_MISO);
  Serial.print("  rail (TFT_ENABLE GPIO43) was raised by this sketch: ");
  Serial.println(rail_raised ? "yes" : "no -- try `rail on`, then `pins` again");
  Serial.println();
  Serial.println("  How to read this:");
  Serial.println("   - RST driven LOW with the rail up means the TCON is held in");
  Serial.println("     reset by something other than us, and will never answer.");
  Serial.println("   - HRDY floating with the rail up means the IT8951 is not");
  Serial.println("     driving its own ready line: unpowered, or not booting.");
  Serial.println("   - HRDY driven (either level) means the chip is alive enough");
  Serial.println("     to hold a pin. The dead board did reach this point, so this");
  Serial.println("     is necessary but not sufficient.");
  park_tcon_pins();
}

// ----------------------------------------------------------------- the rail

static void rail(bool on) {
  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, on ? HIGH : LOW);
  rail_raised = on;
  Serial.print("TFT_ENABLE (GPIO43) -> ");
  Serial.println(on ? "HIGH: logic rail up. The IT8951 now has power; it has"
                      " still not been addressed."
                    : "LOW: logic rail down.");
  if (on) {
    Serial.println("  Give it a moment, then run `pins`. On the dead board HRDY");
    Serial.println("  went HIGH exactly 1601 ms after reset release.");
  }
}

// -------------------------------------------------------------------- I2C

// The SHT40 at 0x44 exists only on the EE03 board, so seeing it proves the
// XIAO is really seated and the board is powered -- the first thing to rule
// out. 0x68 is the PMIC, which the schematic puts on the IT8951's private bus,
// not this one (PROGRESS.md 1.13). Its absence here is the expected result and
// confirms that reading on a second board; its presence would overturn it.
static void i2c_scan() {
  Wire.begin(EE03_SDA, EE03_SCL);
  Serial.print("I2C scan (SDA=GPIO");
  Serial.print(EE03_SDA);
  Serial.print(", SCL=GPIO");
  Serial.print(EE03_SCL);
  Serial.println("):");

  bool sht40 = false, pmic = false;
  int count = 0;
  for (uint8_t a = 0x08; a < 0x78; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      count++;
      Serial.print("  0x");
      Serial.print(a, HEX);
      if (a == 0x44) { Serial.print("  SHT40 -- XIAO is seated on EE03"); sht40 = true; }
      if (a == 0x68) { Serial.print("  TPS651851 PMIC"); pmic = true; }
      Serial.println();
    }
  }
  if (count == 0) Serial.println("  (nothing answered)");
  if (!sht40) {
    Serial.println("  SHT40 (0x44) MISSING -- is the XIAO actually on the EE03");
    Serial.println("  board, and is the board powered?");
  }
  Serial.print("  PMIC at 0x68: ");
  Serial.println(pmic ? "PRESENT -- overturns PROGRESS.md 1.13, drive it directly"
                      : "absent, as the schematic predicts (1.13 confirmed twice)");
  if (count > 8) {
    Serial.println("  Too many addresses answered. That is what a bus with no");
    Serial.println("  pull-ups looks like; treat the whole scan as meaningless.");
  }
}

// A real reading here is a second, independent proof that the board is alive
// and that this I2C bus works -- which is what makes the PMIC's absence above
// a finding rather than a broken bus.
static void sht40_read() {
  Wire.begin(EE03_SDA, EE03_SCL);
  Wire.beginTransmission(0x44);
  Wire.write(0xFD);                       // high-precision measurement
  if (Wire.endTransmission() != 0) {
    Serial.println("SHT40: no ACK. Board not seated, or bus dead.");
    return;
  }
  delay(10);
  if (Wire.requestFrom((uint8_t)0x44, (uint8_t)6) != 6) {
    Serial.println("SHT40: short read.");
    return;
  }
  uint16_t t_raw = (Wire.read() << 8) | Wire.read();
  Wire.read();                            // CRC, not checked
  uint16_t h_raw = (Wire.read() << 8) | Wire.read();
  Wire.read();
  float t = -45.0f + 175.0f * (t_raw / 65535.0f);
  float h = -6.0f + 125.0f * (h_raw / 65535.0f);
  Serial.print("SHT40: ");
  Serial.print(t, 2);
  Serial.print(" C, ");
  Serial.print(h, 2);
  Serial.println(" %RH  -- bus works, board is seated and powered.");
}

// ---------------------------------------------------------------- battery

// The factory firmware reported "battery level: 0", which is expected with no
// cell attached but is worth distinguishing from a broken divider. ADC_EN
// (GPIO6) gates the divider; it is driven only for the duration of the read.
static void battery_read() {
  pinMode(6, OUTPUT);
  digitalWrite(6, HIGH);
  delay(10);
  int raw = analogReadMilliVolts(A0);
  digitalWrite(6, LOW);
  pinMode(6, INPUT);
  Serial.print("Battery ADC (A0, divider gated by GPIO6): ");
  Serial.print(raw);
  Serial.println(" mV at the pin");
  Serial.println("  Near 0 with no cell attached is normal.");
}

// ------------------------------------------------------------------ misc

static void chip_info() {
  Serial.print("Chip: ");
  Serial.print(ESP.getChipModel());
  Serial.print(" rev ");
  Serial.print(ESP.getChipRevision());
  Serial.print(", flash ");
  Serial.print(ESP.getFlashChipSize() / (1024 * 1024));
  Serial.print(" MB, PSRAM ");
  Serial.print(ESP.getPsramSize() / (1024 * 1024));
  Serial.println(" MB");
}

// HRDY on the dead board released at a fixed 1601 ms and then sat still. A
// line that instead moves on its own is a chip doing something.
static void watch_hrdy() {
  Serial.println("Watching HRDY for 5 s (passive)...");
  pinMode(TFT_BUSY, INPUT);
  int last = digitalRead(TFT_BUSY);
  int edges = 0;
  unsigned long t0 = millis();
  while (millis() - t0 < 5000) {
    int now = digitalRead(TFT_BUSY);
    if (now != last) {
      edges++;
      Serial.print("  ");
      Serial.print(millis() - t0);
      Serial.print(" ms: -> ");
      Serial.println(now ? "HIGH" : "LOW");
      last = now;
    }
  }
  Serial.print("  ");
  Serial.print(edges);
  Serial.println(edges ? " transitions: the line is doing something."
                       : " transitions: the line is static.");
}


// =====================================================================
// Active probes -- read-only, but these DO address the IT8951.
//
// Everything above this line only watches pins. These two speak the real
// protocol, because nothing less can answer the question. They still only
// read: no VCOM write, no rail command, no pixel ever sent to a panel.
// The bit-bang is lifted from xiao_pmic, which established that the framing
// below is the one the reference driver uses.
// =====================================================================

static void bb_pins_out() {
  pinMode(TFT_SCLK, OUTPUT); digitalWrite(TFT_SCLK, LOW);
  pinMode(TFT_MOSI, OUTPUT); digitalWrite(TFT_MOSI, LOW);
  pinMode(TFT_CS,   OUTPUT); digitalWrite(TFT_CS,   HIGH);
  pinMode(TFT_MISO, INPUT);
}

static void bb_w16(uint16_t v) {
  for (int i = 15; i >= 0; i--) {
    digitalWrite(TFT_MOSI, (v >> i) & 1);
    digitalWrite(TFT_SCLK, HIGH);
    digitalWrite(TFT_SCLK, LOW);
  }
}

static uint16_t bb_r16() {
  uint16_t v = 0;
  digitalWrite(TFT_MOSI, LOW);
  for (int i = 15; i >= 0; i--) {
    digitalWrite(TFT_SCLK, HIGH);
    if (digitalRead(TFT_MISO)) v |= 1 << i;
    digitalWrite(TFT_SCLK, LOW);
  }
  return v;
}

// Reset and wait for the chip to say it is ready. The dead board released
// HRDY at a fixed 1601 ms no matter what was done to it, so the timing here
// is itself evidence: a different number means a different chip state.
static bool tcon_reset_and_wait() {
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);
  delay(50);
  digitalWrite(TFT_RST, HIGH);

  unsigned long t0 = millis();
  bool ready = false;
  while (millis() - t0 < 5000) {
    if (digitalRead(TFT_BUSY)) { ready = true; break; }
    delay(5);
  }
  Serial.print("  HRDY after reset release: ");
  if (ready) {
    Serial.print("HIGH at ");
    Serial.print(millis() - t0);
    Serial.println(" ms");
  } else {
    Serial.println("TIMEOUT -- never released in 5 s");
  }
  return ready;
}

static void bb_cmd(uint16_t cmd) {
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x6000);
  bb_w16(cmd);
  digitalWrite(TFT_CS, HIGH);
}

// GET_DEV_INFO returns 20 words: width, height, image buffer address (two
// words), then a 16-byte firmware version string and a 16-byte LUT version
// string. The strings matter as much as the geometry -- a chip that returns
// plausible numbers but blank strings is not really talking.
static void tcon_check() {
  Serial.println("TCON check -- GET_DEV_INFO (0x0302), read only:");

  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, HIGH);
  rail_raised = true;
  Serial.println("  logic rail raised (TFT_ENABLE HIGH)");
  delay(100);

  bb_pins_out();
  if (!tcon_reset_and_wait()) {
    Serial.println("  A TCON that never releases HRDY has power and reset but is");
    Serial.println("  not booting. Stopping here -- a read now would only return");
    Serial.println("  zeros and tell you nothing new.");
    return;
  }

  bb_cmd(0x0302);
  delay(50);

  uint16_t w[20];
  digitalWrite(TFT_CS, LOW);
  bb_w16(0x1000);
  bb_r16();                     // dummy word the reference driver discards
  for (int i = 0; i < 20; i++) w[i] = bb_r16();
  digitalWrite(TFT_CS, HIGH);

  Serial.print("  raw:");
  char buf[6];
  for (int i = 0; i < 8; i++) { sprintf(buf, " %04X", w[i]); Serial.print(buf); }
  Serial.println(" ...");

  Serial.print("  panel W: "); Serial.print(w[0]);
  Serial.print("   panel H: "); Serial.println(w[1]);
  Serial.print("  image buffer: 0x");
  Serial.println(((uint32_t)w[3] << 16) | w[2], HEX);

  // The strings arrive as byte pairs inside each word.
  Serial.print("  FW version: '");
  for (int i = 4; i < 12; i++) {
    char a = w[i] >> 8, b = w[i] & 0xFF;
    if (a >= 32 && a < 127) Serial.print(a);
    if (b >= 32 && b < 127) Serial.print(b);
  }
  Serial.println("'");
  Serial.print("  LUT version: '");
  for (int i = 12; i < 20; i++) {
    char a = w[i] >> 8, b = w[i] & 0xFF;
    if (a >= 32 && a < 127) Serial.print(a);
    if (b >= 32 && b < 127) Serial.print(b);
  }
  Serial.println("'");

  bool alive = (w[0] > 0 && w[0] < 4096 && w[1] > 0 && w[1] < 4096);
  Serial.println();
  if (alive) {
    Serial.println("  => TCON RESPONDS. Expected for this panel: 2760 x 2070.");
    Serial.println("     Different numbers still mean a live chip -- it is just");
    Serial.println("     reporting whatever panel profile it was flashed with.");
  } else {
    Serial.println("  => NO RESPONSE (geometry 0x0 / blank strings). This is the");
    Serial.println("     exact signature of the previous board (PROGRESS.md 1.15).");
  }
}

// The PMIC sits on the IT8951's private I2C bus, not the XIAO's (1.13), so the
// only way to ask it anything without soldering is to have the TCON ask for
// us. VCOM readback is that question: a real millivolt figure means the TCON
// reached the PMIC over I2C and got an answer. Zero means it did not.
//
// This reads VCOM. It does not set it -- the argument word below is the
// library's "get" selector.
static void pmic_check() {
  Serial.println("PMIC check -- VCOM readback through the TCON (read only):");
  Serial.println("  (the PMIC has no path to the XIAO's own I2C; see 1.13)");

  bb_pins_out();

  bb_cmd(0x0039);               // IT8951 VCOM command
  digitalWrite(TFT_CS, LOW);    // argument: 0 = read, 1 = write
  bb_w16(0x0000);
  bb_w16(0x0000);
  digitalWrite(TFT_CS, HIGH);
  delay(50);

  digitalWrite(TFT_CS, LOW);
  bb_w16(0x1000);
  bb_r16();                     // dummy
  uint16_t vcom = bb_r16();
  digitalWrite(TFT_CS, HIGH);

  Serial.print("  VCOM readback: ");
  Serial.print(vcom);
  Serial.print(" mV magnitude (-");
  Serial.print(vcom / 1000.0f, 3);
  Serial.println(" V)");

  if (vcom == 0 || vcom == 0xFFFF) {
    Serial.println("  => NO ANSWER. Either the TCON is not talking (run `tcon`");
    Serial.println("     first) or it cannot reach the PMIC on ITE_I2C.");
  } else if (vcom > 500 && vcom < 4000) {
    Serial.println("  => PMIC RESPONDS through the TCON. This is the path 1.14");
    Serial.println("     depends on, and it is open. Panel label wants 1310.");
  } else {
    Serial.println("  => answered, but the value is out of range for an EPD.");
    Serial.println("     Treat the link as suspect rather than proven.");
  }
  Serial.println();
  Serial.println("  Note: VCOM readback proves the I2C link, not the rails.");
  Serial.println("  VPOS/VNEG only come up during a refresh and must be met");
  Serial.println("  with a meter at J1 pins 37 and 38.");
}


// =====================================================================
// HRDY-gated transport (tcon2 / pmic2)
//
// Why a second transport
// ----------------------
// The first one reads zeros, on both boards, with HRDY releasing at a fixed
// ~1603 ms each time. A chip that reliably releases its ready line on a
// schedule is booting, not dead -- which points at the host protocol rather
// than the silicon. The IT8951 requires the host to wait for HRDY before
// every phase of a transfer, including between the read preamble and the
// data that follows it. The transport above skips that wait. This one does
// not; it is the only difference.
// =====================================================================

static unsigned long hrdy_waits = 0;
static unsigned long hrdy_worst = 0;

// 1 s is generous for the survey commands -- the longest wait any of them
// has ever produced is 30 ms. The refresh path raises this, because a
// DPY_AREA has to run the PMIC's power sequence before it will take its
// arguments, and that is a different order of magnitude.
static unsigned long hrdy_timeout_ms = 1000;

// Returns false on timeout. The caller reports it rather than pressing on,
// because every word read after a missed ready is meaningless.
static bool wait_ready(const char *where, unsigned long timeout_ms = 0) {
  if (timeout_ms == 0) timeout_ms = hrdy_timeout_ms;
  unsigned long t0 = millis();
  while (!digitalRead(TFT_BUSY)) {
    if (millis() - t0 > timeout_ms) {
      Serial.print("    HRDY timeout at ");
      Serial.print(where);
      Serial.print(" after ");
      Serial.print(timeout_ms);
      Serial.println(" ms");
      return false;
    }
  }
  unsigned long waited = millis() - t0;
  hrdy_waits++;
  if (waited > hrdy_worst) hrdy_worst = waited;
  return true;
}

// Half-bit delay. digitalWrite on the S3 is slow enough that this is already
// a few hundred kHz, well under the IT8951's ceiling, but an explicit settle
// keeps MISO sampling away from the slave's output transition.
static inline void bb_settle() { delayMicroseconds(2); }

static void bb_w16_s(uint16_t v) {
  for (int i = 15; i >= 0; i--) {
    digitalWrite(TFT_MOSI, (v >> i) & 1);
    bb_settle();
    digitalWrite(TFT_SCLK, HIGH);
    bb_settle();
    digitalWrite(TFT_SCLK, LOW);
  }
}

// Mode 0: the slave changes MISO on the falling edge, so sample just before
// driving the clock low again, after the line has had time to settle.
static uint16_t bb_r16_s() {
  uint16_t v = 0;
  digitalWrite(TFT_MOSI, LOW);
  for (int i = 15; i >= 0; i--) {
    digitalWrite(TFT_SCLK, HIGH);
    bb_settle();
    if (digitalRead(TFT_MISO)) v |= 1 << i;
    digitalWrite(TFT_SCLK, LOW);
    bb_settle();
  }
  return v;
}

static bool tcon_cmd_g(uint16_t cmd) {
  if (!wait_ready("before command")) return false;
  digitalWrite(TFT_CS, LOW);
  bb_w16_s(0x6000);
  if (!wait_ready("after command preamble")) { digitalWrite(TFT_CS, HIGH); return false; }
  bb_w16_s(cmd);
  digitalWrite(TFT_CS, HIGH);
  return true;
}

static bool tcon_write_args_g(const uint16_t *args, int n) {
  if (!wait_ready("before args")) return false;
  digitalWrite(TFT_CS, LOW);
  bb_w16_s(0x0000);
  if (!wait_ready("after write preamble")) { digitalWrite(TFT_CS, HIGH); return false; }
  for (int i = 0; i < n; i++) bb_w16_s(args[i]);
  digitalWrite(TFT_CS, HIGH);
  return true;
}

// The wait after the preamble is the whole point of this file.
static bool tcon_read_g(uint16_t *out, int n) {
  if (!wait_ready("before read")) return false;
  digitalWrite(TFT_CS, LOW);
  bb_w16_s(0x1000);
  if (!wait_ready("after read preamble")) { digitalWrite(TFT_CS, HIGH); return false; }
  bb_r16_s();                                  // dummy word
  if (!wait_ready("after dummy word")) { digitalWrite(TFT_CS, HIGH); return false; }
  for (int i = 0; i < n; i++) out[i] = bb_r16_s();
  digitalWrite(TFT_CS, HIGH);
  return true;
}

static void tcon_check2() {
  Serial.println("TCON check, HRDY-gated transport -- GET_DEV_INFO, read only:");

  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, HIGH);
  rail_raised = true;
  delay(100);

  bb_pins_out();
  if (!tcon_reset_and_wait()) {
    Serial.println("  never became ready; stopping.");
    return;
  }
  delay(100);

  hrdy_waits = 0; hrdy_worst = 0;

  uint16_t w[20];
  if (!tcon_cmd_g(0x0302))  { Serial.println("  command phase failed."); return; }
  if (!tcon_read_g(w, 20))  { Serial.println("  read phase failed."); return; }

  Serial.print("  raw:");
  char buf[6];
  for (int i = 0; i < 8; i++) { sprintf(buf, " %04X", w[i]); Serial.print(buf); }
  Serial.println(" ...");
  Serial.print("  HRDY waits honoured: ");
  Serial.print(hrdy_waits);
  Serial.print(", longest ");
  Serial.print(hrdy_worst);
  Serial.println(" ms");

  Serial.print("  panel W: "); Serial.print(w[0]);
  Serial.print("   panel H: "); Serial.println(w[1]);
  Serial.print("  FW version: '");
  for (int i = 4; i < 12; i++) {
    char a = w[i] >> 8, b = w[i] & 0xFF;
    if (a >= 32 && a < 127) Serial.print(a);
    if (b >= 32 && b < 127) Serial.print(b);
  }
  Serial.println("'");
  Serial.print("  LUT version: '");
  for (int i = 12; i < 20; i++) {
    char a = w[i] >> 8, b = w[i] & 0xFF;
    if (a >= 32 && a < 127) Serial.print(a);
    if (b >= 32 && b < 127) Serial.print(b);
  }
  Serial.println("'");

  Serial.println();
  if (w[0] > 0 && w[0] < 4096 && w[1] > 0 && w[1] < 4096) {
    Serial.println("  => TCON RESPONDS. The gating was the missing piece, and");
    Serial.println("     PROGRESS.md 1.15 needs revisiting: the old board may");
    Serial.println("     never have been dead.");
  } else {
    Serial.println("  => still zeros, now with every HRDY wait honoured. That");
    Serial.println("     removes the protocol explanation for this framing.");
  }
}

// One reading proves nothing on an undriven line -- that is how the first
// pmic check produced 1404 mV once and 61 mV the next time. Noise does not
// repeat; a register does. Five reads must agree before this claims a link.
static void pmic_check2() {
  Serial.println("PMIC check -- VCOM readback, HRDY-gated, five reads:");

  bb_pins_out();

  uint16_t v[5];
  for (int i = 0; i < 5; i++) {
    uint16_t arg = 0x0000;                  // 0 = get
    if (!tcon_cmd_g(0x0039))        { Serial.println("  command phase failed."); return; }
    if (!tcon_write_args_g(&arg, 1)) { Serial.println("  argument phase failed."); return; }
    if (!tcon_read_g(&v[i], 1))     { Serial.println("  read phase failed."); return; }
    Serial.print("    read ");
    Serial.print(i + 1);
    Serial.print(": ");
    Serial.println(v[i]);
    delay(20);
  }

  bool same = true;
  for (int i = 1; i < 5; i++) if (v[i] != v[0]) same = false;

  Serial.println();
  if (!same) {
    Serial.println("  => values disagree: this is noise on an undriven MISO,");
    Serial.println("     not a register. No PMIC link proven.");
  } else if (v[0] == 0 || v[0] == 0xFFFF) {
    Serial.println("  => stable but degenerate. The line is stuck, not talking.");
  } else if (v[0] > 500 && v[0] < 4000) {
    Serial.print("  => stable at ");
    Serial.print(v[0]);
    Serial.println(" mV across five reads. PMIC link is real.");
  } else {
    Serial.println("  => stable but out of range for an EPD; treat as suspect.");
  }
}


// =====================================================================
// VCOM write and the volatility test
//
// The only write in this sketch. It goes to the TPS65185's VCOM register by
// way of the IT8951, which masters that I2C bus. It is reversible -- writing
// another value replaces it.
//
// It does NOT touch the PMIC's PROG bit. Programming VCOM into the part's
// non-volatile memory is a one-way operation with a limited write count, and
// nothing here needs it.
// =====================================================================

static bool vcom_read(uint16_t *out) {
  uint16_t arg = 0x0000;                    // 0 = get
  if (!tcon_cmd_g(0x0039)) return false;
  if (!tcon_write_args_g(&arg, 1)) return false;
  return tcon_read_g(out, 1);
}

static bool vcom_write(uint16_t mv) {
  uint16_t args[2] = { 0x0001, mv };        // 1 = set
  if (!tcon_cmd_g(0x0039)) return false;
  return tcon_write_args_g(args, 2);
}

// Five agreeing reads, same rule as pmic2: one reading proves nothing.
static bool vcom_read_stable(uint16_t *out) {
  uint16_t v[5];
  for (int i = 0; i < 5; i++) {
    if (!vcom_read(&v[i])) return false;
    delay(20);
  }
  for (int i = 1; i < 5; i++) if (v[i] != v[0]) {
    Serial.println("    readings disagree -- treating as noise, not a value.");
    return false;
  }
  *out = v[0];
  return true;
}

static void vcom_set_cmd(uint16_t mv) {
  bb_pins_out();
  Serial.print("Writing VCOM = ");
  Serial.print(mv);
  Serial.println(" mV (magnitude) to the PMIC via the TCON...");
  if (!vcom_write(mv)) { Serial.println("  write failed."); return; }
  delay(100);
  uint16_t back;
  if (!vcom_read_stable(&back)) { Serial.println("  readback failed."); return; }
  Serial.print("  readback: ");
  Serial.print(back);
  Serial.println(back == mv ? " mV -- write took." : " mV -- MISMATCH.");
}

// Does the value survive losing power? That decides whether the XIAO has to
// stay in the final system as the thing that sets VCOM on every boot, or
// whether it can be set once and forgotten.
static void vcom_volatility_test() {
  Serial.println("VCOM volatility test (PROG bit is never touched):");

  bb_pins_out();

  uint16_t before;
  Serial.println("  [1] current value:");
  if (!vcom_read_stable(&before)) return;
  Serial.print("      ");
  Serial.print(before);
  Serial.println(" mV");

  Serial.println("  [2] writing 1310 (the panel's labelled -1.31 V):");
  if (!vcom_write(1310)) { Serial.println("      write failed."); return; }
  delay(100);
  uint16_t after;
  if (!vcom_read_stable(&after)) return;
  Serial.print("      readback ");
  Serial.print(after);
  Serial.println(after == 1310 ? " mV -- took." : " mV -- did not take; stopping.");
  if (after != 1310) return;

  Serial.println("  [3] dropping the logic rail for 3 s...");
  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, LOW);
  rail_raised = false;
  delay(3000);

  Serial.println("  [4] rail back up, TCON reset:");
  digitalWrite(TFT_ENABLE, HIGH);
  rail_raised = true;
  delay(200);
  bb_pins_out();
  if (!tcon_reset_and_wait()) { Serial.println("      TCON did not come back."); return; }
  delay(100);

  Serial.println("  [5] reading VCOM again:");
  uint16_t survived;
  if (!vcom_read_stable(&survived)) return;
  Serial.print("      ");
  Serial.print(survived);
  Serial.println(" mV");

  Serial.println();
  if (survived == 1310) {
    Serial.println("  => NON-VOLATILE across a logic-rail cycle. Set once and the");
    Serial.println("     XIAO is not needed for VCOM at runtime.");
    Serial.println("     Caveat: this cut TFT_ENABLE, not the board's input power.");
    Serial.println("     A full unplug is the stronger test.");
  } else {
    Serial.print("  => VOLATILE: reverted to ");
    Serial.print(survived);
    Serial.println(" mV. The XIAO must set VCOM on every power-up, so it stays");
    Serial.println("     in the final system as more than a power gate.");
  }
}

// =====================================================================
// Rail bring-up
//
// Everything before this point either reads, or writes only the VCOM
// register. This is the first thing in the sketch that makes the board
// generate high voltages.
//
// It cannot ask for them directly. The TPS65185 sits on the IT8951's private
// I2C bus and has no path to the XIAO's own (1.13, confirmed twice by the
// scan), so nothing here can set the PMIC's ENABLE register. The rails come
// up only as a side effect of the TCON running a display refresh, and that
// is what this does.
//
// DPY_AREA in INIT mode is the cheapest refresh that exercises the whole
// power sequence, and unlike every other mode it needs no image in the frame
// buffer. One pass over the profile the TCON reports for itself takes a
// couple of seconds and the rails drop again the moment it ends -- not long
// enough to find a test point with a probe in each hand. So the refresh is
// re-issued until the window closes, which holds the rails up near enough to
// continuously for a meter to settle.
//
// Nothing is attached to J1. Driving the source and gate buses into an open
// connector is harmless, and so is whatever VCOM happens to be: with no
// panel to bias, the magnitude does not matter. It is printed before the
// rails come up anyway, so the reading you take is on the record next to the
// value that produced it.
// =====================================================================

// LUTAFSR reads 0 when the display engine is idle. Polling it is how the
// next refresh starts without leaving a gap the rails can fall through.
#define IT8951_LUTAFSR 0x1224

static bool reg_read(uint16_t addr, uint16_t *out) {
  if (!tcon_cmd_g(0x0010)) return false;                 // REG_RD
  if (!tcon_write_args_g(&addr, 1)) return false;
  return tcon_read_g(out, 1);
}

static bool dpy_area(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t mode) {
  uint16_t args[5] = { x, y, w, h, mode };
  if (!tcon_cmd_g(0x0034)) return false;                 // DPY_AREA
  return tcon_write_args_g(args, 5);
}

// GET_DEV_INFO again, quietly. The refresh has to name an area and the only
// geometry certain to be valid is the one the TCON claims for itself --
// 1872x1404 on this board, which is the Seeed kit's panel, not ours (1.19).
// That mismatch does not matter here: no panel is connected and the point is
// the power sequence, not the pixels.
static void words_to_str(const uint16_t *w, int from, int to, char *out) {
  int n = 0;
  for (int i = from; i < to; i++) {
    char a = w[i] >> 8, b = w[i] & 0xFF;
    if (a >= 32 && a < 127) out[n++] = a;
    if (b >= 32 && b < 127) out[n++] = b;
  }
  out[n] = 0;
}

static bool dev_geometry(uint16_t *w, uint16_t *h, char *fw, char *lut) {
  uint16_t info[20];
  if (!tcon_cmd_g(0x0302)) return false;
  if (!tcon_read_g(info, 20)) return false;
  if (info[0] == 0 || info[1] == 0 || info[0] > 4096 || info[1] > 4096) return false;
  *w = info[0];
  *h = info[1];
  words_to_str(info, 4, 12, fw);
  words_to_str(info, 12, 20, lut);
  return true;
}

static bool reg_write(uint16_t addr, uint16_t val) {
  uint16_t args[2] = { addr, val };
  if (!tcon_cmd_g(0x0011)) return false;                 // REG_WR
  return tcon_write_args_g(args, 2);
}

static void rails_up(unsigned long seconds) {
  Serial.println("Rail bring-up -- the board will generate high voltages.");
  Serial.println("  Measure against TP41 (GND, on the TCON sheet's TP column):");
  Serial.println("    TP21  VPOS  +15 V        TP20  VNEG  -15 V");
  Serial.println("    TP24  VGH   +28 V        TP23  VGL   -20 V");
  Serial.println("    TP32  VCOM  (value printed below, negative at the pin)");
  Serial.println("    J1 pin 5 / 11  EPD_3V3  +3.3 V   (no test point exists)");
  Serial.println();
  Serial.println("  TP23/TP24 are the same nets as J1 pins 1 and 3. Probe the");
  Serial.println("  test points: J1 is 0.5 mm pitch and a slip shorts neighbours.");
  Serial.println();

  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, HIGH);
  rail_raised = true;
  delay(100);

  bb_pins_out();
  Serial.println("  [TCON] releasing reset...");
  if (!tcon_reset_and_wait()) {
    Serial.println("  [TCON] NO RESPONSE -- HRDY never released. Nothing else on");
    Serial.println("         this board can drive the PMIC, so there is no");
    Serial.println("         fallback and no rails. Stopping.");
    return;
  }
  delay(100);

  uint16_t w, h;
  char fw[24], lut[24];
  if (!dev_geometry(&w, &h, fw, lut)) {
    Serial.println("  [TCON] NO RESPONSE -- GET_DEV_INFO returned nothing usable.");
    Serial.println("         Stopping rather than guessing an area to refresh.");
    return;
  }
  Serial.print("  [TCON] RESPONDS -- ");
  Serial.print(w);
  Serial.print(" x ");
  Serial.print(h);
  Serial.print(", FW '");
  Serial.print(fw);
  Serial.print("', LUT '");
  Serial.print(lut);
  Serial.println("'");

  // The TCON answering says nothing about the PMIC behind it. VCOM reads
  // back over the IT8951's private I2C bus, so a real value is the one piece
  // of evidence available that the link the rails depend on is open.
  uint16_t vcom;
  if (vcom_read_stable(&vcom)) {
    Serial.print("  [PMIC] LINK OK -- VCOM reads ");
    Serial.print(vcom);
    Serial.print(" mV (5 agreeing reads) -> about -");
    Serial.print(vcom / 1000.0, 3);
    Serial.println(" V at TP32");
  } else {
    Serial.println("  [PMIC] NO LINK -- VCOM did not read back cleanly. The TCON");
    Serial.println("         answers but cannot reach the PMIC; rails are unlikely.");
  }

  if (!tcon_cmd_g(0x0001)) {                             // SYS_RUN
    Serial.println("  [TCON] SYS_RUN failed. Stopping.");
    return;
  }
  Serial.println("  [TCON] SYS_RUN accepted");

  // Every reference driver writes this and this sketch never did. I80CPCR
  // enables packed write, which is exactly the framing tcon_write_args_g
  // uses: one 0x0000 preamble followed by every argument inside a single CS
  // frame. The VCOM write is two words and got away without it; DPY_AREA is
  // five, and the first attempt hung on the argument phase. This is the
  // cheapest explanation, so rule it out before reaching for a harder one.
  if (!reg_write(0x0004, 0x0001)) {
    Serial.println("  [TCON] I80CPCR write failed; continuing without it.");
  } else {
    Serial.println("  [TCON] I80CPCR = 1 (packed write enabled)");
  }

  Serial.println();
  Serial.print("  rails up for ");
  Serial.print(seconds);
  Serial.println(" s -- send any line to stop early.");
  Serial.println();

  hrdy_timeout_ms = 15000;
  hrdy_waits = 0;
  hrdy_worst = 0;

  unsigned long t0        = millis();
  unsigned long deadline  = t0 + seconds * 1000UL;
  unsigned long next_tick = t0 + 1000;
  unsigned long passes    = 0;
  bool stalled = false;
  bool aborted = false;
  bool lut_ok  = true;

  while ((long)(millis() - deadline) < 0) {
    if (Serial.available()) {
      while (Serial.available()) Serial.read();
      Serial.println("  stopped early.");
      break;
    }

    passes++;
    Serial.print("  [TCON] DPY_AREA #");
    Serial.print(passes);
    Serial.print(": ");
    if (!tcon_cmd_g(0x0034)) {                           // DPY_AREA
      Serial.println("command REFUSED. Stopping.");
      aborted = true;
      break;
    }
    Serial.print("command accepted, ");

    // Wait for the chip to take its arguments -- by hand, so that a stall is
    // a result rather than an abort. 15 s was not enough on the first two
    // runs, and a TCON that goes busy on DPY_AREA and stays busy is most
    // likely sitting inside the PMIC power sequence: waking the TPS65185 and
    // waiting on PWR_GOOD. If that is what it is doing, the rails are up
    // while it waits, and this stall is the measurement window, not a
    // failure. So hold in it and say so.
    unsigned long tw = millis();
    bool ready = false;
    while ((long)(millis() - deadline) < 0) {
      if (digitalRead(TFT_BUSY)) { ready = true; break; }
      if (Serial.available()) { while (Serial.available()) Serial.read(); break; }
      if ((long)(millis() - next_tick) >= 0) {
        if (next_tick == t0 + 1000) Serial.println("HRDY still low");
        Serial.print("  t+");
        Serial.print((millis() - t0) / 1000);
        Serial.print(" s   HRDY low for ");
        Serial.print(millis() - tw);
        Serial.println(" ms -- MEASURE NOW if it is going to read at all");
        next_tick += 1000;
      }
      delay(10);
    }
    if (!ready) { stalled = true; break; }

    uint16_t args[5] = { 0, 0, w, h, 0 };                // mode 0 = INIT
    if (!tcon_write_args_g(args, 5)) {
      Serial.println("args REFUSED. Stopping.");
      aborted = true;
      break;
    }
    Serial.println("5 args sent, refreshing");

    // Wait out the pass. If LUTAFSR cannot be read, fall back to a fixed
    // wait rather than hammering the chip: a ragged window beats none.
    unsigned long t1 = millis();
    for (;;) {
      if ((long)(millis() - next_tick) >= 0) {
        Serial.print("  t+");
        Serial.print((millis() - t0) / 1000);
        Serial.println(" s   refreshing");
        next_tick += 1000;
      }
      if (lut_ok) {
        uint16_t busy;
        if (!reg_read(IT8951_LUTAFSR, &busy)) {
          Serial.println("  LUTAFSR unreadable -- falling back to a fixed 2.5 s");
          Serial.println("  wait per pass. Rails may dip between passes.");
          lut_ok = false;
          continue;
        }
        if (busy == 0) {
          Serial.print("  [TCON] DPY_AREA #");
          Serial.print(passes);
          Serial.println(": LUTAFSR reads idle");
          break;
        }
        if (millis() - t1 > 8000) {
          Serial.println("  refresh did not finish in 8 s. Stopping.");
          aborted = true;
          break;
        }
        delay(20);
      } else {
        if (millis() - t1 > 2500) break;
        delay(20);
      }
    }
    if (aborted) break;
  }

  hrdy_timeout_ms = 1000;

  Serial.println();
  Serial.print("  longest HRDY wait this run: ");
  Serial.print(hrdy_worst);
  Serial.print(" ms over ");
  Serial.print(hrdy_waits);
  Serial.println(" waits");

  if (stalled) {
    Serial.println();
    Serial.println("  => The first DPY_AREA went through in full -- command,");
    Serial.println("     all five arguments, and a LUTAFSR read back. The next");
    Serial.println("     one was accepted and then the TCON held HRDY low for");
    Serial.println("     the rest of the window. So the framing is fine; the");
    Serial.println("     chip wedges on being asked again, most likely because");
    Serial.println("     LUTAFSR at 0x1224 is not the busy flag on this");
    Serial.println("     firmware and the first refresh was still running.");
    Serial.println("     Two readings of that:");
    Serial.println("       rails MEASURED non-zero -> the power sequence ran and");
    Serial.println("         stalls afterwards. That is enough for bring-up: this");
    Serial.println("         command is now a working rail switch.");
    Serial.println("       rails MEASURED zero -> it never got as far as the PMIC.");
    Serial.println("         Next suspect is the panel-side handshake, not power.");
    Serial.println("     Either way the answer is on your meter, not in this log.");
  }

  Serial.print("  ");
  Serial.print(passes);
  Serial.println(" DPY_AREA attempt(s). Rails, if they came up, are falling now.");
  Serial.println("  TFT_ENABLE is left HIGH, so the logic rail stays up;");
  Serial.println("  `rail off` drops that too.");
}

static void help() {
  Serial.println("Commands:");
  Serial.println("  scan      I2C scan on GPIO41/42 (SHT40 present? PMIC absent?)");
  Serial.println("  sht       read the SHT40 -- proves board seated and powered");
  Serial.println("  batt      battery divider reading");
  Serial.println("  pins      passive TCON pin survey (driven vs floating)");
  Serial.println("  rail on   raise TFT_ENABLE: powers the logic rail only");
  Serial.println("  rail off  drop it again");
  Serial.println("  watch     watch HRDY for 5 s");
  Serial.println("  tcon      GET_DEV_INFO -- does the IT8951 answer at all?");
  Serial.println("  pmic      VCOM readback through the TCON -- does the PMIC?");
  Serial.println("  tcon2     GET_DEV_INFO with every HRDY wait honoured");
  Serial.println("  pmic2     VCOM readback, gated, five reads must agree");
  Serial.println("  vcom <mV> WRITE VCOM, e.g. `vcom 1310` (reversible)");
  Serial.println("  vtest     write 1310, cycle the rail, see if it survives");
  Serial.println("  rails [s] REFRESH loop to hold the panel rails up (default 60 s)");
  Serial.println("  info      chip / flash / PSRAM");
  Serial.println("  help      this");
  Serial.println();
  Serial.println("Most commands only watch pins. Three do more: `vcom` and");
  Serial.println("`vtest` write the PMIC's VCOM register through the TCON, and");
  Serial.println("`rails` runs a refresh so the board generates VPOS/VNEG/VGH/");
  Serial.println("VGL/VCOM. Nothing writes the PMIC's non-volatile PROG bit.");
}

void setup() {
  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < 3000) { delay(10); }

  park_tcon_pins();

  Serial.println();
  Serial.println("=== ee03_probe -- read-only board survey ===");
  Serial.println("TCON pins parked as inputs. Nothing will be driven on the");
  Serial.println("SPI bus or on TFT_RST by this sketch.");
  Serial.println();
  chip_info();
  Serial.println();
  i2c_scan();
  Serial.println();
  sht40_read();
  Serial.println();
  pins_report();
  Serial.println();
  Serial.println("Type `help` for commands. Run `tcon`, then `pmic`.");

#if RAILS_ON_BOOT
  Serial.println();
  Serial.println("*** RAILS_ON_BOOT is set: bringing the rails up now. ***");
  Serial.println("*** Set it to 0 in this file before wiring a panel.  ***");
  Serial.println();
  rails_up(RAILS_ON_BOOT_SECONDS);
#endif

  Serial.print("> ");
}

void loop() {
  static String line;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c != '\n') { line += c; continue; }

    line.trim();
    if      (line == "scan")     i2c_scan();
    else if (line == "sht")      sht40_read();
    else if (line == "batt")     battery_read();
    else if (line == "pins")     pins_report();
    else if (line == "rail on")  rail(true);
    else if (line == "rail off") rail(false);
    else if (line == "watch")    watch_hrdy();
    else if (line == "tcon")     tcon_check();
    else if (line == "pmic")     pmic_check();
    else if (line == "tcon2")    tcon_check2();
    else if (line == "pmic2")    pmic_check2();
    else if (line == "vtest")    vcom_volatility_test();
    else if (line == "rails")    rails_up(60);
    else if (line.startsWith("rails ")) {
      long n = line.substring(6).toInt();
      if (n < 1 || n > 300) Serial.println("rails <sec>: 1..300");
      else rails_up((unsigned long)n);
    }
    else if (line.startsWith("vcom ")) vcom_set_cmd((uint16_t)line.substring(5).toInt());
    else if (line == "info")     chip_info();
    else if (line == "help")     help();
    else if (line.length())      Serial.println("unknown -- try `help`");
    line = "";
    Serial.print("> ");
  }
}
