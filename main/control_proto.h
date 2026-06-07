#ifndef CONTROL_PROTO_H
#define CONTROL_PROTO_H

// Parse a "t,y" control message — two floats separated by a comma — into
// throttle and yaw. Whitespace around the numbers/comma is tolerated; trailing
// garbage after the second number is ignored. Non-finite values (NaN/inf) are
// rejected. Returns 0 on success, -1 on malformed input. Does NOT range-check
// finite values (car_drive clamps them). On failure, *throttle/*yaw are unchanged.
int control_parse_ty(const char *msg, float *throttle, float *yaw);

#endif // CONTROL_PROTO_H
