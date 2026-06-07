#include "ws_control.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_check.h"
#include "http_server.h"
#include "control_proto.h"
#include "car.h"

static const char *TAG = "ws";

static esp_err_t ws_handler(httpd_req_t *req) {
    if (req->method == HTTP_GET) {
        // WebSocket handshake completed; nothing to send back.
        ESP_LOGI(TAG, "ws client connected");
        return ESP_OK;
    }

    // First call with max_len = 0 fills frame.len so we know the payload size.
    httpd_ws_frame_t frame = { .type = HTTPD_WS_TYPE_TEXT };
    esp_err_t ret = httpd_ws_recv_frame(req, &frame, 0);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "recv len failed: %s", esp_err_to_name(ret));
        return ret;
    }
    // The probe overwrites frame.type with the wire opcode. Only act on data
    // frames; CONTINUE / control frames are handled by the framework or ignored.
    if (frame.type != HTTPD_WS_TYPE_TEXT && frame.type != HTTPD_WS_TYPE_BINARY) {
        return ESP_OK;
    }
    if (frame.len == 0 || frame.len > 31) {
        ESP_LOGD(TAG, "ignoring ws frame len=%d", (int)frame.len);
        return ESP_OK;  // ignore empty / oversized frames
    }

    uint8_t buf[32];
    frame.payload = buf;
    ret = httpd_ws_recv_frame(req, &frame, sizeof(buf) - 1);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "recv payload failed: %s", esp_err_to_name(ret));
        return ret;
    }
    buf[frame.len] = '\0';

    float t, y;
    if (control_parse_ty((const char *)buf, &t, &y) == 0) {
        car_drive(t, y);
    } else {
        ESP_LOGW(TAG, "bad ws msg: '%s'", (const char *)buf);
    }
    return ESP_OK;
}

esp_err_t ws_control_start(void) {
    httpd_handle_t server = http_server_get_handle();
    if (server == NULL) {
        ESP_LOGE(TAG, "http server not started");
        return ESP_FAIL;
    }
    httpd_uri_t ws = {
        .uri = "/ws",
        .method = HTTP_GET,
        .handler = ws_handler,
        .is_websocket = true,
    };
    ESP_RETURN_ON_ERROR(httpd_register_uri_handler(server, &ws), TAG, "register /ws");
    ESP_LOGI(TAG, "WebSocket endpoint registered at /ws");
    return ESP_OK;
}
