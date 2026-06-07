#ifndef CAR_H
#define CAR_H

// Initialize the mutex + default calibration table and issue a safety stop.
// Call once after pca9685 is initialized, before any car_drive() call.
void car_init(void);

// Apply a driving intent. throttle and yaw are each clamped to [-1, 1], then
// mixed into side speeds, planned to per-channel PWM, and written to the PCA9685.
// Thread-safe: the I2C write is serialized by an internal mutex, so the console
// task and the WebSocket task may both call it. Last write wins.
void car_drive(float throttle, float yaw);

// Convenience safety stop (equivalent to car_drive(0, 0)).
void car_stop(void);

#endif // CAR_H
