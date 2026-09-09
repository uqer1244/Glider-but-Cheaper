// EE03 as the Glider PMIC -- hold the rails for the FPGA, and self-test the
// panel when it is plugged into J1.
//
// This folder is the only copy. The superseded xiao_pmic (wrong PMIC register
// addresses, PROGRESS.md 1.14/1.15) is kept under legacy/ because it carries
// work that was never committed. See README.md here, and ../docs/WIRING.md
// for the harness that turns EE03 into a power-only board for the FPGA.
//
// What this is
// ------------
// The FPGA is not involved. Here the EE03's own IT8951 TCON drives the panel,
// because it is the only thing on this board that can run the TPS65185 power
// sequence: the PMIC sits on the IT8951's private I2C bus and its WAKEUP and
// PWRUP pins are IT8951 GPIOs (PROGRESS.md 1.13 / 1.21). So "a picture on the
// glass" and "the rails came up" are the same experiment, and if the picture
// appears, the whole power chain is proven at once.
//
// The resolution does not match, and that is accepted
// ---------------------------------------------------
// The TCON's flashed profile is the Seeed kit's 10.3" panel -- it reports
// 1872x1404, LUT '3M29T' (1.19) -- while the panel is 2760x2070. Driving it at
// the profile's geometry updates the first 1872 columns of the first 1404 rows
// and leaves the rest of the glass untouched. Ink moves, which is the point.
// `geo 115` instead asks for the full 2760x2070, which is what Seeed's own
// ED115OC1 example overrides the host-side geometry to; whether this firmware
// honours a scan wider than its own profile is unknown, so it is a command and
// not the default. Neither can damage anything: too few gate clocks just stops
// the scan early.
//
// The one thing that is not optional
// ----------------------------------
// VCOM. The board comes up at -2.50 V on every power cycle (the register is
// volatile, 1.20) and the panel is labelled -1.31 V. Nothing in this sketch
// refreshes the panel until VCOM has been written and read back three times as
// VCOM_MV_TARGET. `force` lifts that interlock and says what it is lifting.
//
// Transport
// ---------
// Same framing as ee03_probe, which is the framing that works on this board:
// HRDY is waited on before the frame, after the preamble, and after the read
// dummy word (1.19 -- skipping that last wait is what made a live chip look
// dead). The difference is hardware SPI instead of bit-bang, because 1.3 MB of
// pixels at the probe's ~250 kHz would take 40 minutes. Command arguments go
// one word per CS frame, the way the ITE reference driver sends them, not
// packed into one frame the way ee03_probe's `rails` did -- that packed path is
// where the TCON wedged on its second DPY_AREA (1.21). If the transport
// misbehaves, drop SPI_WRITE_HZ; ee03_probe remains the known-good slow path.
//
// Wiring: the panel FPC goes straight into J1, no breakout. Verified against
// the PCB netlist: J1 pin 40 reaches VCOM through R60 (0R, fitted) so it
// matches the panel's pin 40 = VCOM; 36 = +15 V, 38 = -15 V, 37 = NC;
// pin 34 is +3V3 through R121, harmless because the panel side is NC.
// PROGRESS.md 1.18's corrected table is the right one. plan.md 1.2's EE03
// column (36=NC / 37=+15V / 34=GND) is stale -- do not wire from it.
//
// The three buttons on the board
// ------------------------------
// EE03 has BUTTON1/2/3 (SW3/SW4/SW5) wired to the XIAO's pads 2, 3 and 5 --
// GPIO2, GPIO3, GPIO5 -- each with a 10K pull-up to ESP_3V3 and a 100 nF cap,
// switching to ground. Active low, already debounced in hardware. Verified
// against the PCB netlist, cross-checked with PWR_EN on pad 7 = GPIO43.
//
//   BUTTON1  short: refresh the current pattern (GC16)
//            long:  next pattern, then refresh
//   BUTTON2  short: clear the glass to white (load white + INIT)
//            long:  SLEEP -- drops the panel rails
//   BUTTON3  short: start -- the whole sequence from reset to a picture
//            long:  HOLD RAILS on/off -- the mode the FPGA needs (see below)
//
// A button pressed before anything else brings the board up on its own, VCOM
// interlock included, so the serial console is optional. SW2 is the XIAO's
// reset and SW1 is the slide switch; neither is read here.
//
// Holding the rails up for the FPGA
// ---------------------------------
// Measured 2026-09-09: once a refresh has run, VPOS/VNEG/VGH/VGL stay up for as
// long as the TCON is left in SYS_RUN. Nothing here ever calls SLEEP on its own
// (Seeed_GFX's update() does, and that call is deliberately absent), so the
// rails simply persist. `hold` is therefore cheap: bring up, set VCOM, SYS_RUN,
// one INIT refresh -- no image stream at all -- and walk away. It also leaves
// the glass white, which is the right baseline before something else drives it.
//
// BUTTON2 vs BUTTON3 look alike and are not. SLEEP hands the job to the
// TPS65185's own down-sequencer, so the rails fall in the order the panel
// expects. Cutting PWR_EN pulls the PMIC's input away and every rail decays at
// whatever its own capacitance decides. So: BUTTON2 normally, BUTTON3 when
// something is wrong -- and BUTTON3 uses no SPI, so it still works when the
// TCON is wedged (PROGRESS.md 1.21). It is polled inside the HRDY and refresh
// wait loops too, because an emergency stop that only works when the firmware
// is idle is not an emergency stop.
//
// What the TCON can and cannot reach
// ----------------------------------
// With a power-only harness the TCON's ED0-15/SDCLK/SDLE/GDCLK go nowhere, and
// it can hammer them harmlessly. But it still reaches the panel through the
// PMIC: VCOM, the rails and EPD_3V3 are all its to command. That is why VCOM is
// verified before the rails come up AND again after, and why a mismatch that
// survives a rewrite drops the rails instead of shrugging.
//
// RAILS_READY (GPIO39) goes high while the rails are held, as a handshake for
// the FPGA. It says "asked for, and nothing has slept since" -- not "measured":
// PWR_GOOD is an IT8951 GPIO with no path to the XIAO (1.21), so this pin is an
// intent, not a sensor. GPIO39 is XIAO pad 16, which on EE03 goes only to U6's
// chip select, and U6 (GT30L32S4W) is DNP with its pull-up R39 also DNP -- so
// the pad is free and solderable at U6 pin 1.
//
// !! Two things this does not solve, both of them wiring:
//   1. The IT8951 still drives ED0-15/SDCLK/SDLE/GDCLK, and those are J1's own
//      pins. With the panel in J1, an FPGA driving the same nets is a bus
//      fight. EE03 has to become a power-only board: take VGL(1) VGH(3)
//      3V3(5,11) GND(9,12,22) VCOM(10) +15V(36) -15V(38) off J1 to a breakout,
//      put the panel there, and leave J1's data pins connected to nothing.
//   2. Rails up with no scan means DC on the ink. On EE03 that is covered by
//      accident -- GDOE(6) and SDOE(33) are pulled to EPD_3V3, which is the
//      PMIC's own switched 3.3 V, so they fall with the rails, and the gate
//      shift register ends a frame with every line off. On a breakout the FPGA
//      must own GDOE/SDOE (Glider's DRIVE gate already drops them) and they
//      want 10K pull-downs so they cannot float while the FPGA is unloaded.
//
// Commands: info, vcom [mv], temp [c], geo fw|115, pat <0-5>, init, show,
//           du, run, hold, drop, status, sleep, wake, rail on|off,
//           mirror on|off, force, help

