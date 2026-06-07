#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include "esp_err.h"

// Start the embedded HTTP server. Serves the embedded index.html at GET "/".
esp_err_t http_server_start(void);

#endif // HTTP_SERVER_H
