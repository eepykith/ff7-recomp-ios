// The two compressions Steam uses for depot chunks, for the Builder's Steam download
// (Sources/Steam/SteamDepot.swift): LZMA (the LZMA SDK's LzmaDec.c, public domain) and zstd
// (Zstandard's decompressor, BSD; Vendor/zstd/LICENSE).
#pragma once
#include <stddef.h>
#include <stdint.h>

// Raw LZMA with its 5-byte properties: returns the bytes written to dst, or -1.
long ff7_lzma_decode(const uint8_t *props, const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len);

// One zstd frame: returns the bytes written to dst, or -1.
long ff7_zstd_decode(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len);
