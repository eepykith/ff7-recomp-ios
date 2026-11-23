#!/usr/bin/env python3
"""Make the Android core's host code address guest memory through g_mem_base.

The Android core (and the Rosetta Mac host) run the lift with RECOMP_FLAT_MEMORY: a guest
address IS a host address below 4 GB, so the Win32 shims, FF7 HLE and FFNx turn guest
addresses into pointers with plain casts. Native arm64 Apple processes keep a 4 GB PAGEZERO,
so there the guest lives in a window at g_mem_base (FF7_BASED_MEMORY, ff7_boot.c).

The window is 4 GB aligned, so host -> guest stays a truncation, (uint32_t)(uintptr_t)p, and
only guest -> host needs the base. This transform routes those through two helpers declared
in pcrecomp's recomp_types.h:

    G2H(va)  guest address -> host pointer (0 -> NULL; base + va otherwise)
    H2G(p)   host pointer -> guest address

With g_mem_base == 0 (every flat build) both are the old casts, so the rewrite is safe for
Android and Rosetta too.

Rewrites (idempotent; a marker line records each converted file):
    (T *)(uintptr_t)X                          -> (T *)G2H(X)
    reinterpret_cast<T *>(static_cast<uintptr_t>(X)) -> reinterpret_cast<T *>(G2H(X))
    (T *)get_absolute_value(...) / get_relative_call(...) -> (T *)G2H(get_...(...))   [FFNx]
    (T *)0xADDR                                 -> (T *)G2H(0xADDR)                   [FFNx]
plus a few hand-placed edits (fixed mmaps, guest_abi.h) listed in EDITS below.

usage: python3 -I tools/based_memory_port.py <ff7-recomp-android root> [--check]
"""
import os
import re
import sys

MARKER = 'FF7_IOS_BASED_MEMORY: guest addresses go through G2H (tools/based_memory_port.py)'

# Files whose (T *)(uintptr_t)X casts take guest addresses.
UINTPTR_DIRS = [
    'external/pcrecomp/runtime/win32hle',
    'src/hle', 'src/host', 'src/ffnx_bridge', 'src/ffnx_port', 'src/mods',
]
SKIP = re.compile(r'selftest|/include_stub_ffmpeg/')
# FFNx sources: its address tables and patch helpers.
FFNX_DIR = 'external/FFNx/src'

CAST_TYPE = r'\(\s*(?:(?:const|volatile|struct|unsigned|signed)\s+)*[A-Za-z_][\w:]*(?:\s*<[^()<>;]*>)?\s*(?:const\s*)?\*+\s*(?:const\s*)?\)'
UINTPTR_CAST = re.compile(r'(' + CAST_TYPE + r')\s*\(uintptr_t\)\s*')
REINTERPRET = re.compile(r'(reinterpret_cast<[^<>;]*\*\s*>\s*\()\s*static_cast<uintptr_t>\s*')
FFNX_CALL_CAST = re.compile(r'(' + CAST_TYPE + r')\s*(?=(?:get_absolute_value|get_relative_call)\s*\()')
FFNX_LIT_CAST = re.compile(r'(' + CAST_TYPE + r')\s*(0x[0-9A-Fa-f]+)\b')


def match_group(s, i):
    """s[i] is an opening bracket; return the index just past its match."""
    pairs = {'(': ')', '[': ']'}
    stack = [pairs[s[i]]]
    j = i + 1
    while j < len(s) and stack:
        c = s[j]
        if c in pairs:
            stack.append(pairs[c])
        elif c == stack[-1]:
            stack.pop()
        elif c in ')]':
            raise ValueError('unbalanced')
        j += 1
    if stack:
        raise ValueError('unbalanced')
    return j


TYPE_GROUP = re.compile(r'\(\s*(?:(?:const|volatile|struct|unsigned|signed)\s+)*[A-Za-z_][\w:]*(?:\s*<[^()<>;]*>)?\s*[*\s]*\)$')


def skip_ws(s, i):
    while i < len(s) and s[i] in ' \t':
        i += 1
    return i


