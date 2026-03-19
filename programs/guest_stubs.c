// CoreStation Guest Program - PolkaVM Export Stubs
//
// Provides the .polkavm_metadata and .polkavm_exports sections that polkatool
// needs to build the dispatch table for guest programs.
//
// Guest programs have a single entry point: guest_main.
// No host imports (no refine/accumulate, no host call functions).

typedef unsigned long long uint64_t;

// ---- PolkaVM metadata structures (same as host_stubs.c) ----

struct PolkaVM_Metadata {
    unsigned char version;
    unsigned int flags;
    unsigned int symbol_length;
    const char * symbol;
    unsigned char input_regs;
    unsigned char output_regs;
} __attribute__ ((packed));

#define POLKAVM_EXPORT_DEF()  \
    ".quad %[metadata]\n" \
    ".quad %[function]\n"

#define CONCAT2(a, b) a ## b
#define CONCAT(a, b) CONCAT2(a, b)

#define GUEST_EXPORT(fn_name, in_regs, out_regs) \
extern void fn_name(); \
static struct PolkaVM_Metadata fn_name##__EXPORT_METADATA \
    __attribute__ ((section(".polkavm_metadata"), used)) = { \
    1, 0, sizeof(#fn_name) - 1, #fn_name, in_regs, out_regs \
}; \
static void __attribute__ ((naked, used)) CONCAT(polkavm_export_dummy_, fn_name)() { \
    __asm__( \
        ".pushsection .polkavm_exports,\"Ra\",@note\n" \
        ".byte 1\n" \
        POLKAVM_EXPORT_DEF() \
        ".popsection\n" \
        : \
        : [metadata] "i" (&fn_name##__EXPORT_METADATA), \
          [function] "i" (fn_name) \
        : "memory" \
    ); \
}

// ---- Builtins required by C3 for local arrays ----

void *memset(void *s, int c, unsigned long n) {
    unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

void *memcpy(void *dest, const void *src, unsigned long n) {
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

// Export: guest_main(argv, argc) -> result
GUEST_EXPORT(guest_main, 2, 1)
