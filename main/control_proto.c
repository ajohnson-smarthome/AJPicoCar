#include "control_proto.h"
#include <string.h>
#include <stdlib.h>
#include <math.h>

// Find a JSON number keyed by `key` (e.g. "\"t\"") and parse the value after the
// colon. Zero-alloc; tolerant of whitespace. Returns 0 on success, -1 otherwise.
static int find_num(const char *msg, const char *key, float *out) {
    const char *p = strstr(msg, key);
    if (p == NULL) return -1;
    p += strlen(key);
    while (*p == ' ' || *p == '\t') p++;   // ws before the colon
    if (*p != ':') return -1;              // a JSON member needs its colon
    p++;
    while (*p == ' ' || *p == '\t') p++;   // ws after the colon
    char *end;
    float v = strtof(p, &end);
    if (end == p || !isfinite(v)) return -1;
    *out = v;
    return 0;
}

int control_parse_json(const char *msg, float *throttle, float *yaw) {
    if (msg == NULL) return -1;
    float t, y;
    if (find_num(msg, "\"t\"", &t) != 0) return -1;
    if (find_num(msg, "\"y\"", &y) != 0) return -1;
    *throttle = t;
    *yaw = y;
    return 0;
}
