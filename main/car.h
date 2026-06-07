#ifndef CAR_H
#define CAR_H

// Initialize the default calibration table and issue a safety stop.
// Call once after pca9685 is initialized.
void car_init(void);

// Apply a driving intent. throttle and yaw are each clamped to [-1, 1],
// then mixed into side speeds, planned to per-channel PWM, and written to the
// PCA9685. Safe to call from any task once car_init() has run.
void car_drive(float throttle, float yaw);

#endif // CAR_H