#include "driver.h"
#include <SPI.h>

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#warning "Pin numbers here (GPIO43/44) are XIAO ESP32-S3. Check your board."
#endif

// ------------------------------------------------------------------ config

#define VCOM_MV_TARGET   1310    // panel label -1.31 V (PROGRESS.md 1.19)
#define SET_TEMP_C       25      // host-supplied temperature, as Seeed_GFX does
#define SPI_WRITE_HZ     10000000
#define SPI_READ_HZ      1000000  // reads are 1..20 words: correctness over speed
#define HRDY_TIMEOUT_MS  15000   // longest honest wait seen is 30 ms (1.19)
#define PANEL_115_W      2760
#define PANEL_115_H      2070

// RAILS_READY handshake output for the FPGA. Harmless with nothing soldered:
// the only thing on this net is an unpopulated chip's CS pin. Set to -1 to
// leave the pin alone entirely.
#define RAILS_READY_PIN  39

// Does SYS_RUN alone raise the rails, or does it take a refresh? Unmeasured as
// of 2026-09-09, so this defaults to the path that is known to work. If a
// measurement shows SYS_RUN is enough (`rail on`, `info`, measure TP21 = 0 V,
// then `wake`, measure again), set this to 0: rails ON then never touches the
// display engine at all, and comes up instantly instead of in two seconds.
#define RAILS_NEED_REFRESH 1

// Drop the rails after this many minutes of holding, as a backstop against
// leaving high voltage on an idle panel. 0 = never, which is what the FPGA
// bring-up wants.
#define RAILS_TIMEOUT_MIN 0

// Refresh on boot? Left off deliberately. A panel is attached now, and the
// project's own notes call unattended high voltage a stop-the-line item. One
// typed `run` costs nothing; flip this to 1 once a manual run has worked.
#define RUN_ON_BOOT      0

// ------------------------------------------------------------- IT8951 defs

#define CMD_SYS_RUN      0x0001
#define CMD_STANDBY      0x0002
#define CMD_SLEEP        0x0003
#define CMD_REG_RD       0x0010
#define CMD_REG_WR       0x0011
#define CMD_LD_IMG_AREA  0x0021
#define CMD_LD_IMG_END   0x0022
#define CMD_DPY_AREA     0x0034
#define CMD_VCOM         0x0039
#define CMD_TEMP         0x0040
#define CMD_GET_DEV_INFO 0x0302

#define REG_I80CPCR      0x0004
#define REG_LISAR        0x0208   // MCSR base 0x0200 + 0x08
#define REG_LUTAFSR      0x1224   // DISPLAY base 0x1000 + 0x224

// EE03's user buttons, active low (10K to ESP_3V3, 100 nF, switch to GND)
#define BTN_ON_PIN       2        // BUTTON1, SW3, XIAO pad 2 / D1  -- rails on
#define BTN_OFF_PIN      3        // BUTTON2, SW4, XIAO pad 3 / D2  -- rails off
#define BTN_EMERG_PIN    5        // BUTTON3, SW5, XIAO pad 5 / D4  -- cut PWR_EN
#define BTN_DEBOUNCE_MS  30

#define BPP_4            2        // IT8951_4BPP
#define ENDIAN_LITTLE    0
#define ROTATE_0         0

#define MODE_INIT        0
#define MODE_DU          1
#define MODE_GC16        2

// ------------------------------------------------------------------- state

#ifdef ARDUINO_XIAO_ESP32S3
static SPIClass tconSPI(HSPI);
#else
static SPIClass tconSPI(FSPI);
#endif

static uint16_t fw_w = 0, fw_h = 0;      // geometry the TCON claims for itself
static uint32_t img_addr = 0;            // its image buffer base
static char     fw_ver[24] = "", lut_ver[24] = "";
static bool     use_115 = false;         // geometry override
static uint8_t  pattern = 2;
// Seeed_GFX's EE03 setup defines EPD_HORIZONTAL_MIRROR and reverses each row
// before sending it, so this panel is probably mirrored left-to-right against
// the buffer. Unverified, so it starts off: if the origin block lands top-RIGHT
// or the staircase runs light-to-dark, turn it on.
static bool     mirror = false;
static bool     forced = false;          // VCOM interlock lifted
static bool     rail_up = false;
static bool     awake = false;
static bool     rails_held = false;
static unsigned long rails_since = 0;
static unsigned long hrdy_worst = 0;
static unsigned long hrdy_waits = 0;