def operand_end(s, i):
    """End of the unary operand starting at s[i]: a prefix op (* & - ~ !) or a cast applied to
    an operand, a (group), or a name; then ->, ., [], () suffixes."""
    i = skip_ws(s, i)
    if i < len(s) and s[i] in '*&~!-' and not s.startswith('->', i):
        return operand_end(s, i + 1)
    if i < len(s) and s[i] == '(':
        j = match_group(s, i)
        k = skip_ws(s, j)
        if TYPE_GROUP.match(s[i:j]) and k < len(s) and (s[k].isalnum() or s[k] in '_(*&'):
            return operand_end(s, k)                 # (T *)expr: a cast applied to expr
    else:
        lit = re.compile(r'(?:0[xX][0-9A-Fa-f]+|\d+)[uUlL]*\b').match(s, i)
        if lit:
            return lit.end()                         # a literal address
        m = re.compile(r'[A-Za-z_]\w*(?:::\w+)*').match(s, i)
        if not m:
            raise ValueError(f'no operand at {s[i:i+30]!r}')
        j = m.end()
    while True:
        k = j
        while k < len(s) and s[k] in ' \t':
            k += 1
        if s.startswith('->', k) or (k < len(s) and s[k] == '.' and not s.startswith('...', k)):
            m2 = re.compile(r'(?:->|\.)\s*[A-Za-z_]\w*').match(s, k)
            if not m2:
                return j
            j = m2.end()
        elif k < len(s) and s[k] in '[(':
            j = match_group(s, k)
        else:
            return j


def wrap_after(text, pattern, keep_group=1, keep=()):
    """For each match, wrap the operand that follows it in G2H(...) (operands in keep stay)."""
    out, pos, n = [], 0, 0
    for m in pattern.finditer(text):
        if m.start() < pos:
            continue
        start = m.end()
        try:
            end = operand_end(text, start)
        except ValueError:
            continue
        operand = text[start:end]
        if operand.startswith('G2H(') or operand.strip() in keep:
            continue
        out.append(text[pos:m.start()])
        out.append(m.group(keep_group) + 'G2H(' + operand + ')')
        pos = end
        n += 1
    out.append(text[pos:])
    return ''.join(out), n


def convert_runtime(text):
    text, a = wrap_after(text, UINTPTR_CAST)
    text, b = wrap_after(text, REINTERPRET)
    return text, a + b


# (T *)(uintptr_t)X operands in FFNx that are not guest data addresses.
FFNX_UINTPTR_KEEP = {'gameHwnd', 'ffnx_recomp::guest_va_of(f)'}


# reinterpret_cast<T *>(X) where X is a 32-bit guest address (clang does not flag these the
# way it flags C-style casts, so the operands are listed). FF8-only files are not built.
FFNX_REINTERPRET_G2H = {
    'ff7_data.h': ['get_absolute_value(ff7_externals.swirl_enter_sub_401810, 0xE) + 0x112C'],
    'ff7/battle/battle.cpp': ['texture_resource', 'ifrit_resources'],
    'ff7/field/field.cpp': ['ff7_externals.field_map_infos + 0xBC'],
    'ff7/japanese_text.cpp': ['ff7_externals.current_dialog_string_pointer[WINDOW_ID]'],
    'ff7/misc.cpp': ['ff7_externals.current_dialog_string_pointer[WINDOW_ID]',
                     'ff7_externals.world_current_dialog_string_pointer[WINDOW_ID]'],
    'ff7/universal_buttons.cpp': ['ff7_externals.current_dialog_string_pointer[window_index]'],
    'ff7/multilanguage.cpp': ['address'],
}
REINTERPRET_ANY = re.compile(r'(reinterpret_cast<[^<>;]*\*\s*>\s*)\(')


def wrap_reinterpret(text, operands):
    out, pos, n = [], 0, 0
    for m in REINTERPRET_ANY.finditer(text):
        if m.start() < pos:
            continue
        open_ = m.end() - 1
        close = match_group(text, open_)
        inner = text[open_ + 1:close - 1]
        if ' '.join(inner.split()) not in operands:
            continue
        out.append(text[pos:open_ + 1] + 'G2H(' + inner + ')')
        pos = close - 1
        n += 1
    out.append(text[pos:])
    return ''.join(out), n


