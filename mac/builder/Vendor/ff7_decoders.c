#include "ff7_decoders.h"
#include <stdlib.h>
#include "lzma/LzmaDec.h"
#include "zstd/zstd.h"

static void *lz_alloc(ISzAllocPtr p, size_t size) { (void)p; return malloc(size); }
static void lz_free(ISzAllocPtr p, void *address) { (void)p; free(address); }
static const ISzAlloc lz_alloc_funcs = { lz_alloc, lz_free };

long ff7_lzma_decode(const uint8_t *props, const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len) {
    SizeT out = dst_len, in = src_len;
    ELzmaStatus status;
    SRes r = LzmaDecode(dst, &out, src, &in, props, LZMA_PROPS_SIZE, LZMA_FINISH_ANY, &status, &lz_alloc_funcs);
    if (r != SZ_OK) return -1;
    return (long)out;
}

long ff7_zstd_decode(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len) {
    size_t n = ZSTD_decompress(dst, dst_len, src, src_len);
    if (ZSTD_isError(n)) return -1;
    return (long)n;
}