static uint8_t rowbuf[PANEL_115_W / 4 * 2];

static uint16_t act_w() { return use_115 ? PANEL_115_W : fw_w; }
static uint16_t act_h() { return use_115 ? PANEL_115_H : fw_h; }

// -------------------------------------------------------------- transport

// Declared here because the wait loops below poll it: an emergency stop that
// only works while the firmware is idle is not an emergency stop.
static void emergency_cut(const char *why);
static bool aborted_by_button = false;
static inline bool emergency_pressed() { return digitalRead(BTN_EMERG_PIN) == LOW; }

static bool hrdy_wait(const char *where) {
  unsigned long t0 = millis();
  if (digitalRead(TFT_BUSY)) return true;
  while (!digitalRead(TFT_BUSY)) {
    if (emergency_pressed()) { emergency_cut("BUTTON3 during an HRDY wait"); return false; }
    if (millis() - t0 > HRDY_TIMEOUT_MS) {
      Serial.print("  !! HRDY never released (");
      Serial.print(where);
      Serial.print(", ");
      Serial.print(millis() - t0);
      Serial.println(" ms). Aborting this operation.");
      return false;
    }
  }
  unsigned long waited = millis() - t0;
  hrdy_waits++;
  if (waited > hrdy_worst) hrdy_worst = waited;
  return true;
}

static void frame_begin(uint32_t hz) {
  tconSPI.beginTransaction(SPISettings(hz, MSBFIRST, SPI_MODE0));
  digitalWrite(TFT_CS, LOW);
}

static void frame_end() {
  digitalWrite(TFT_CS, HIGH);
  tconSPI.endTransaction();
}

static bool tcon_cmd(uint16_t cmd) {
  if (!hrdy_wait("before command")) return false;
  frame_begin(SPI_WRITE_HZ);
  tconSPI.transfer16(0x6000);
  if (!hrdy_wait("after command preamble")) { frame_end(); return false; }
  tconSPI.transfer16(cmd);
  frame_end();
  return true;
}

// One word, one CS frame -- the reference driver's tconWirteData.
static bool tcon_arg(uint16_t v) {
  if (!hrdy_wait("before argument")) return false;
  frame_begin(SPI_WRITE_HZ);
  tconSPI.transfer16(0x0000);
  if (!hrdy_wait("after write preamble")) { frame_end(); return false; }
  tconSPI.transfer16(v);
  frame_end();
  return true;
}

static bool tcon_args(const uint16_t *a, int n) {
  for (int i = 0; i < n; i++) if (!tcon_arg(a[i])) return false;
  return true;
}

// The wait after the dummy word is the fix from PROGRESS.md 1.19. Without it
// this returns plausible garbage, not zeros -- so never trust a single read.
static bool tcon_read(uint16_t *out, int n) {
  if (!hrdy_wait("before read")) return false;
  frame_begin(SPI_READ_HZ);
  tconSPI.transfer16(0x1000);
  if (!hrdy_wait("after read preamble")) { frame_end(); return false; }
  tconSPI.transfer16(0x0000);                       // dummy, discarded
  if (!hrdy_wait("after dummy word")) { frame_end(); return false; }
  // HRDY before EVERY word, not just once. The reference driver waits once and
  // gets away with it; at 4 MHz this read came back with word 8 repeated --
  // GET_DEV_INFO said FW 'Seeed_v.v.0.1' where the bit-banged read in
  // PROGRESS.md 1.19 says 'Seeed_v.0.1', and the trailing NULs hid the shift.
  // A stale word in a 1-word register read is a wrong LUTAFSR, which is a
  // refresh that looks finished when it is not.
  for (int i = 0; i < n; i++) {
    if (!hrdy_wait("read word")) { frame_end(); return false; }
    out[i] = tconSPI.transfer16(0x0000);
  }
  frame_end();
  return true;
}

// ----------------------------------------------------------- IT8951 verbs

static bool reg_wr(uint16_t addr, uint16_t val) {
  if (!tcon_cmd(CMD_REG_WR)) return false;
  uint16_t a[2] = { addr, val };
  return tcon_args(a, 2);
}

static bool reg_rd(uint16_t addr, uint16_t *val) {
  if (!tcon_cmd(CMD_REG_RD)) return false;
  if (!tcon_arg(addr)) return false;
  return tcon_read(val, 1);
}

static bool tcon_reset() {
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);
  delay(50);
  digitalWrite(TFT_RST, HIGH);
  unsigned long t0 = millis();
  while (millis() - t0 < 5000) {
    if (digitalRead(TFT_BUSY)) {
      Serial.print("  HRDY released at ");
      Serial.print(millis() - t0);
      Serial.println(" ms (1601/1605 ms is this chip booting normally)");
      awake = false;
      return true;
    }
    delay(5);
  }
  Serial.println("  HRDY never released in 5 s -- the TCON is not booting.");
  return false;
}

static void words_to_str(const uint16_t *w, int from, int to, char *out) {
  int n = 0;
  for (int i = from; i < to; i++) {
    char a = w[i] >> 8, b = w[i] & 0xFF;
    if (a >= 32 && a < 127) out[n++] = a;
    if (b >= 32 && b < 127) out[n++] = b;
  }
  out[n] = 0;
}

static bool dev_info() {
  uint16_t info[20];
  if (!tcon_cmd(CMD_GET_DEV_INFO)) return false;
  if (!tcon_read(info, 20)) return false;
  if (info[0] == 0 || info[1] == 0 || info[0] > 4096 || info[1] > 4096) {
    Serial.println("  GET_DEV_INFO returned nothing usable -- transport is wrong.");
    return false;
  }
  fw_w = info[0];
  fw_h = info[1];
  img_addr = (uint32_t)info[2] | ((uint32_t)info[3] << 16);
  words_to_str(info, 4, 12, fw_ver);
  words_to_str(info, 12, 20, lut_ver);
  Serial.print("  TCON profile ");
  Serial.print(fw_w);
  Serial.print(" x ");
  Serial.print(fw_h);
  Serial.print(", image buffer 0x");
  Serial.print(img_addr, HEX);
  Serial.print(", FW '");
  Serial.print(fw_ver);
  Serial.print("', LUT '");
  Serial.print(lut_ver);
  Serial.println("'");
  return true;
}

