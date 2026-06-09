#ifndef WS_CONTROL_H
#define WS_CONTROL_H

#include <stdint.h>
#include "esp_err.h"

// Register the "/ws" WebSocket endpoint on the already-running HTTP server
// (obtained via http_server_get_handle()). Incoming "t,y" text frames are
// parsed and applied via car_drive(). Call after http_server_start().
esp_err_t ws_control_start(void);

// Total valid control frames received since boot (atomic u32 on this single-core target).
uint32_t ws_control_frames(void);

#endif // WS_CONTROL_H
