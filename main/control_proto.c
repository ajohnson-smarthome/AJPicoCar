#include "control_proto.h"
#include <stdio.h>

int control_parse_ty(const char *msg, float *throttle, float *yaw) {
    if (msg == NULL) return -1;
    float t, y;
    // "%f , %f" — leading spaces in the format skip whitespace; the comma must
    // match literally. sscanf returns the count of successfully parsed fields.
    if (sscanf(msg, " %f , %f", &t, &y) != 2) return -1;
    *throttle = t;
    *yaw = y;
    return 0;
}