static bool vcom_read(uint16_t *mv) {
  if (!tcon_cmd(CMD_VCOM)) return false;
  if (!tcon_arg(0x0000)) return false;            // 0 = get
  return tcon_read(mv, 1);
}

static bool vcom_write(uint16_t mv) {
  if (!tcon_cmd(CMD_VCOM)) return false;
  uint16_t a[2] = { 0x0002, mv };                 // 2 = set
  return tcon_args(a, 2);
}

// Three agreeing reads, because an ungated read gives plausible garbage and
// the most convincing wrong answer this board ever produced was 1404 (1.19).
static bool vcom_read_stable(uint16_t *mv) {
  uint16_t v[3];
  for (int i = 0; i < 3; i++) {
    if (!vcom_read(&v[i])) return false;
    delay(20);
  }
  if (v[0] != v[1] || v[1] != v[2]) {
    Serial.print("  VCOM reads disagree: ");
    Serial.print(v[0]); Serial.print(" / ");
    Serial.print(v[1]); Serial.print(" / ");
    Serial.println(v[2]);
    return false;
  }
  *mv = v[0];
  return true;
}

static bool temp_read(uint16_t *c) {
  if (!tcon_cmd(CMD_TEMP)) return false;
  if (!tcon_arg(0x0000)) return false;
  return tcon_read(c, 1);
}

static bool temp_write(uint16_t c) {
  if (!tcon_cmd(CMD_TEMP)) return false;
  uint16_t a[2] = { 0x0001, c };
  return tcon_args(a, 2);
}

static bool set_img_base(uint32_t addr) {
  if (!reg_wr(REG_LISAR + 2, (uint16_t)(addr >> 16))) return false;
  return reg_wr(REG_LISAR, (uint16_t)(addr & 0xFFFF));
}

static bool ld_img_area(uint16_t x, uint16_t y, uint16_t w, uint16_t h) {
  uint16_t a[5];
  a[0] = (ENDIAN_LITTLE << 8) | (BPP_4 << 4) | ROTATE_0;
  a[1] = x; a[2] = y; a[3] = w; a[4] = h;
  if (!tcon_cmd(CMD_LD_IMG_AREA)) return false;
  return tcon_args(a, 5);
}

static bool dpy_area(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t mode) {
  uint16_t a[5] = { x, y, w, h, mode };
  if (!tcon_cmd(CMD_DPY_AREA)) return false;
  return tcon_args(a, 5);
}

// LUTAFSR reads 0 when the display engine is idle. ee03_probe saw it read idle
// instantly and then wedged the chip by issuing the next command, so an idle
// reading is only believed after min_ms has actually passed.
static bool wait_display(unsigned long min_ms, unsigned long timeout_ms) {
  unsigned long t0 = millis();
  unsigned long tick = t0 + 1000;
  for (;;) {
    if (emergency_pressed()) { emergency_cut("BUTTON3 during a refresh"); return false; }
    uint16_t busy;
    if (!reg_rd(REG_LUTAFSR, &busy)) return false;
    unsigned long el = millis() - t0;
    if (busy == 0 && el >= min_ms) {
      Serial.print("  engine idle after ");
      Serial.print(el);
      Serial.println(" ms");
      delay(100);                                 // let it settle before the next command
      return true;
    }
    if (el > timeout_ms) {
      Serial.print("  engine still busy after ");
      Serial.print(el);
      Serial.println(" ms. Giving up on this refresh.");
      return false;
    }
    if ((long)(millis() - tick) >= 0) {
      Serial.print("    t+");
      Serial.print(el / 1000);
      Serial.print(" s  LUTAFSR=0x");
      Serial.println(busy, HEX);
      tick += 1000;
    }
    delay(20);
  }
}

// ------------------------------------------------------------------ pixels

static const char *pattern_name(uint8_t p) {
  switch (p) {
    case 0: return "white";
    case 1: return "black";
    case 2: return "16-step grey staircase";
    case 3: return "smooth horizontal ramp";
    case 4: return "128 px checkerboard";
    case 5: return "geometry: border + 200 px grid + origin block + diagonal";
  }
  return "?";
}

static uint8_t pixel(int x, int y, int w, int h) {
  switch (pattern) {
    case 0: return 15;
    case 1: return 0;
    case 2: {
      int s = (int)((long)x * 16 / w);
      return s > 15 ? 15 : s;
    }
    case 3: return (uint8_t)((long)x * 15 / (w - 1));
    case 4: return (((x >> 7) ^ (y >> 7)) & 1) ? 0 : 15;
    case 5: {
      if (x < 8 || y < 8 || x >= w - 8 || y >= h - 8) return 0;
      if (x < 200 && y < 200) return 0;                  // origin, unmistakable
      if ((x % 200) < 2 || (y % 200) < 2) return 7;
      int d = x - (int)((long)y * w / h);
      if (d < 0) d = -d;
      if (d < 3) return 0;
      return 15;
    }
  }
  return 15;
}

// 4 bpp, little endian: pixel i of the group of four sits in nibble i, and the
// word goes on the wire high byte first. Every pattern above has features far
// wider than 4 px, so a nibble-order mistake would show as a 3 px edge shift
// and nothing more.
static void fill_row(int words, int y, int w, int h) {
  for (int i = 0; i < words; i++) {
    uint16_t word = 0;
    for (int k = 0; k < 4; k++) {
      int x = i * 4 + k;
      if (x >= w) x = w - 1;
      if (mirror) x = w - 1 - x;
      word |= (uint16_t)(pixel(x, y, w, h) & 0x0F) << (4 * k);
    }
    rowbuf[2 * i]     = (uint8_t)(word >> 8);
    rowbuf[2 * i + 1] = (uint8_t)(word & 0xFF);
  }
}

