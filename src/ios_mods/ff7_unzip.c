/* ff7_unzip.c: unpack a .zip mod download (ModDownloader.swift), with the system's zlib.
 *
 * Reads the central directory (ZIP64 included: big texture packs pass 4 GB), then each entry
 * from its local header: stored or deflated, streamed to its file through a 1 MB buffer, so
 * memory stays small whatever the mod's size. Paths are checked to stay inside the output
 * folder; encrypted entries and other methods (Deflate64, BZip2, LZMA) are reported. */
#include "ff7_unzip.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

static volatile int g_cancel;
static volatile unsigned long long g_done, g_total;
void ff7_unzip_cancel(void) { g_cancel = 1; }
void ff7_unzip_progress(unsigned long long *done, unsigned long long *total) { *done = g_done; *total = g_total; }

#define BUF (1u << 20)

static int fail(char *err, size_t n, const char *fmt, const char *a) {
  snprintf(err, n, fmt, a ? a : "");
  return -1;
}

static uint16_t u16(const unsigned char *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t u32(const unsigned char *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint64_t u64(const unsigned char *p) { return (uint64_t)u32(p) | (uint64_t)u32(p + 4) << 32; }

static int read_at(int fd, void *buf, size_t n, uint64_t off) {
  size_t got = 0;
  while (got < n) {
    ssize_t r = pread(fd, (char *)buf + got, n - got, (off_t)(off + got));
    if (r <= 0) return -1;
    got += (size_t)r;
  }
  return 0;
}

static int write_all(int fd, const unsigned char *p, size_t n) {
  while (n) {
    ssize_t w = write(fd, p, n);
    if (w < 0) { if (errno == EINTR) continue; return -1; }
    p += w; n -= (size_t)w;
  }
  return 0;
}

static int mkdirs(char *path) {          /* path: a directory; modified in place, restored */
  for (char *s = path + 1; *s; s++) {
    if (*s != '/') continue;
    *s = 0;
    if (mkdir(path, 0755) != 0 && errno != EEXIST) { *s = '/'; return -1; }
    *s = '/';
  }
  return mkdir(path, 0755) != 0 && errno != EEXIST ? -1 : 0;
}

/* The entry's path below outdir, or NULL when it would leave it (absolute, "..") */
static char *entry_path(const char *outdir, const unsigned char *name, size_t len) {
  char *rel = malloc(len + 1);
  if (!rel) return NULL;
  for (size_t i = 0; i < len; i++) rel[i] = name[i] == '\\' ? '/' : (char)name[i];
  rel[len] = 0;
  const char *r = rel;
  while (*r == '/') r++;
  for (const char *s = r; *s;) {
    const char *e = strchr(s, '/');
    size_t n = e ? (size_t)(e - s) : strlen(s);
    if (n == 2 && s[0] == '.' && s[1] == '.') { free(rel); return NULL; }
    s += n + (e ? 1 : 0);
    if (!e) break;
  }
  size_t ol = strlen(outdir);
  char *out = malloc(ol + 2 + strlen(r));
  if (out) sprintf(out, "%s/%s", outdir, r);
  free(rel);
  return out;
}

int ff7_unzip(const char *archive, const char *outdir, char *err, size_t errlen) {
  g_cancel = 0; g_done = 0; g_total = 0;
  int fd = open(archive, O_RDONLY);
  if (fd < 0) return fail(err, errlen, "cannot open the download: %s", strerror(errno));
  struct stat st;
  fstat(fd, &st);
  uint64_t size = (uint64_t)st.st_size;
  int rc = -1;
  unsigned char *buf = malloc(BUF), *out = malloc(BUF);
  unsigned char *cd = NULL;
  if (!buf || !out) { fail(err, errlen, "out of memory%s", NULL); goto done; }

  /* end of central directory: the last 22..65557 bytes */
  uint64_t tail = size < 65557 ? size : 65557;
  if (tail < 22 || read_at(fd, buf, (size_t)tail, size - tail) != 0) { fail(err, errlen, "not a zip file%s", NULL); goto done; }
  long eocd = -1;
  for (long i = (long)tail - 22; i >= 0; i--)
    if (u32(buf + i) == 0x06054b50) { eocd = i; break; }
  if (eocd < 0) { fail(err, errlen, "not a zip file (no directory)%s", NULL); goto done; }
  uint64_t count = u16(buf + eocd + 10), cd_size = u32(buf + eocd + 12), cd_off = u32(buf + eocd + 16);
  uint64_t eocd_pos = size - tail + (uint64_t)eocd;
  if (eocd_pos >= 20) {                   /* ZIP64 locator just before it */
    unsigned char loc[20];
    if (read_at(fd, loc, 20, eocd_pos - 20) == 0 && u32(loc) == 0x07064b50) {
      unsigned char z[56];
      if (read_at(fd, z, 56, u64(loc + 8)) == 0 && u32(z) == 0x06064b50) {
        count = u64(z + 32); cd_size = u64(z + 40); cd_off = u64(z + 48);
      }
    }
  }
  if (cd_off + cd_size > size || cd_size > (256u << 20)) { fail(err, errlen, "the zip's directory is damaged%s", NULL); goto done; }
  cd = malloc((size_t)cd_size ? (size_t)cd_size : 1);
  if (!cd || read_at(fd, cd, (size_t)cd_size, cd_off) != 0) { fail(err, errlen, "cannot read the zip's directory%s", NULL); goto done; }

  /* pass 1: sizes for progress; pass 2: unpack */
  for (int pass = 0; pass < 2; pass++) {
    uint64_t p = 0;
    for (uint64_t i = 0; i < count; i++) {
      if (p + 46 > cd_size || u32(cd + p) != 0x02014b50) { fail(err, errlen, "the zip's directory is damaged%s", NULL); goto done; }
      const unsigned char *h = cd + p;
      uint16_t flags = u16(h + 8), method = u16(h + 10);
      uint64_t csize = u32(h + 20), usize = u32(h + 24), loff = u32(h + 42);
      uint16_t nlen = u16(h + 28), xlen = u16(h + 30), clen = u16(h + 32);
      if (p + 46 + nlen + xlen + clen > cd_size) { fail(err, errlen, "the zip's directory is damaged%s", NULL); goto done; }
      const unsigned char *name = h + 46, *x = name + nlen, *xe = x + xlen;
      while (x + 4 <= xe) {                  /* ZIP64 extra: the fields that are 0xFFFFFFFF */
        uint16_t id = u16(x), n = u16(x + 2);
        const unsigned char *v = x + 4, *ve = v + n;
        if (id == 0x0001) {
          if (usize == 0xFFFFFFFFu && v + 8 <= ve) { usize = u64(v); v += 8; }
          if (csize == 0xFFFFFFFFu && v + 8 <= ve) { csize = u64(v); v += 8; }
          if (loff == 0xFFFFFFFFu && v + 8 <= ve) { loff = u64(v); v += 8; }
        }
        x = ve;
      }
      p += 46 + nlen + xlen + clen;
      int is_dir = nlen > 0 && (name[nlen - 1] == '/' || name[nlen - 1] == '\\');
      if (pass == 0) { if (!is_dir) g_total += usize; continue; }
      if (g_cancel) { fail(err, errlen, "cancelled%s", NULL); goto done; }

      char *path = entry_path(outdir, name, nlen);
      if (!path) { fail(err, errlen, "the zip holds a path outside its folder%s", NULL); goto done; }
      if (is_dir) {
        size_t l = strlen(path);
        if (l && path[l - 1] == '/') path[l - 1] = 0;
        int bad = mkdirs(path);
        free(path);
        if (bad) { fail(err, errlen, "cannot create a folder: %s", strerror(errno)); goto done; }
        continue;
      }
      if (flags & 1) { free(path); fail(err, errlen, "the zip is password-protected%s", NULL); goto done; }
      if (method != 0 && method != 8) {
        free(path);
        snprintf(err, errlen, "the zip uses compression method %u, which is not supported (repack it as a normal zip or .7z)", method);
        goto done;
      }
      unsigned char lh[30];
      if (read_at(fd, lh, 30, loff) != 0 || u32(lh) != 0x04034b50) { free(path); fail(err, errlen, "the zip is damaged%s", NULL); goto done; }
      uint64_t data = loff + 30 + u16(lh + 26) + u16(lh + 28);
      if (data + csize > size) { free(path); fail(err, errlen, "the zip is cut short (download it again)%s", NULL); goto done; }

      char *slash = strrchr(path, '/');
      if (slash) { *slash = 0; int bad = mkdirs(path); *slash = '/'; if (bad) { free(path); fail(err, errlen, "cannot create a folder: %s", strerror(errno)); goto done; } }
      int ofd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
      if (ofd < 0) { fail(err, errlen, "cannot write a file: %s", strerror(errno)); free(path); goto done; }
      free(path);

      int bad = 0;
      uint64_t left = csize;
      if (method == 0) {
        while (left && !bad) {
          size_t n = left > BUF ? BUF : (size_t)left;
          if (g_cancel || read_at(fd, buf, n, data) != 0 || write_all(ofd, buf, n) != 0) bad = 1;
          data += n; left -= n; g_done += n;
        }
      } else {
        z_stream z;
        memset(&z, 0, sizeof z);
        if (inflateInit2(&z, -MAX_WBITS) != Z_OK) bad = 1;
        int zr = Z_OK;
        while (!bad && zr != Z_STREAM_END) {
          if (z.avail_in == 0) {
            if (!left) { bad = 1; break; }
            size_t n = left > BUF ? BUF : (size_t)left;
            if (read_at(fd, buf, n, data) != 0) { bad = 1; break; }
            data += n; left -= n;
            z.next_in = buf; z.avail_in = (uInt)n;
          }
          z.next_out = out; z.avail_out = BUF;
          zr = inflate(&z, Z_NO_FLUSH);
          if (zr != Z_OK && zr != Z_STREAM_END) { bad = 1; break; }
          size_t got = BUF - z.avail_out;
          if (write_all(ofd, out, got) != 0) bad = 1;
          g_done += got;
          if (g_cancel) bad = 1;
        }
        inflateEnd(&z);
      }
      if (close(ofd) != 0) bad = 1;
      if (bad) {
        if (g_cancel) fail(err, errlen, "cancelled%s", NULL);
        else fail(err, errlen, "could not unpack the zip (damaged, or the phone is full)%s", NULL);
        goto done;
      }
    }
  }
  rc = 0;
done:
  free(cd); free(buf); free(out);
  close(fd);
  return rc;
}