def convert_ffnx(text, rel=''):
    # the Android port's own FFNx edits read game memory as (T *)(uintptr_t)va
    text, u = wrap_after(text, UINTPTR_CAST, keep=FFNX_UINTPTR_KEEP)
    text, a = wrap_after(text, FFNX_CALL_CAST)
    text, b = FFNX_LIT_CAST.subn(lambda m: f'{m.group(1)}G2H({m.group(2)})', text)
    c = 0
    text, c = wrap_after(text, REINTERPRET)
    ops = FFNX_REINTERPRET_G2H.get(rel.split('external/FFNx/src/', 1)[-1], [])
    text, d = wrap_reinterpret(text, ops) if ops else (text, 0)
    return text, u + a + b + c + d


# Hand-placed edits: (file, old, new). Applied before the regex passes; each must match
# exactly once unless already applied (new text present).
G2H_DECL = '''extern ptrdiff_t g_mem_base;
/* FF7_IOS_BASED_MEMORY: guest address <-> host pointer for host code (shims, HLE, FFNx).
 * g_mem_base is 0 in flat builds, so these are the plain casts there. The based window is
 * 4 GB aligned (ff7_boot.c), so a host pointer into it truncates to its guest address. */
#define G2H(va) ((void *)((uint32_t)(va) ? (uintptr_t)(uint32_t)(va) + (uintptr_t)g_mem_base : (uintptr_t)0))
#define H2G(p)  ((uint32_t)(uintptr_t)(p))
'''
EDITS = [
    # ff7_boot.c: the 4 GB-aligned guest window, reserved once before anything maps guest
    # memory (also from static initialisers: ffnx_guest_static.cpp).
    ('src/host/ff7_boot.c',
     'int ff7_boot_and_run(const char *game_dir) {\n',
     '''/* FF7_IOS_BASED_MEMORY: native arm64 keeps a 4 GB PAGEZERO, so the guest's 32-bit space is a
 * window at g_mem_base. 4 GB aligned: a host pointer into it truncates to its guest address.
 * Only [0, FF7_LAYOUT_MAX) is reserved, PROT_NONE until mapped; page 0 never is. Idempotent;
 * a no-op in flat builds. */
int ff7_guest_window_init(void) {
#ifdef FF7_BASED_MEMORY
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static int rc = 1;
    pthread_mutex_lock(&lock);
    if (rc == 1) {
        const uintptr_t span = FF7_LAYOUT_MAX, align = (uintptr_t)1 << 32;
        uint8_t *r = (uint8_t *)mmap(NULL, span + align, PROT_NONE,
                                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (r == MAP_FAILED) {
            perror("[ff7] reserve guest window");
            rc = -1;
        } else {
            uintptr_t b = ((uintptr_t)r + align - 1) & ~(align - 1), end = (uintptr_t)r + span + align;
            if (b > (uintptr_t)r) munmap(r, b - (uintptr_t)r);
            if (end > b + span) munmap((void *)(b + span), end - (b + span));
            g_mem_base = (ptrdiff_t)b;
            fprintf(stderr, "[ff7] guest window 0x%llx (+0x%llx), based memory\\n",
                    (unsigned long long)b, (unsigned long long)span);
            rc = 0;
        }
    }
    pthread_mutex_unlock(&lock);
    return rc;
#else
    return 0;
#endif
}

int ff7_boot_and_run(const char *game_dir) {
'''),
    ('src/host/ff7_boot.c',
     '    if (ff7_pick_layout(&arena_lo, &arena_hi, &vm_lo, &vm_hi) != 0) return 70;\n',
     '    if (ff7_guest_window_init() != 0) return 70;   /* FF7_IOS_BASED_MEMORY */\n'
     '    if (ff7_pick_layout(&arena_lo, &arena_hi, &vm_lo, &vm_hi) != 0) return 70;\n'),
    ('src/host/ff7_boot.c',
     '#define _GNU_SOURCE\n',
     '#define _GNU_SOURCE\n#include <pthread.h>   /* ff7_guest_window_init (FF7_IOS_BASED_MEMORY) */\n'),
    # guest_alloc: the arena lives in the window; MAP_FIXED replaces the reservation.
    ('external/pcrecomp/runtime/win32hle/guest_alloc.c',
     '    if (p == MAP_FAILED || (uintptr_t)p != lo) {',
     '    if (p == MAP_FAILED || (uintptr_t)p != (uintptr_t)G2H(lo)) {'),
    ('external/pcrecomp/runtime/win32hle/guest_alloc.c',
     '#include "guest_alloc.h"\n',
     '#include "guest_alloc.h"\n#include "recomp_types.h"   /* G2H (FF7_IOS_BASED_MEMORY) */\n'),
    ('external/pcrecomp/runtime/win32hle/pe_loader.c',
     '#include "pe_loader.h"\n',
     '#include "pe_loader.h"\n#include "recomp_types.h"   /* G2H (FF7_IOS_BASED_MEMORY) */\n'),
    ('src/hle/ff7_virtual.c',
     '    if (p == MAP_FAILED || (uintptr_t)p != lo) {',
     '    if (p == MAP_FAILED || (uintptr_t)p != (uintptr_t)G2H(lo)) {'),
    # guest_alloc: host pointers checked against the arena's guest range (subtract, don't
    # truncate: a host pointer outside the window must not alias into the arena).
    ('external/pcrecomp/runtime/win32hle/guest_alloc.c',
     '''static ga_hdr *ga_header(void *p) {
    uintptr_t a = (uintptr_t)p;
    if (a < (uintptr_t)g_arena_lo + GA_HDR || a >= g_arena_hi) ga_die("free of a pointer outside the guest arena", (uint32_t)a);
    ga_hdr *h = (ga_hdr *)(a - GA_HDR);''',
     '''static ga_hdr *ga_header(void *p) {
    uintptr_t a = (uintptr_t)p - (uintptr_t)g_mem_base;   /* FF7_IOS_BASED_MEMORY */
    if (a < (uintptr_t)g_arena_lo + GA_HDR || a >= g_arena_hi) ga_die("free of a pointer outside the guest arena", (uint32_t)a);
    ga_hdr *h = (ga_hdr *)((uintptr_t)p - GA_HDR);'''),
    ('external/pcrecomp/runtime/win32hle/guest_alloc.c',
     '''int guest_alloc_is_guest(const void *p) {
    uintptr_t a = (uintptr_t)p;''',
     '''int guest_alloc_is_guest(const void *p) {
    uintptr_t a = (uintptr_t)p - (uintptr_t)g_mem_base;   /* FF7_IOS_BASED_MEMORY */'''),
    # strcpy_s forwards src through varargs: a gptr<char> would arrive as its raw guest address.
    ('src/ffnx_port/include/windows.h',
     '#define strcpy_s(dst, n, src) (snprintf((dst), (n), "%s", (src)), 0)',
     '#define strcpy_s(dst, n, src) (snprintf((dst), (n), "%s", (const char *)(src)), 0)   /* FF7_IOS_BASED_MEMORY */'),
    # printf-checked loggers, so -Wformat can find gptr values passed through their varargs.
    ('external/FFNx/src/log.h',
     'void debug_printf(const char *, uint32_t, const char *, ...);',
     'void debug_printf(const char *, uint32_t, const char *, ...) __attribute__((format(printf, 3, 4)));   // FF7_IOS_BASED_MEMORY'),
    # guest_abi.h: gptr<T> and every FFNx guest pointer convert here.
    ('src/ffnx_bridge/guest_abi.h',
     '''    if (a > 0xFFFFFFFFu) fatal("host pointer given to the guest (not guest memory)", a);
    return static_cast<uint32_t>(a);''',
     '''    if (!a) return 0;
    if (a - static_cast<uintptr_t>(g_mem_base) > 0xFFFFFFFFu) fatal("host pointer given to the guest (not guest memory)", a);
    return static_cast<uint32_t>(a - static_cast<uintptr_t>(g_mem_base));   // FF7_IOS_BASED_MEMORY'''),
    ('src/ffnx_bridge/guest_abi.h',
     'template <typename T> inline T *ptr_of_raw(uint32_t va) { return reinterpret_cast<T *>(static_cast<uintptr_t>(va)); }',
     'template <typename T> inline T *ptr_of_raw(uint32_t va) { return reinterpret_cast<T *>(reinterpret_cast<uintptr_t>(G2H(va))); }'),
    ('src/ffnx_port/ffnx_guest_static.cpp',
     'void *p = mmap(reinterpret_cast<void *>(k_base), k_size,',
     'void *p = mmap(G2H(k_base), k_size,'),
    ('src/ffnx_port/ffnx_guest_static.cpp',
     '    if (!g_next) {\n',
     '    if (!g_next) {\n        if (ff7_guest_window_init() != 0) std::abort();   // FF7_IOS_BASED_MEMORY: may run before boot\n'),
    ('src/ffnx_port/ffnx_guest_static.cpp',
     '    return reinterpret_cast<void *>(at);   // zeroed (fresh anonymous pages)\n',
     '    return G2H(at);   // zeroed (fresh anonymous pages); FF7_IOS_BASED_MEMORY: a host pointer\n'),
    ('src/ffnx_port/ffnx_guest_static.cpp',
     'namespace {\nconstexpr uintptr_t k_base',
     'extern "C" int ff7_guest_window_init(void);   // src/host/ff7_boot.c (FF7_IOS_BASED_MEMORY)\n\nnamespace {\nconstexpr uintptr_t k_base'),
    ('src/ffnx_port/ffnx_guest_static.cpp',
     'if (p != reinterpret_cast<void *>(k_base)) {',
     'if (p != G2H(k_base)) {'),
]