// The whole image in one CS frame: preamble once, then every row. This is the
// one place packed mode (I80CPCR = 1) is required.
static bool stream_image(uint16_t w, uint16_t h) {
  int words = (w + 3) / 4;
  if (!hrdy_wait("before pixel stream")) return false;
  unsigned long t0 = millis();
  frame_begin(SPI_WRITE_HZ);
  tconSPI.transfer16(0x0000);
  if (!hrdy_wait("after pixel preamble")) { frame_end(); return false; }
  for (int y = 0; y < h; y++) {
    fill_row(words, y, w, h);
    tconSPI.writeBytes(rowbuf, words * 2);
    if (!digitalRead(TFT_BUSY) && !hrdy_wait("mid-stream")) { frame_end(); return false; }
    if ((y & 255) == 255) { Serial.print("."); }
  }
  frame_end();
  Serial.print(" ");
  Serial.print((long)words * 2 * h / 1024);
  Serial.print(" KB in ");
  Serial.print(millis() - t0);
  Serial.println(" ms");
  return true;
}

// -------------------------------------------------------------- sequences

static void rail(bool on) {
  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, on ? HIGH : LOW);
  rail_up = on;
  Serial.print("  PWR_EN (GPIO43) -> ");
  Serial.println(on ? "HIGH: logic rail and the PMIC's VIN load switch are on"
                    : "LOW: both off");
}

// The handshake pin. Named for what it can honestly claim.
static void rails_ready(bool up) {
#if RAILS_READY_PIN >= 0
  pinMode(RAILS_READY_PIN, OUTPUT);
  digitalWrite(RAILS_READY_PIN, up ? HIGH : LOW);
#endif
}

static bool bring_up() {
  if (!rail_up) { rail(true); delay(100); }
  if (!tcon_reset()) return false;
  delay(100);
  if (!dev_info()) return false;
  if (!reg_wr(REG_I80CPCR, 0x0001)) {
    Serial.println("  I80CPCR write failed -- the pixel stream needs it. Stopping.");
    return false;
  }
  Serial.println("  I80CPCR = 1 (packed write enabled)");
  return true;
}

// The interlock. Everything that puts voltage on the glass goes through here.
static bool vcom_ok() {
  uint16_t mv;
  if (!vcom_write(VCOM_MV_TARGET)) { Serial.println("  VCOM write failed."); return false; }
  delay(100);
  if (!vcom_read_stable(&mv)) {
    Serial.println("  VCOM could not be read back. Not refreshing.");
    return forced;
  }
  Serial.print("  VCOM = ");
  Serial.print(mv);
  Serial.print(" mV (about -");
  Serial.print(mv / 1000.0, 3);
  Serial.println(" V at TP32)");
  if (mv == VCOM_MV_TARGET) return true;
  Serial.print("  !! VCOM is not ");
  Serial.print(VCOM_MV_TARGET);
  Serial.println(" mV. The panel is labelled -1.31 V; the board's own default");
  Serial.println("     is -2.50 V, which is far stronger. Refusing to refresh.");
  Serial.println("     `force` overrides this if you know why you want to.");
  return forced;
}

static bool sys_run() {
  if (awake) return true;
  if (!tcon_cmd(CMD_SYS_RUN)) return false;
  awake = true;
  uint16_t t;
  if (temp_read(&t)) {
    if (t == 0xFFFF) Serial.println("  TCON temperature: not available (0xFFFF)");
    else { Serial.print("  TCON temperature reads ");
           Serial.print((int8_t)(t & 0xFF)); Serial.println(" C"); }
  }
#if SET_TEMP_C > 0
  if (temp_write(SET_TEMP_C)) {
    Serial.print("  host temperature set to ");
    Serial.print(SET_TEMP_C);
    Serial.println(" C (Seeed_GFX does this before every update)");
  }
#endif
  return true;
}

static void rails_hint() {
  Serial.println("  >>> the PMIC power sequence runs NOW. Against TP41 (GND):");
  Serial.println("      TP21 VPOS +15   TP20 VNEG -15   TP24 VGH +28   TP23 VGL -20");
}

static bool refresh(uint16_t mode, const char *what, unsigned long min_ms) {
  uint16_t w = act_w(), h = act_h();
  Serial.print("  DPY_AREA 0,0,");
  Serial.print(w); Serial.print(",");
  Serial.print(h); Serial.print(" mode ");
  Serial.print(mode); Serial.print(" (");
  Serial.print(what); Serial.println(")");
  rails_hint();
  if (!dpy_area(0, 0, w, h, mode)) {
    Serial.println("  DPY_AREA never got its arguments in. This is the shape of the");
    Serial.println("  wedge in PROGRESS.md 1.21: a second refresh issued while the");
    Serial.println("  engine was still running, or the TCON sitting in the PMIC power");
    Serial.println("  sequence waiting on PWR_GOOD. Measure TP21/TP20 right now -- if");
    Serial.println("  they are live, the rails are up and only the handshake is stuck.");
    return false;
  }
  return wait_display(min_ms, 20000);
}

static bool load_pattern() {
  uint16_t w = act_w(), h = act_h();
  Serial.print("  loading pattern ");
  Serial.print(pattern);
  Serial.print(" (");
  Serial.print(pattern_name(pattern));
  Serial.print(") at ");
  Serial.print(w); Serial.print("x"); Serial.print(h);
  Serial.print(", 4 bpp ");
  if (!set_img_base(img_addr)) { Serial.println("LISAR write failed."); return false; }
  if (!ld_img_area(0, 0, w, h)) { Serial.println("LD_IMG_AREA refused."); return false; }
  if (!stream_image(w, h)) return false;
  if (!tcon_cmd(CMD_LD_IMG_END)) { Serial.println("  LD_IMG_END refused."); return false; }
  return true;
}

