#include <Wire.h>

// =============================================================================
// EE03 V1.0 Board Pin Configurations (Schematic Pages 4, 5, 6)
// =============================================================================
#define PIN_PWR_SW     6   // XIAO D5 / GPIO 6 -> P-MOSFET Gate (Must be LOW to enable PMIC 5V/VSYS main power)
#define PIN_PWR_EN     43  // XIAO D6 / GPIO 43 -> TPS22916 Load Switch (Must be HIGH to enable 3.3V/5V rails)
#define PIN_TFT_RST    38  // XIAO D11 / GPIO 38 -> IT8951 Reset

#define PIN_FPGA_READY 1   // XIAO D1 -> FPGA PMIC_READY Handshake (Pin N7 on FPGA)
#define PIN_FPGA_DONE  2   // XIAO D2 <- FPGA REFRESH_DONE (Pin N9 on FPGA)

// =============================================================================
// TPS651851 PMIC Register Definitions
// =============================================================================
// Register map taken from epdiy's driver for the same part, which is in this
// repo at epdiy-main/src/board/tps65185.h. The map used here before was wrong
// in a way that silently did nothing and silently did harm:
//
//   old REG_VCOM   0x00  is TMST_VALUE, read only -> VCOM was never set at all
//   old REG_UP_SEQ 0x02  is VADJ, the VPOS/VNEG magnitude -> writing 0x80 to it
//                        changed the rail voltages as a side effect
//
// epdiy never writes VADJ; it leaves the default. Do the same. The real
// power-up sequencer is at 0x09/0x0A and is not touched either.
#define PMIC_I2C_ADDR  0x68 // 7-bit I2C address of TPS651851
#define REG_TMST_VALUE 0x00 // read only, on-chip temperature
#define REG_ENABLE     0x01 // power rails enable
#define REG_VADJ       0x02 // VPOS/VNEG magnitude -- do not write, default is right
#define REG_VCOM1      0x03 // VCOM[7:0]
#define REG_VCOM2      0x04 // VCOM[8]
#define REG_PG         0x0F // power good, per rail
#define REG_REVID      0x10

// Rails good. epdiy waits for exactly this before driving anything.
#define PG_MASK        0xFA

// VCOM for this panel is -1.31 V. That is not a guess: it is printed on the
// panel itself. Confirmed 2026-08-24.
//
// The TPS65185 takes it as a positive magnitude in units of 10 mV, split
// across two registers:  val = mV / 10;  VCOM2 = val >> 8;  VCOM1 = val & 0xFF.
// So -1.31 V is val = 131 -> VCOM2 = 0x00, VCOM1 = 0x83.
//
// The old code used VCOM = -(600 + val*10) mV and val = 71, which even at the
// right register would have asked for -1.31 V by a formula the part does not
// use. Two independent errors pointing at the same wrong result.
uint16_t current_vcom_mv = 1310;
bool pmic_power_state = false;
bool pmic_rails_good = false;

// Function Declarations
void pmic_write_reg(uint8_t reg, uint8_t val);
uint8_t pmic_read_reg(uint8_t reg);
void pmic_set_vcom(uint16_t vcom_mv);
bool pmic_wait_power_good(unsigned long timeout_ms);
void i2c_scan();
void pmic_power_up();
void pmic_power_down();
void print_status();
void handle_serial_cli();

void setup() {
  Serial.begin(115200);

  // Configure EE03 Hardware Gate Control Pins
  pinMode(PIN_PWR_SW, OUTPUT);
  pinMode(PIN_PWR_EN, OUTPUT);
  pinMode(PIN_TFT_RST, OUTPUT);
  pinMode(PIN_FPGA_READY, OUTPUT);
  pinMode(PIN_FPGA_DONE, INPUT);

  // Safe Boot Defaults
  digitalWrite(PIN_PWR_SW, LOW);   // Turn ON P-MOSFET (GND Gate)
  digitalWrite(PIN_PWR_EN, HIGH);  // Turn ON Load Switch (3.3V Enable)
  // Not ready until the PMIC says the rails are actually up. The old code
  // raised this in setup() before talking to the PMIC at all, so the signal
  // carried no information -- which is why the FPGA side stopped using it.
  digitalWrite(PIN_FPGA_READY, LOW);

  // Reset IT8951 TCON
  digitalWrite(PIN_TFT_RST, LOW);
  delay(100);
  digitalWrite(PIN_TFT_RST, HIGH);
  delay(150);

  // Initialize Wire I2C
  Wire.begin();
  Wire.setClock(100000);

  unsigned long start = millis();
  while (!Serial && (millis() - start < 3000));

  Serial.println("\n==================================================");
  Serial.println("EE03 V1.0 TPS651851 PMIC & Handshake Controller");
  Serial.println("==================================================");
  Serial.println("Initiating PMIC Power-Up Sequence...");

  // Scan first. If the PMIC does not answer, nothing below can work and it is
  // better to see that immediately than to watch a power-up sequence that is
  // talking to no one.
  i2c_scan();

  pmic_power_up();

  Serial.println("\nEnter command ('help' for list of commands):");
  Serial.print("> ");
}