def apply_edits(root, check):
    for rel, old, new in EDITS:
        path = os.path.join(root, rel)
        t = open(path, encoding='utf-8', errors='surrogateescape').read()
        if new in t:
            continue
        if t.count(old) != 1:
            raise SystemExit(f'{rel}: expected one match for an edit; layout changed:\n{old[:120]}')
        if not check:
            open(path, 'w', encoding='utf-8', errors='surrogateescape').write(t.replace(old, new, 1))
        print(f'  {rel}: edit applied')


def convert_tree(root, rel_dir, fn, exts, check):
    total = 0
    for dirpath, _, files in os.walk(os.path.join(root, rel_dir)):
        for f in sorted(files):
            if not f.endswith(exts):
                continue
            path = os.path.join(dirpath, f)
            rel = os.path.relpath(path, root)
            if SKIP.search(rel):
                continue
            t = open(path, encoding='utf-8', errors='surrogateescape').read()
            new, n = fn(t, rel) if fn is convert_ffnx else fn(t)   # passes skip what is wrapped
            if not n:
                continue
            total += n
            print(f'  {rel}: {n} casts')
            if not check:
                nl = '\r\n' if '\r\n' in new else '\n'
                head = '' if MARKER in new else f'// {MARKER}{nl}'
                if not re.search(r'#include\s+"(recomp_types|win32hle|guest_abi|ffnx_guest)\.h"', new) and f.endswith(('.c', '.cpp')):
                    inc = '#include "recomp_types.h"'
                    if f.endswith('.cpp'):
                        inc = f'extern "C" {{{nl}{inc}{nl}}}'
                    head += inc + nl
                if MARKER in new and not head:
                    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
                    continue
                open(path, 'w', encoding='utf-8', errors='surrogateescape').write(head + new)
    return total