// A button press can be the first thing that ever happens, so every action
// funnels through here: bring the board up if it is not up, and never skip the
// VCOM interlock -- the register is volatile and resets to -2.50 V (1.20).
static bool ensure_ready() {
  if (!fw_w && !bring_up()) return false;
  if (!vcom_ok()) return false;
  return sys_run();
}

static void do_run() {
  Serial.println();
  Serial.println("=== run: bring up, verify VCOM, draw, refresh ===");
  hrdy_worst = 0; hrdy_waits = 0;
  fw_w = 0;                      // a start is a start: reset and re-read
  if (!ensure_ready()) return;
  // One refresh, not two. ee03_probe's second DPY_AREA is where the TCON
  // wedged (1.21), so the first thing this sketch asks for is the one that
  // matters. `init` then `show` is the two-step version if the glass needs
  // clearing first.
  Serial.println("-- pattern");
  if (!load_pattern()) return;
  Serial.println("-- GC16 (mode 2): 16 grey levels");
  if (!refresh(MODE_GC16, "GC16", 800)) return;
  Serial.println();
  Serial.print("  done. longest HRDY wait this run: ");
  Serial.print(hrdy_worst);
  Serial.print(" ms over ");
  Serial.print(hrdy_waits);
  Serial.println(" waits.");
  Serial.println("  If the glass changed at all, the PMIC ran its power sequence");
  Serial.println("  and the whole chain works. If the log got this far and nothing");
  Serial.println("  moved, measure the rails during the next `show`.");
  Serial.println("  `sleep` drops the panel rails; `pat n` then `show` redraws.");
  Serial.println("  `init` clears the glass if the old image is showing through.");
  rails_held = true;
  rails_since = millis();
  rails_ready(true);
  Serial.println("  Rails are up and stay up (measured 2026-09-09). `drop` ends that.");
}

// ------------------------------------------------------------ rail control

static void emergency_cut(const char *why) {
  digitalWrite(TFT_CS, HIGH);                 // never leave the bus asserted
  pinMode(TFT_ENABLE, OUTPUT);
  digitalWrite(TFT_ENABLE, LOW);              // PWR_EN low: the PMIC loses VIN
  rail_up = false;
  awake = false;
  rails_held = false;
  fw_w = 0;                                   // next power-up is a cold start
  aborted_by_button = true;
  rails_ready(false);
  Serial.println();
  Serial.print("*** EMERGENCY CUT -- ");
  Serial.println(why);
  Serial.println("    PWR_EN is low. Every rail is collapsing at its own RC, which");
  Serial.println("    is why this is the abnormal path. No SPI was used, so it works");
  Serial.println("    even with the TCON wedged. BUTTON1 brings it all back.");
  while (emergency_pressed()) delay(10);      // swallow the press
  delay(BTN_DEBOUNCE_MS);
}

// VCOM again, now that the power sequence has run. PROGRESS.md 1.20 saw
// something rewrite this register to 2500 at boot; if that something also runs
// during power-up, the value checked a moment ago is not the value on the
// glass. One rewrite is allowed, then the rails come down.
static bool vcom_still_right() {
  uint16_t mv;
  if (!vcom_read_stable(&mv)) {
    Serial.println("  post-power VCOM read failed. Treating that as wrong.");
    return forced;
  }
  if (mv == VCOM_MV_TARGET) {
    Serial.print("  VCOM after power-up still ");
    Serial.print(mv);
    Serial.println(" mV -- good.");
    return true;
  }
  Serial.print("  !! VCOM changed to ");
  Serial.print(mv);
  Serial.println(" mV once the rails came up. Rewriting once.");
  if (vcom_write(VCOM_MV_TARGET) && (delay(100), vcom_read_stable(&mv)) && mv == VCOM_MV_TARGET) {
    Serial.println("  rewrite took. Continuing.");
    return true;
  }
  Serial.print("  !! still ");
  Serial.print(mv);
  Serial.println(" mV. Something else owns this register.");
  return forced;
}

// BUTTON1.
static void rails_on() {
  Serial.println();
  Serial.println("[BUTTON1] rails ON");
  aborted_by_button = false;
  hrdy_worst = 0; hrdy_waits = 0;
  fw_w = 0;                                   // always a cold start
  rails_ready(false);

  if (!bring_up())  { Serial.println("  bring-up failed. Rails are not up."); return; }
  if (!vcom_ok())   { Serial.println("  VCOM interlock. Rails are not up."); return; }
  if (!sys_run())   { Serial.println("  SYS_RUN failed. Rails are not up."); return; }

#if RAILS_NEED_REFRESH
  Serial.println("  one INIT refresh -- this is what actually runs the PMIC's");
  Serial.println("  power sequence. No image is streamed.");
  if (!refresh(MODE_INIT, "INIT", 500)) {
    if (!aborted_by_button) {
      Serial.println("  the refresh did not finish, so the rail state is UNKNOWN.");
      Serial.println("  Measure TP21/TP20 before trusting anything, or hit BUTTON3.");
    }
    return;
  }
#endif

  if (!vcom_still_right()) {
    Serial.println("  dropping the rails rather than leaving a wrong VCOM on the panel.");
    if (tcon_cmd(CMD_SLEEP)) awake = false;
    rails_ready(false);
    return;
  }

  rails_held = true;
  rails_since = millis();
  rails_ready(true);
  Serial.println();
  Serial.println("  RAILS UP AND HELD. Nothing here will sleep on its own.");
  Serial.println("  Measure against TP41: TP21 +15  TP20 -15  TP24 VGH  TP23 VGL  TP32 VCOM");
  Serial.println("  Now bring the FPGA up: BTN4 freerun off, BTN0 drive on, BTN1 to step.");
  Serial.println("  BUTTON2 here shuts down in order. BUTTON3 cuts power outright.");
}

