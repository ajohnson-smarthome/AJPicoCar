#include "http_server.h"
#include "esp_log.h"
#include "esp_check.h"

static const char *TAG = "http";
static httpd_handle_t s_server = NULL;

// Embedded via EMBED_TXTFILES "web/index.html" in CMakeLists (NUL-terminated).
extern const char index_html_start[] asm("_binary_index_html_start");

static esp_err_t root_get_handler(httpd_req_t *req) {
    httpd_resp_set_type(req, "text/html");
    // EMBED_TXTFILES NUL-terminates the data, so HTTPD_RESP_USE_STRLEN sends
    // exactly the file length (excluding the trailing NUL).
    return httpd_resp_send(req, index_html_start, HTTPD_RESP_USE_STRLEN);
}

httpd_handle_t http_server_get_handle(void) {
    return s_server;
}

esp_err_t http_server_start(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.lru_purge_enable = true;
    ESP_RETURN_ON_ERROR(httpd_start(&s_server, &config), TAG, "httpd start");

    httpd_uri_t root = {
        .uri = "/",
        .method = HTTP_GET,
        .handler = root_get_handler,
    };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(s_server, &root), TAG, "register /");

    ESP_LOGI(TAG, "HTTP server started, serving / on the softAP");
    return ESP_OK;
}