def fix_from_warnings(root, sites_file):
    """Wrap the operand of each data-pointer cast clang flagged with -Wint-to-pointer-cast /
    -Wint-to-void-pointer-cast (a 32-bit guest address made a pointer) in G2H.
    sites_file: lines 'rel/path:line:col' (col = the cast's '(').
    Leaves function-pointer casts (call targets; gfn truncates them back to guest addresses)
    and MSVC cast-as-lvalue assignments alone. Used once to produce patches/ffnx-based-memory.patch."""
    by_file = {}
    for ln in open(sites_file):
        ln = ln.strip()
        if not ln:
            continue
        rel, line, col = ln.rsplit(':', 2)
        by_file.setdefault(rel, []).append((int(line), int(col)))
    done = skipped = 0
    for rel, sites in by_file.items():
        path = os.path.join(root, rel)
        raw = open(path, 'rb').read().decode('utf-8', errors='surrogateescape')
        nl = '\r\n' if '\r\n' in raw else '\n'
        lines = raw.split(nl)
        # right-to-left within a line so earlier columns stay valid
        for line, col in sorted(sites, key=lambda t: (t[0], -t[1])):
            text = lines[line - 1]
            i = col - 1
            if i >= len(text) or text[i] != '(':
                print(f'  skip {rel}:{line}:{col}: not a cast here'); skipped += 1; continue
            j = match_group(text, i)
            ctype = text[i:j]
            if '(*' in ctype.replace(' ', '') or '(__' in ctype:
                skipped += 1; continue                      # function pointer: a call target
            k = j
            while k < len(text) and text[k] in ' \t':
                k += 1
            if text.startswith('G2H(', k):
                continue
            try:
                end = operand_end(text, k)
            except ValueError:
                print(f'  skip {rel}:{line}:{col}: operand not parsed'); skipped += 1; continue
            rest = text[end:].lstrip()
            if re.match(r'(?:[-+*/|&^]|<<|>>)?=(?!=)', rest) and not text[:i].rstrip().endswith('*'):
                print(f'  skip {rel}:{line}:{col}: cast-as-lvalue'); skipped += 1; continue
            lines[line - 1] = text[:k] + 'G2H(' + text[k:end] + ')' + text[end:]
            done += 1
        open(path, 'wb').write(nl.join(lines).encode('utf-8', errors='surrogateescape'))
    print(f'warnings: {done} casts wrapped, {skipped} left as they are')


