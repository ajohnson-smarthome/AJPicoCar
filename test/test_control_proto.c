#include "control_proto.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int approx(float a, float b) { return fabsf(a - b) < 1e-4f; }

static void ok(const char *msg, float et, float ey) {
    float t = 999.0f, y = 999.0f;
    int r = control_parse_ty(msg, &t, &y);
    if (r != 0 || !approx(t, et) || !approx(y, ey)) {
        printf("FAIL ok('%s') -> r=%d t=%.4f y=%.4f (want t=%.4f y=%.4f)\n",
               msg, r, t, y, et, ey);
        assert(0);
    }
}

static void bad(const char *msg) {
    float t = 7.0f, y = 7.0f;
    int r = control_parse_ty(msg, &t, &y);
    if (r != -1 || t != 7.0f || y != 7.0f) {  // unchanged on failure
        printf("FAIL bad('%s') -> r=%d t=%.4f y=%.4f (want r=-1, unchanged)\n",
               msg ? msg : "(null)", r, t, y);
        assert(0);
    }
}

int main(void) {
    ok("0.5,0", 0.5f, 0.0f);
    ok("0,1", 0.0f, 1.0f);
    ok("-1,-0.5", -1.0f, -0.5f);
    ok("1.0,-1.0", 1.0f, -1.0f);
    ok(" 0.25 , 0.75 ", 0.25f, 0.75f);   // whitespace tolerated

    bad("abc");
    bad("0.5");        // missing comma + second value
    bad("0.5,");       // missing second value
    bad(",0.5");       // missing first value
    bad("");
    bad(NULL);

    printf("test_control_proto: all passed\n");
    return 0;
}
