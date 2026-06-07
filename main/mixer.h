#ifndef MIXER_H
#define MIXER_H

// Нормализованные скорости бортов, каждая в диапазоне [-1.0, 1.0].
typedef struct {
    float left;
    float right;
} side_speeds_t;

// Смешать throttle и yaw (каждый в [-1, 1]) в скорости левого/правого борта.
// Результат нормализуется с сохранением пропорции: оба значения попадают в [-1, 1].
//   mix(1,0)   -> {1, 1}    прямо
//   mix(0,1)   -> {1,-1}    разворот на месте
//   mix(0.5,0.5)->{1, 0}    дуга
side_speeds_t mixer_mix(float throttle, float yaw);

#endif // MIXER_H