def fix_formats(root, log_file):
    """Wrap each gptr<char> passed to a %s (clang -Wformat, with debug_printf annotated) in
    (const char *)(...): through varargs a gptr arrives as its raw guest address."""
    pat = re.compile(r"^(?:.*/ff7-recomp-android/)?(?P<rel>[^:]+):(?P<line>\d+):(?P<col>\d+): warning: format specifies type 'char \*' but the argument has type 'gptr<char>'")
    by_file = {}
    for ln in open(log_file, errors='replace'):
        m = pat.match(ln.strip())
        if m:
            by_file.setdefault(m['rel'], set()).add((int(m['line']), int(m['col'])))
    n = 0
    for rel, sites in by_file.items():
        path = os.path.join(root, rel)
        raw = open(path, 'rb').read().decode('utf-8', errors='surrogateescape')
        nl = '\r\n' if '\r\n' in raw else '\n'
        lines = raw.split(nl)
        for line, col in sorted(sites, key=lambda t: (t[0], -t[1])):
            t = lines[line - 1]
            # clang points at the expression's own location (a member's name for a->b):
            # walk left to the argument's start, the top-level ',' or the call's '('.
            i, depth = col - 1, 0
            while i > 0:
                c = t[i - 1]
                if c in ')]':
                    depth += 1
                elif c in '([':
                    if depth == 0:
                        break
                    depth -= 1
                elif c == ',' and depth == 0:
                    break
                i -= 1
            while t[i] in ' \t':
                i += 1
            if t.startswith('(const char *)(', i):
                continue
            j, depth = i, 0
            while j < len(t):
                c = t[j]
                if c in '([':
                    depth += 1
                elif c in ')]':
                    if depth == 0:
                        break
                    depth -= 1
                elif c == ',' and depth == 0:
                    break
                j += 1
            arg = t[i:j].rstrip()
            lines[line - 1] = t[:i] + '(const char *)(' + arg + ')' + t[i + len(arg):]
            n += 1
        open(path, 'wb').write(nl.join(lines).encode('utf-8', errors='surrogateescape'))
    print(f'formats: {n} gptr<char> varargs wrapped')


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == 'warnings':
        return fix_from_warnings(sys.argv[2], sys.argv[3])
    if sys.argv[1] == 'formats':
        return fix_formats(sys.argv[2], sys.argv[3])
    root = sys.argv[1]
    check = '--check' in sys.argv[2:]
    apply_edits(root, check)
    n = 0
    for d in UINTPTR_DIRS:
        n += convert_tree(root, d, convert_runtime, ('.c', '.cpp', '.h'), check)
    n += convert_tree(root, FFNX_DIR, convert_ffnx, ('.cpp', '.h'), check)
    print(f'based memory: {n} casts {"would change" if check else "converted"}')


if __name__ == '__main__':
    main()
