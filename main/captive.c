#include "captive.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lwip/sockets.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "http_server.h"

static const char *TAG = "captive";
#define AP_IP "192.168.4.1"

// Any unregistered URL (e.g. iOS /hotspot-detect.html) -> 302 to the pad. The
// non-"Success" response makes iOS show the captive sheet and open "/".
static esp_err_t redirect_404(httpd_req_t *req, httpd_err_code_t err) {
    (void)err;
    httpd_resp_set_status(req, "302 Found");
    httpd_resp_set_hdr(req, "Location", "http://" AP_IP "/");
    httpd_resp_send(req, "", 0);
    return ESP_OK;
}

// Minimal DNS server: reply to every A query with the softAP IP.
static void dns_task(void *arg) {
    (void)arg;
    uint8_t buf[512];
    struct sockaddr_in server = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_ANY),
        .sin_port = htons(53),
    };
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) { ESP_LOGE(TAG, "dns socket failed"); vTaskDelete(NULL); return; }
    if (bind(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        ESP_LOGE(TAG, "dns bind failed"); close(sock); vTaskDelete(NULL); return;
    }
    ESP_LOGI(TAG, "captive DNS server listening on :53");

    // Answer record: name pointer to the question (0xC00C), A/IN, TTL 60s, IP.
    const uint8_t answer[16] = {
        0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x3C, 0x00, 0x04, 192, 168, 4, 1,
    };

    while (1) {
        struct sockaddr_in client;
        socklen_t clen = sizeof(client);
        int len = recvfrom(sock, buf, sizeof(buf), 0, (struct sockaddr *)&client, &clen);
        // Need a DNS header (12 bytes) and room to append the answer.
        if (len < 12 || len > (int)(sizeof(buf) - sizeof(answer))) continue;

        buf[2] = 0x81;  // QR=1, RD copied
        buf[3] = 0x80;  // RA=1
        buf[6] = 0x00; buf[7] = 0x01;  // ANCOUNT = 1
        buf[8] = 0x00; buf[9] = 0x00;  // NSCOUNT = 0
        buf[10] = 0x00; buf[11] = 0x00; // ARCOUNT = 0
        memcpy(buf + len, answer, sizeof(answer));
        sendto(sock, buf, len + sizeof(answer), 0, (struct sockaddr *)&client, clen);
    }
}

esp_err_t captive_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) {
        ESP_LOGE(TAG, "http server not started");
        return ESP_FAIL;
    }
    esp_err_t e = httpd_register_err_handler(server, HTTPD_404_NOT_FOUND, redirect_404);
    if (e != ESP_OK) {
        ESP_LOGE(TAG, "register 404 handler: %s", esp_err_to_name(e));
        return e;
    }
    if (xTaskCreate(dns_task, "captive_dns", 4096, NULL, 5, NULL) != pdPASS) {
        ESP_LOGE(TAG, "failed to start DNS task");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "captive portal started");
    return ESP_OK;
}
