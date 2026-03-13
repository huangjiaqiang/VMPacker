/**
 * libvmptest.c — VMPacker shared-library test target
 *
 * Every exported function is pure computation: no libc calls, no PLT,
 * no global/TLS data.  This lets us verify the basic ET_DYN protection
 * pipeline (PT_NOTE hijack, trampoline, reverse-bytecode, etc.) before
 * tackling the PLT / load-base problem.
 *
 * Build:
 *   arm-linux-gnueabihf-gcc -shared -fPIC -O1 -o libvmptest.so libvmptest.c
 * Protect:
 *   vmpacker -func "vmp_compute,vmp_verify_key" -v -o libvmptest_protected.so libvmptest.so
 */

#include "libvmptest.h"

/* ------------------------------------------------------------------ */
/*  vmp_compute                                                        */
/* ------------------------------------------------------------------ */
int vmp_compute(const char *input, int mode, int seed) {
    if (!input)
        return -1;

    unsigned int h = (unsigned int)seed ^ 0xA5A5A5A5u;

    /* FNV-1a–style hash over input bytes */
    int i = 0;
    while (input[i] && i < 128) {
        h ^= (unsigned char)input[i];
        h *= 0x01000193u;
        i++;
    }

    int result = (int)(h & 0x7FFFFFFFu);

    /* Mode-dependent transform (branch + arithmetic mix) */
    if (mode == 1) {
        result = (result >> 4) ^ (result << 3);
        result &= 0x7FFFFFFF;
    } else if (mode == 2) {
        result = result * 7 + 13;
    } else {
        result ^= 0xDEADBEEF;
        result &= 0x7FFFFFFF;
    }

    /* Small iteration — tests loop translation */
    for (int j = 0; j < (mode + 1) * 3; j++) {
        result += j * 5 - 2;
    }

    return result & 0xFFFF;
}

/* ------------------------------------------------------------------ */
/*  vmp_verify_key                                                     */
/* ------------------------------------------------------------------ */
int vmp_verify_key(const char *key, int product_id) {
    if (!key)
        return 0;

    unsigned int acc = (unsigned int)product_id * 2654435761u;

    int i = 0;
    while (key[i] && i < 32) {
        acc = (acc << 5) | (acc >> 27);
        acc ^= (unsigned char)key[i];
        acc += (unsigned int)i * 7;
        i++;
    }

    if (i < 4)
        return 0;

    unsigned int expected = (unsigned int)product_id ^ 0x55AA55AAu;
    expected = (expected * 31) & 0xFFFFFFFFu;

    return (acc & 0xFFFF) == (expected & 0xFFFF) ? 1 : 0;
}
