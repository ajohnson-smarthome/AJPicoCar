#ifndef CAPTIVE_H
#define CAPTIVE_H

#include "esp_err.h"

// Start the captive portal: a DNS server that resolves every name to the softAP
// IP (192.168.4.1), plus a 404 redirect on the HTTP server so a phone's
// captive-network check lands on "/". Makes iOS auto-open the control page when
// it joins the AP. Call after http_server_start() and wifi_ap_start().
esp_err_t captive_start(void);

#endif // CAPTIVE_H