// BUTTON2.
static void rails_off() {
  Serial.println();
  Serial.println("[BUTTON2] rails OFF");
  if (!rail_up) { Serial.println("  PWR_EN is already low; nothing is powered."); rails_held = false; rails_ready(false); return; }
  Serial.println("  Drop the FPGA's DRIVE gate first if you have not -- the panel");
  Serial.println("  should stop being scanned before its rails go away.");
  if (tcon_cmd(CMD_SLEEP)) {
    awake = false;
    Serial.println("  SLEEP sent. The TPS65185 runs its own down-sequence, so the");
    Serial.println("  rails fall in order. PWR_EN stays high: the logic rail lives,");
    Serial.println("  which makes the next BUTTON1 quick. BUTTON3 cuts that too.");
  } else {
    Serial.println("  SLEEP was refused -- the TCON is not answering. Falling back");
    Serial.println("  to the blunt path.");
    emergency_cut("SLEEP refused, fell back to PWR_EN");
    return;
  }
  rails_held = false;
  rails_ready(false);
}

static void status() {
  Serial.print("  PWR_EN ");
  Serial.print(rail_up ? "high" : "low");
  Serial.print(", TCON ");
  Serial.print(awake ? "SYS_RUN" : "not woken");
  Serial.print(", rails ");
  if (rails_held) {
    Serial.print("HELD for ");
    Serial.print((millis() - rails_since) / 1000);
    Serial.println(" s");
  } else {
    Serial.println("not held by this sketch");
  }
  Serial.print("  geometry ");
  if (!use_115 && !fw_w) Serial.print("unknown (TCON not read yet)");
  else { Serial.print(act_w()); Serial.print("x"); Serial.print(act_h()); }
  Serial.print(", pattern ");
  Serial.print(pattern);
  Serial.print(mirror ? ", mirrored" : "");
  Serial.println(forced ? ", VCOM interlock LIFTED" : "");
  Serial.println("  \"held\" is an intent, not a measurement: PWR_GOOD has no path to");
  Serial.println("  the XIAO. TP21/TP20 against TP41 is the only truth here.");
}

// ---------------------------------------------------------------- buttons
//
// Short presses only. BUTTON1 and BUTTON2 act on release, the ordinary way.
// BUTTON3 acts the moment it goes down and is also polled from inside the wait
// loops, because waiting until the firmware is idle to honour an emergency stop
// defeats the point of having one.

static const uint8_t btn_pin[3]  = { BTN_ON_PIN, BTN_OFF_PIN, BTN_EMERG_PIN };
static bool          btn_down[3] = { false, false, false };
static unsigned long btn_edge[3] = { 0, 0, 0 };

static void poll_buttons() {
  unsigned long now = millis();
  for (int i = 0; i < 3; i++) {
    bool down = (digitalRead(btn_pin[i]) == LOW);
    if (down == btn_down[i]) continue;
    if (now - btn_edge[i] < BTN_DEBOUNCE_MS) continue;
    btn_down[i] = down;
    btn_edge[i] = now;
    if (i == 2) {                              // emergency: on the way down
      if (down) emergency_cut("BUTTON3");
      continue;
    }
    if (down) continue;                        // the others act on release
    if (i == 0) rails_on();
    else        rails_off();
  }
}

// --------------------------------------------------- panel test (serial only)

static void do_refresh() {
  if (!ensure_ready()) return;
  if (!load_pattern()) return;
  refresh(MODE_GC16, "GC16", 800);
}

// INIT drives every pixel white and ignores the frame buffer, but the buffer is
// loaded white anyway: otherwise the next GC16 resurrects whatever image is
// still sitting in the TCON's memory.
static void do_clear() {
  if (!ensure_ready()) return;
  uint8_t keep = pattern;
  pattern = 0;
  bool ok = load_pattern();
  pattern = keep;
  if (!ok) return;
  refresh(MODE_INIT, "INIT", 500);
}

// ---------------------------------------------------------------- console

static void help() {
  Serial.println("Commands:");
  Serial.println("  info       reset the TCON and report geometry, FW, VCOM, temp");
  Serial.println("  vcom       read VCOM (three agreeing reads)");
  Serial.println("  vcom <mv>  write VCOM in mV, then read it back");
  Serial.println("  temp <c>   set the host-supplied temperature");
  Serial.println("  geo fw     use the TCON's own profile (default)");
  Serial.println("  geo 115    use 2760x2070, the real ED115OC1 geometry");
  Serial.println("  pat <0-5>  choose a pattern");
  Serial.println("  init       full-screen INIT refresh (clear)");
  Serial.println("  show       load the pattern and refresh with GC16");
  Serial.println("  du         load the pattern and refresh with DU (fast, 2 level)");
  Serial.println("  run        the whole sequence, from reset to a picture");
  Serial.println("  on | hold  rails up and held         (same as BUTTON1)");
  Serial.println("  off | drop rails down, in sequence    (same as BUTTON2)");
  Serial.println("  cut        PWR_EN low right now       (same as BUTTON3)");
  Serial.println("  clear      load white and INIT (panel must be in J1)");
  Serial.println("  status     what this sketch believes is powered right now");
  Serial.println("  wake       IT8951 SYS_RUN");
  Serial.println("  mirror on|off  flip the pattern left-to-right");
  Serial.println("  rail on|off  PWR_EN: logic rail + the PMIC's VIN switch");
  Serial.println("  force      lift the VCOM interlock for this session");
  Serial.println();
  Serial.print("Patterns: ");
  for (int i = 0; i <= 5; i++) {
    Serial.print(i); Serial.print("="); Serial.print(pattern_name(i));
    if (i < 5) Serial.print(", ");
  }
  Serial.println();
  Serial.println("Buttons: 1 = rails ON, 2 = rails OFF (sequenced), 3 = EMERGENCY cut.");
  Serial.println("         Short presses. Everything else is on this console.");
  Serial.print("VCOM target ");
  Serial.print(VCOM_MV_TARGET);
  Serial.print(" mV. Geometry now: ");
  if (!use_115 && !fw_w) Serial.print("the TCON's profile, not read yet");
  else { Serial.print(act_w()); Serial.print("x"); Serial.print(act_h());
         Serial.print(use_115 ? " (ED115OC1 override)" : " (TCON profile)"); }
  Serial.println(forced ? ", VCOM interlock LIFTED" : "");
}

