#ifndef WS_CONTROL_H
#define WS_CONTROL_H

#include "esp_err.h"

// Register the "/ws" WebSocket endpoint on the already-running HTTP server
// (obtained via http_server_get_handle()). Incoming "t,y" text frames are
// parsed and applied via car_drive(). Call after http_server_start().
esp_err_t ws_control_start(void);

#endif // WS_CONTROL_H
