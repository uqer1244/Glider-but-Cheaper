#include <Wire.h>

// =============================================================================
// Pin Configurations (Modify these to match your actual hardware wiring)
// =============================================================================
#define PIN_PMIC_WAKEUP   2   // XIAO D2 -> PMIC WAKEUP
#define PIN_PMIC_PWRUP    3   // XIAO D3 -> PMIC PWRUP

#define PIN_FPGA_READY    1   // XIAO D1 -> FPGA PMIC_READY (Input to FPGA Pin A14)
#define PIN_FPGA_DONE     0   // XIAO D0 <- FPGA REFRESH_DONE (Output from FPGA Pin B13)

// =============================================================================
// TPS65185 PMIC Register definitions
// =============================================================================
#define PMIC_I2C_ADDR     0x68  // 7-bit I2C address of TPS65185
#define REG_ENABLE        0x02  // Enable Register
#define REG_VADJ          0x03  // VCOM Adjustment Register

// Default VCOM setting: -1.50V (VADJ = 20 / 0x14)
// Formula: VCOM = -0.5V - (VADJ * 0.05V)
// For -1.50V: VADJ = (-1.50V + 0.5V) / -0.05V = 20 (0x14)
// For -2.00V: VADJ = (-2.00V + 0.5V) / -0.05V = 30 (0x1E)
uint8_t current_vadj = 0x14; 
bool pmic_power_state = false;

// =============================================================================
// Function Declarations
// =============================================================================
void pmic_write_reg(uint8_t reg, uint8_t val);
uint8_t pmic_read_reg(uint8_t reg);
void pmic_power_up();
void pmic_power_down();
void print_status();
void handle_serial_cli();

void setup()
{
    Serial.begin(115200);
    
    // Configure Handshake and Control Pins
    pinMode(PIN_PMIC_WAKEUP, OUTPUT);
    pinMode(PIN_PMIC_PWRUP, OUTPUT);
    pinMode(PIN_FPGA_READY, OUTPUT);
    pinMode(PIN_FPGA_DONE, INPUT); // Standard input

    // Keep outputs safe at boot
    digitalWrite(PIN_PMIC_WAKEUP, LOW);
    digitalWrite(PIN_PMIC_PWRUP, LOW);
    digitalWrite(PIN_FPGA_READY, LOW);

    // Initialize I2C (Standard 100 kHz)
    Wire.begin();
    Wire.setClock(100000);

    // Wait for Serial Monitor (max 3 seconds)
    unsigned long start = millis();
    while (!Serial && (millis() - start < 3000));

    Serial.println("\n==================================================");
    Serial.println("XIAO ESP32S3 - E-Ink PMIC Handshake Controller");
    Serial.println("==================================================");
    Serial.println("Initializing PMIC...");
    
    // Automatically power up E-ink rails on boot
    pmic_power_up();

    Serial.println("\nEnter command ('help' for list of commands):");
    Serial.print("> ");
}

void loop()
{
    handle_serial_cli();

    // Monitor FPGA refresh state
    static bool last_done = HIGH;
    bool current_done = digitalRead(PIN_FPGA_DONE);

    if (current_done != last_done) {
        if (current_done == LOW) {
            Serial.println("[FPGA] Screen refresh cycle STARTED (REFRESH_DONE -> LOW)");
        } else {
            Serial.println("[FPGA] Screen refresh cycle COMPLETED (REFRESH_DONE -> HIGH)");
        }
        last_done = current_done;
    }

    delay(10);
}

// Write to TPS65185 register over I2C
void pmic_write_reg(uint8_t reg, uint8_t val)
{
    Wire.beginTransmission(PMIC_I2C_ADDR);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
}

// Read from TPS65185 register over I2C
uint8_t pmic_read_reg(uint8_t reg)
{
    Wire.beginTransmission(PMIC_I2C_ADDR);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(PMIC_I2C_ADDR, 1);
    return Wire.available() ? Wire.read() : 0xFF;
}

// Power-up sequence for TPS65185
void pmic_power_up()
{
    Serial.println("\n[PMIC] Initiating power-up sequence...");

    // 1. Hold WAKEUP low for 5ms
    digitalWrite(PIN_PMIC_WAKEUP, LOW);
    digitalWrite(PIN_PMIC_PWRUP, LOW);
    digitalWrite(PIN_FPGA_READY, LOW);
    delay(10);

    // 2. Drive WAKEUP high and wait 10ms for PMIC standby state
    digitalWrite(PIN_PMIC_WAKEUP, HIGH);
    delay(15);

    // 3. Write VADJ to set VCOM
    Serial.print("[PMIC] Setting VADJ register (0x03) to 0x");
    Serial.println(current_vadj, HEX);
    pmic_write_reg(REG_VADJ, current_vadj);
    delay(2);

    // 4. Write ENABLE (0x80) to turn on VCOM buffer
    Serial.println("[PMIC] Enabling VCOM Buffer (REG 0x02 = 0x80)");
    pmic_write_reg(REG_ENABLE, 0x80);
    delay(5);

    // Verify VCOM write
    uint8_t read_val = pmic_read_reg(REG_VADJ);
    if (read_val == current_vadj) {
        Serial.println("[PMIC] I2C verification SUCCESSFUL.");
    } else {
        Serial.print("[PMIC] WARNING: I2C readback mismatch (Read: 0x");
        Serial.print(read_val, HEX);
        Serial.print(", Expected: 0x");
        Serial.print(current_vadj, HEX);
        Serial.println("). Connection issue?");
    }

    // 5. Drive PWRUP high to turn on boost converters (+/-15V, VGH/VGL)
    Serial.println("[PMIC] Driving PWRUP -> HIGH (Enabling high voltage rails)");
    digitalWrite(PIN_PMIC_PWRUP, HIGH);
    
    // Wait for PMIC voltages to stabilize
    delay(50);

    // 6. Notify FPGA that PMIC is stable and ready to refresh
    Serial.println("[HANDSHAKE] PMIC is ready. Driving PMIC_READY -> HIGH");
    digitalWrite(PIN_FPGA_READY, HIGH);

    pmic_power_state = true;
    Serial.println("[PMIC] Power-up sequence completed.");
}