void setup() {
  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < 3000);

  for (int i = 0; i < 3; i++) pinMode(btn_pin[i], INPUT);   // external 10K pull-ups
  rails_ready(false);                        // low before anything can be powered

  pinMode(TFT_CS, OUTPUT);
  digitalWrite(TFT_CS, HIGH);
  pinMode(TFT_BUSY, INPUT);
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, LOW);               // hold the TCON in reset until asked
  tconSPI.begin(TFT_SCLK, TFT_MISO, TFT_MOSI, -1);

  Serial.println();
  Serial.println("ee03_panel -- EE03 + IT8951 driving the 11.5\" ED115OC1.");
  Serial.println("The TCON's profile is 1872x1404 and the panel is 2760x2070;");
  Serial.println("that mismatch is accepted here (see the top of this file).");
  Serial.println();
  help();
  Serial.println();
#if RUN_ON_BOOT
  Serial.println("*** RUN_ON_BOOT is set. Starting in 3 s -- send anything to stop.");
  unsigned long t1 = millis();
  while (millis() - t1 < 3000) {
    if (Serial.available()) { while (Serial.available()) Serial.read();
                              Serial.println("    cancelled."); return; }
    delay(10);
  }
  do_run();
#else
  Serial.println("Nothing is powered until you ask. BUTTON1 raises the rails and");
  Serial.println("holds them; BUTTON2 lowers them in order; BUTTON3 cuts PWR_EN.");
  Serial.println("`run` still draws a test image, for when the panel is in J1.");
#endif
}

void loop() {
  poll_buttons();

#if RAILS_TIMEOUT_MIN > 0
  if (rails_held && millis() - rails_since > (unsigned long)RAILS_TIMEOUT_MIN * 60000UL) {
    Serial.println();
    Serial.print("[timeout] rails held for ");
    Serial.print(RAILS_TIMEOUT_MIN);
    Serial.println(" min -- dropping them.");
    rails_off();
  }
#endif

  static String line;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      line.trim();
      if (line.length()) {
        Serial.print("> ");
        Serial.println(line);

        if (line == "help" || line == "?") help();
        else if (line == "info") {
          if (bring_up()) {
            uint16_t mv, t;
            if (vcom_read_stable(&mv)) {
              Serial.print("  VCOM = "); Serial.print(mv);
              Serial.print(" mV (target "); Serial.print(VCOM_MV_TARGET);
              Serial.println(")");
            }
            if (temp_read(&t)) {
              if (t == 0xFFFF) Serial.println("  temperature: not available (0xFFFF)");
              else { Serial.print("  temperature "); Serial.print((int8_t)(t & 0xFF)); Serial.println(" C"); }
            }
          }
        }
        else if (line == "vcom") {
          uint16_t mv;
          if (vcom_read_stable(&mv)) { Serial.print("  VCOM = "); Serial.print(mv); Serial.println(" mV"); }
        }
        else if (line.startsWith("vcom ")) {
          long mv = line.substring(5).toInt();
          if (mv < 0 || mv > 5000) Serial.println("  vcom <mv>: 0..5000");
          else if (vcom_write((uint16_t)mv)) {
            delay(100);
            uint16_t rb;
            if (vcom_read_stable(&rb)) {
              Serial.print("  wrote "); Serial.print(mv);
              Serial.print(", reads "); Serial.print(rb);
              Serial.println(rb == mv ? " -- ok" : " -- MISMATCH");
            }
          }
        }
        else if (line.startsWith("temp ")) {
          long c2 = line.substring(5).toInt();
          if (temp_write((uint16_t)c2)) { Serial.print("  host temperature = "); Serial.println(c2); }
        }
        else if (line == "geo fw")  { use_115 = false; Serial.print("  geometry "); Serial.print(act_w()); Serial.print("x"); Serial.println(act_h()); }
        else if (line == "geo 115") { use_115 = true;  Serial.println("  geometry 2760x2070 -- beyond the TCON's own profile, may be clipped"); }
        else if (line.startsWith("pat ")) {
          long p = line.substring(4).toInt();
          if (p < 0 || p > 5) Serial.println("  pat <0-5>");
          else { pattern = (uint8_t)p; Serial.print("  pattern "); Serial.print(pattern);
                 Serial.print(" = "); Serial.println(pattern_name(pattern)); }
        }
        else if (line == "init") {
          if (fw_w && vcom_ok() && sys_run()) refresh(MODE_INIT, "INIT", 500);
          else if (!fw_w) Serial.println("  run `info` or `run` first.");
        }
        else if (line == "show" || line == "du") {
          bool gc = (line == "show");
          if (!fw_w) Serial.println("  run `info` or `run` first.");
          else if (vcom_ok() && sys_run() && load_pattern())
            refresh(gc ? MODE_GC16 : MODE_DU, gc ? "GC16" : "DU", gc ? 800 : 200);
        }
        else if (line == "run")   do_run();
        else if (line == "sleep" || line == "drop" || line == "off") rails_off();
        else if (line == "hold" || line == "on") rails_on();
        else if (line == "cut")    emergency_cut("`cut` on the console");
        else if (line == "clear")  do_clear();
        else if (line == "status") status();
        else if (line == "wake")  { awake = false; sys_run(); }
        else if (line == "mirror on")  { mirror = true;  Serial.println("  mirrored"); }
        else if (line == "mirror off") { mirror = false; Serial.println("  not mirrored"); }
        else if (line == "rail on")  rail(true);
        else if (line == "rail off") { rail(false); awake = false; rails_held = false; rails_ready(false); }
        else if (line == "force") {
          forced = true;
          Serial.println("  VCOM interlock lifted. Refreshes will now proceed even if");
          Serial.println("  VCOM is not -1.31 V. The board's default is -2.50 V.");
        }
        else Serial.println("  ? try `help`");
        Serial.println();
      }
      line = "";
    } else if (line.length() < 40) {
      line += c;
    }
  }
}