void loop() {
  handle_serial_cli();

  // Continuously maintain Power Gates ACTIVE
  digitalWrite(PIN_PWR_SW, LOW);   // P-MOSFET ON
  digitalWrite(PIN_PWR_EN, HIGH);  // Load Switch ON
  digitalWrite(PIN_FPGA_READY, pmic_rails_good ? HIGH : LOW);

  // Re-assert the rail enable periodically, and re-read power good so a rail
  // that drops out is noticed. The old keepalive also rewrote 0x02 every two
  // seconds, which meant it was rewriting VADJ every two seconds.
  static unsigned long last_keepalive = 0;
  if (millis() - last_keepalive > 2000) {
    if (pmic_power_state) {
      pmic_write_reg(REG_ENABLE, 0x3F);
      uint8_t pg = pmic_read_reg(REG_PG);
      pmic_rails_good = ((pg & PG_MASK) == PG_MASK);
    }
    last_keepalive = millis();
  }

  delay(10);
}

// Write to TPS651851 register over I2C
void pmic_write_reg(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(PMIC_I2C_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

// Read from TPS651851 register over I2C
uint8_t pmic_read_reg(uint8_t reg) {
  Wire.beginTransmission(PMIC_I2C_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(PMIC_I2C_ADDR, 1);
  return Wire.available() ? Wire.read() : 0xFF;
}

// Walks the bus and prints whatever answers.
//
// This matters more than it looks. The EE03 schematic has two separate I2C
// buses: the XIAO's own (GPIO41 SCL / GPIO42 SDA), which carries only the
// SHT40 temperature sensor at 0x44, and a second bus named ITE_I2C_SCL/SDA
// that the IT8951 masters. The TPS651851's SCL/SDA are on the second one
// (schematic sheet 6, pins 17/18), not on the XIAO's.
//
// If that reading is right, every I2C write this sketch has ever made to the
// PMIC went nowhere, and no amount of fixing register addresses can change
// VCOM. The scan settles it: 0x44 present and 0x68 absent means the PMIC is
// unreachable from here, and TP2/TP3 have to be wired to the XIAO before any
// of this code can do anything.
void i2c_scan() {
  Serial.println("\n--- I2C scan ---");
  int found = 0;
  for (uint8_t addr = 0x08; addr < 0x78; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.print("  0x");
      Serial.print(addr, HEX);
      if (addr == 0x44) Serial.print("  SHT40 temperature/humidity");
      if (addr == PMIC_I2C_ADDR) Serial.print("  TPS651851 PMIC");
      Serial.println();
      found++;
    }
  }
  if (found == 0) Serial.println("  nothing responded");

  Wire.beginTransmission(PMIC_I2C_ADDR);
  bool pmic_here = (Wire.endTransmission() == 0);
  Serial.print("PMIC at 0x68: ");
  Serial.println(pmic_here ? "REACHABLE"
                           : "NOT REACHABLE -- see comment above i2c_scan()");
  Serial.println("----------------");
}

// VCOM is a positive magnitude in units of 10 mV, split over two registers.
// Order matters: write the high bit first, then the low byte, the same way
// epdiy does it.
void pmic_set_vcom(uint16_t vcom_mv) {
  uint16_t val = vcom_mv / 10;
  Serial.print("[PMIC] VCOM = -");
  Serial.print(vcom_mv / 1000.0f, 2);
  Serial.print(" V -> VCOM2(0x04)=0x");
  Serial.print((val >> 8) & 0x01, HEX);
  Serial.print(" VCOM1(0x03)=0x");
  Serial.println(val & 0xFF, HEX);
  pmic_write_reg(REG_VCOM2, (val >> 8) & 0x01);
  pmic_write_reg(REG_VCOM1, val & 0xFF);
}

// Poll the power good register the way epdiy does, but with a timeout: a
// blocking wait here would hang the whole controller on a hardware fault.
bool pmic_wait_power_good(unsigned long timeout_ms) {
  unsigned long start = millis();
  while (millis() - start < timeout_ms) {
    uint8_t pg = pmic_read_reg(REG_PG);
    if ((pg & PG_MASK) == PG_MASK) {
      pmic_rails_good = true;
      return true;
    }
    delay(5);
  }
  pmic_rails_good = false;
  return false;
}

// Power-up sequence for TPS651851 PMIC
void pmic_power_up() {
  Serial.println("\n[PMIC] Initiating EE03 Power-Up Sequence...");

  // 1. Ensure Power Gates are OPEN
  digitalWrite(PIN_PWR_SW, LOW);
  digitalWrite(PIN_PWR_EN, HIGH);
  delay(20);

  // 2. Report who we are talking to. A wrong or absent part reads 0xFF here,
  //    which is worth knowing before enabling anything.
  Serial.print("[PMIC] REVID = 0x");
  Serial.println(pmic_read_reg(REG_REVID), HEX);

  // 3. Set VCOM before the rails come up.
  pmic_set_vcom(current_vcom_mv);
  delay(10);

  // 4. Enable the rails.
  Serial.println("[PMIC] Enabling power rails (ENABLE 0x01 = 0x3F)...");
  pmic_write_reg(REG_ENABLE, 0x3F);
  pmic_power_state = true;

  // 5. Wait for the PMIC to say the rails are up, and only then tell the FPGA.
  //    VADJ (0x02) is deliberately not written: the default is correct and the
  //    old code was corrupting it.
  if (pmic_wait_power_good(500)) {
    digitalWrite(PIN_FPGA_READY, HIGH);
    Serial.println("[STATUS] Rails up and power good. VCOM/VPOS/VNEG/VGH/VGL active.");
  }
  else {
    digitalWrite(PIN_FPGA_READY, LOW);
    Serial.print("[FAIL] Power good never asserted. PG = 0x");
    Serial.println(pmic_read_reg(REG_PG), HEX);
    Serial.println("[FAIL] Rails may be partially up. Measure before connecting a panel.");
  }
}

void pmic_power_down() {
  Serial.println("\n[PMIC] Initiating Power-Down Sequence...");
  digitalWrite(PIN_FPGA_READY, LOW);
  pmic_write_reg(REG_ENABLE, 0x00);
  pmic_power_state = false;
  pmic_rails_good = false;
  Serial.println("[STATUS] PMIC High-Voltage Rails Disables.");
}

void print_status() {
  Serial.println("\n--- EE03 PMIC Status & Handshake Pins ---");
  Serial.print("PMIC Power State   : ");
  Serial.println(pmic_power_state ? "ON (HIGH VOLTAGES ACTIVE)" : "OFF");

  Serial.print("Target VCOM Voltage: -");
  Serial.print(current_vcom_mv / 1000.0f, 2);
  Serial.print(" V  (VCOM1=0x");
  Serial.print((current_vcom_mv / 10) & 0xFF, HEX);
  Serial.print(" VCOM2=0x");
  Serial.print(((current_vcom_mv / 10) >> 8) & 0x01, HEX);
  Serial.println(")");

  uint8_t pg = pmic_read_reg(REG_PG);
  Serial.print("Power Good (0x0F)  : 0x");
  Serial.print(pg, HEX);
  Serial.println(((pg & PG_MASK) == PG_MASK) ? "  ALL RAILS GOOD" : "  NOT GOOD");

  Serial.print("Die Temperature    : ");
  Serial.print((int8_t)pmic_read_reg(REG_TMST_VALUE));
  Serial.println(" C");

  Serial.print("P-MOSFET Gate (GPIO 6) : ");
  Serial.println(digitalRead(PIN_PWR_SW) ? "HIGH (OFF)" : "LOW (ON)");

  Serial.print("Load Switch   (GPIO 43): ");
  Serial.println(digitalRead(PIN_PWR_EN) ? "HIGH (ON)" : "LOW (OFF)");

  Serial.print("PMIC_READY Handshake   : ");
  Serial.println(digitalRead(PIN_FPGA_READY) ? "HIGH (Ready)" : "LOW (Not Ready)");
  Serial.println("------------------------------------------");
}

void handle_serial_cli() {
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    if (input.length() == 0) return;

    if (input.equalsIgnoreCase("help")) {
      Serial.println("\nCommands: 'on', 'off', 'status', 'scan', 'vcom 1.31' (magnitude in volts)");
    } else if (input.equalsIgnoreCase("on")) {
      pmic_power_up();
    } else if (input.equalsIgnoreCase("off")) {
      pmic_power_down();
    } else if (input.equalsIgnoreCase("status")) {
      print_status();
    } else if (input.equalsIgnoreCase("scan")) {
      i2c_scan();
    } else if (input.startsWith("vcom ")) {
      float val = input.substring(5).toFloat();
      if (val < 0) val = -val;
      uint16_t mv = (uint16_t)(val * 1000.0f + 0.5f);
      // The part holds VCOM in 9 bits of 10 mV, so 5.11 V is the ceiling.
      if (mv > 5110) {
        Serial.println("[CLI] Out of range: VCOM magnitude must be <= 5.11 V");
      }
      else {
        current_vcom_mv = mv;
        pmic_set_vcom(current_vcom_mv);
      }
    }
  }
}

