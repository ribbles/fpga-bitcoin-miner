#include <Arduino.h>
#include "driver/pcnt.h"
#include "esp_timer.h"

// Connect the FPGA square-wave output to this ESP32 pin and connect grounds.
// The FPGA signal must be 3.3 V or lower; ESP32 GPIO pins are not 5 V tolerant.
static constexpr gpio_num_t SIGNAL_PIN = GPIO_NUM_27;

static constexpr uint32_t GATE_TIME_MS = 10000UL;
static constexpr int16_t COUNTER_HIGH_LIMIT = 30000;
static constexpr pcnt_unit_t PCNT_UNIT_USED = PCNT_UNIT_0;
static volatile uint64_t overflowPulses = 0;

static void IRAM_ATTR onCounterLimit(void *argument) {
  uint32_t eventStatus = 0;
  pcnt_get_event_status(PCNT_UNIT_USED, &eventStatus);
  if (eventStatus & PCNT_EVT_H_LIM) {
    overflowPulses += COUNTER_HIGH_LIMIT;
  }
}

static void configurePulseCounter() {
  pcnt_config_t config = {};
  config.pulse_gpio_num = SIGNAL_PIN;
  config.ctrl_gpio_num = PCNT_PIN_NOT_USED;
  config.unit = PCNT_UNIT_USED;
  config.channel = PCNT_CHANNEL_0;
  config.pos_mode = PCNT_COUNT_INC;
  config.neg_mode = PCNT_COUNT_DIS;
  config.lctrl_mode = PCNT_MODE_KEEP;
  config.hctrl_mode = PCNT_MODE_KEEP;
  config.counter_h_lim = COUNTER_HIGH_LIMIT;
  config.counter_l_lim = 0;

  pcnt_unit_config(&config);
  // Reject glitches shorter than 10 APB clock cycles (125 ns at 80 MHz)
  // while allowing the expected 1 us period through the counter.
  pcnt_set_filter_value(PCNT_UNIT_USED, 10);
  pcnt_filter_enable(PCNT_UNIT_USED);
  pcnt_event_enable(PCNT_UNIT_USED, PCNT_EVT_H_LIM);
  pcnt_isr_service_install(0);
  pcnt_isr_handler_add(PCNT_UNIT_USED, onCounterLimit, nullptr);
  pcnt_counter_pause(PCNT_UNIT_USED);
  pcnt_counter_clear(PCNT_UNIT_USED);
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  configurePulseCounter();
  Serial.println("FPGA frequency counter ready");
}

void loop() {
  int16_t pulseCount = 0;

  overflowPulses = 0;
  pcnt_counter_clear(PCNT_UNIT_USED);
  const int64_t startUs = esp_timer_get_time();
  pcnt_counter_resume(PCNT_UNIT_USED);
  delay(GATE_TIME_MS);
  pcnt_counter_pause(PCNT_UNIT_USED);
  const int64_t elapsedUs = esp_timer_get_time() - startUs;
  delay(1);
  pcnt_get_counter_value(PCNT_UNIT_USED, &pulseCount);

  const uint64_t totalPulses = overflowPulses + static_cast<uint16_t>(pulseCount);
  const double dividedHz =
      static_cast<double>(totalPulses) * 1000000.0 / static_cast<double>(elapsedUs);
  Serial.printf("%.6f Hz\n", dividedHz);
  delay(500);
}
