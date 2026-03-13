#ifndef LIBVMPTEST_H
#define LIBVMPTEST_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * vmp_compute - pure computation function (no external calls).
 *
 * Hashes the input string with arithmetic, bitwise, loop, and branch
 * instructions — the same mix that log2Console exercises.
 * Because it never calls libc or any PLT symbol, it can be VM-protected
 * in a shared library without the load-base fixup.
 *
 * @param input  NUL-terminated string (NULL → returns -1)
 * @param mode   selects the post-hash transform (0/1/2)
 * @param seed   initial hash seed
 * @return       16-bit result (0x0000–0xFFFF), or -1 on NULL input
 */
int vmp_compute(const char *input, int mode, int seed);

/**
 * vmp_verify_key - license-key style verifier (no external calls).
 *
 * Walks the key string, accumulates a checksum, and returns 1 if it
 * matches the expected value for the given product_id, 0 otherwise.
 */
int vmp_verify_key(const char *key, int product_id);

#ifdef __cplusplus
}
#endif

#endif /* LIBVMPTEST_H */
