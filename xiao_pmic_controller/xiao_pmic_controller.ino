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
#define PMIC_I2C_ADDR  0x68 // 7-bit I2C address of TPS651851
#define REG_VCOM       0x00 // VCOM Voltage Setting Register
#define REG_ENABLE     0x01 // Power Rails Enable Register
#define REG_UP_SEQ     0x02 // Power-Up Sequencer Register

// Target VCOM: -1.31V (1310 mV)
// Formula: VCOM = - (600 + VCOM_VAL * 10) mV
// For -1.31V: VCOM_VAL = (1310 - 600) / 10 = 71 (0x47)
uint8_t current_vcom_val = 71; 
bool pmic_power_state = false;

// Function Declarations
void pmic_write_reg(uint8_t reg, uint8_t val);
uint8_t pmic_read_reg(uint8_t reg);
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
  digitalWrite(PIN_FPGA_READY, HIGH); // Handshake Ready

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

  // Force PMIC High-Voltage Rails (+15V, -15V, VGH, VGL, VCOM -1.31V)
  pmic_power_up();

  Serial.println("\nEnter command ('help' for list of commands):");
  Serial.print("> ");
}

void loop() {
  handle_serial_cli();

  // Continuously maintain Power Gates ACTIVE
  digitalWrite(PIN_PWR_SW, LOW);   // P-MOSFET ON
  digitalWrite(PIN_PWR_EN, HIGH);  // Load Switch ON
  digitalWrite(PIN_FPGA_READY, HIGH); // Handshake HIGH

  // Keep sending PMIC rail enable packet every 2 seconds
  static unsigned long last_keepalive = 0;
  if (millis() - last_keepalive > 2000) {
    if (pmic_power_state) {
      pmic_write_reg(REG_ENABLE, 0x3F);
      pmic_write_reg(REG_UP_SEQ, 0x80);
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

// Power-up sequence for TPS651851 PMIC
void pmic_power_up() {
  Serial.println("\n[PMIC] Initiating EE03 Power-Up Sequence...");

  // 1. Ensure Power Gates are OPEN
  digitalWrite(PIN_PWR_SW, LOW);
  digitalWrite(PIN_PWR_EN, HIGH);
  delay(20);

  // 2. Set Target VCOM (-1.31V -> Reg 0x00 = 71 / 0x47)
  Serial.print("[PMIC] Setting VCOM Register (0x00) to 71 (-1.31V)...");
  pmic_write_reg(REG_VCOM, current_vcom_val);
  delay(10);

  // 3. Enable All Power Rails (VPOS +15V, VNEG -15V, VGH, VGL, VCOM) -> Reg 0x01 = 0x3F
  Serial.println("[PMIC] Enabling Power Rails (REG 0x01 = 0x3F)...");
  pmic_write_reg(REG_ENABLE, 0x3F);
  delay(10);

  // 4. Trigger Power-Up Sequencer -> Reg 0x02 = 0x80
  Serial.println("[PMIC] Triggering Power-Up Sequencer (REG 0x02 = 0x80)...");
  pmic_write_reg(REG_UP_SEQ, 0x80);
  delay(50);

  // 5. Notify FPGA
  digitalWrite(PIN_FPGA_READY, HIGH);
  pmic_power_state = true;
  Serial.println("[STATUS] PMIC High-Voltage Rails (+15V, -15V, VGH, VGL, VCOM -1.31V) ACTIVATED!");
}

void pmic_power_down() {
  Serial.println("\n[PMIC] Initiating Power-Down Sequence...");
  digitalWrite(PIN_FPGA_READY, LOW);
  pmic_write_reg(REG_ENABLE, 0x00);
  pmic_power_state = false;
  Serial.println("[STATUS] PMIC High-Voltage Rails Disables.");
}

void print_status() {
  Serial.println("\n--- EE03 PMIC Status & Handshake Pins ---");
  Serial.print("PMIC Power State   : ");
  Serial.println(pmic_power_state ? "ON (HIGH VOLTAGES ACTIVE)" : "OFF");

  float vcom_volts = -((float)(600 + current_vcom_val * 10) / 1000.0f);
  Serial.print("Target VCOM Voltage: ");
  Serial.print(vcom_volts, 2);
  Serial.println(" V");

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
      Serial.println("\nCommands: 'on', 'off', 'status', 'vcom 1.31'");
    } else if (input.equalsIgnoreCase("on")) {
      pmic_power_up();
    } else if (input.equalsIgnoreCase("off")) {
      pmic_power_down();
    } else if (input.equalsIgnoreCase("status")) {
      print_status();
    } else if (input.startsWith("vcom ")) {
      float val = input.substring(5).toFloat();
      if (val < 0) val = -val;
      current_vcom_val = (uint8_t)((val * 1000.0f - 600.0f) / 10.0f);
      pmic_power_up();
    }
  }
}