// Power-down sequence
void pmic_power_down()
{
    Serial.println("\n[PMIC] Initiating power-down sequence...");

    // 1. Notify FPGA we are powering down (FPGA must stop driving EPD signals immediately)
    Serial.println("[HANDSHAKE] Powering down. Driving PMIC_READY -> LOW");
    digitalWrite(PIN_FPGA_READY, LOW);
    delay(10);

    // 2. Shut off boost converters
    Serial.println("[PMIC] Driving PWRUP -> LOW (Disabling high voltage rails)");
    digitalWrite(PIN_PMIC_PWRUP, LOW);
    delay(20); // wait for discharge

    // 3. Put PMIC to sleep
    Serial.println("[PMIC] Driving WAKEUP -> LOW (Entering Sleep mode)");
    digitalWrite(PIN_PMIC_WAKEUP, LOW);

    pmic_power_state = false;
    Serial.println("[PMIC] Power-down completed.");
}

void print_status()
{
    Serial.println("\n--- System Status & Handshake Pins ---");
    Serial.print("PMIC Power State   : ");
    Serial.println(pmic_power_state ? "ON (HIGH VOLTAGES ACTIVE)" : "OFF (SLEEP)");
    
    float vcom_val = -0.5f - ((float)current_vadj * 0.05f);
    Serial.print("Target VCOM Voltage: ");
    Serial.print(vcom_val, 2);
    Serial.print(" V (VADJ: 0x");
    Serial.print(current_vadj, HEX);
    Serial.println(")");

    Serial.print("Output (XIAO -> FPGA) PMIC_READY : ");
    Serial.println(digitalRead(PIN_FPGA_READY) ? "HIGH (Ready)" : "LOW (Not Ready)");

    Serial.print("Input  (FPGA -> XIAO) REFRESH_DONE: ");
    Serial.println(digitalRead(PIN_FPGA_DONE) ? "HIGH (EPD Idle)" : "LOW (EPD Refreshing)");
    Serial.println("--------------------------------------");
}

void handle_serial_cli()
{
    if (Serial.available() > 0) {
        String input = Serial.readStringUntil('\n');
        input.trim();
        
        if (input.length() == 0) {
            Serial.print("\n> ");
            return;
        }

        Serial.println(input); // echo command

        if (input.equalsIgnoreCase("help")) {
            Serial.println("\nAvailable Commands:");
            Serial.println("  on            - Trigger PMIC Power-up sequence");
            Serial.println("  off           - Trigger PMIC Power-down sequence");
            Serial.println("  status        - Print current PMIC/Handshake pin status");
            Serial.println("  vcom <value>  - Set target VCOM. Options: '1.5' or '2.0'");
            Serial.println("  help          - Print this help message");
        } 
        else if (input.equalsIgnoreCase("on")) {
            if (pmic_power_state) {
                Serial.println("PMIC is already powered up!");
            } else {
                pmic_power_up();
            }
        } 
        else if (input.equalsIgnoreCase("off")) {
            if (!pmic_power_state) {
                Serial.println("PMIC is already powered down!");
            } else {
                pmic_power_down();
            }
        } 
        else if (input.equalsIgnoreCase("status")) {
            print_status();
        } 
        else if (input.startsWith("vcom ")) {
            String valStr = input.substring(5);
            valStr.trim();
            if (valStr == "1.5" || valStr == "1.50" || valStr == "-1.5") {
                current_vadj = 0x14; // -1.50V
                Serial.println("Target VCOM set to -1.50V (requires power cycle/re-on to apply).");
            } 
            else if (valStr == "2.0" || valStr == "2.00" || valStr == "-2.0") {
                current_vadj = 0x1E; // -2.00V
                Serial.println("Target VCOM set to -2.00V (requires power cycle/re-on to apply).");
            } 
            else {
                Serial.println("Invalid VCOM value! Choose '1.5' (for -1.50V) or '2.0' (for -2.00V).");
            }
        } 
        else {
            Serial.print("Unknown command: ");
            Serial.println(input);
        }
        
        Serial.print("\n> ");
    }
}
