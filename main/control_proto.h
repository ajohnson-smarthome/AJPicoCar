#ifndef CONTROL_PROTO_H
#define CONTROL_PROTO_H

// Parse a "t,y" control message — two floats separated by a comma — into
// throttle and yaw. Whitespace around the numbers/comma is tolerated.
// Returns 0 on success, -1 on malformed input. Does NOT range-check the values
// (car_drive clamps them). On failure, *throttle/*yaw are left unchanged.
int control_parse_ty(const char *msg, float *throttle, float *yaw);

#endif // CONTROL_PROTO_H
