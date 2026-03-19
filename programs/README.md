# Guest Programs

Sub-VM guest programs that run inside CoreStation via `host_machine()`.  
Each program is a `.pvm` blob in JAM SPI format — RO data, RW data, and code
packaged together with a minimal stub that exports only `guest_main`.

## Prerequisites

- Docker (the build runs inside `ghcr.io/dreverr/jamc3`)

## Building

Build a guest by passing its directory name under `programs/` to the `guest-build` script:

```bash
# Build the hello guest
./scripts/guest-build programs/hello

# Build the add guest
./scripts/guest-build programs/add
```

### Build output

```
programs/hello/build/
  guest.polkavm    # Intermediate PolkaVM binary
  guest.pvm        # JAM SPI blob (this is what CoreStation loads)
```

### What's in the .pvm file

The `.pvm` file is a JAM SPI (Service Program Image) with:
- Read-only data (string literals, constants)
- Read-write data (global buffers like the console)
- PVM code blob (jump table + bytecode + bitmask)

But unlike a full JAM service, the stub only exports `guest_main` — no `refine`,
`accumulate`, or host call imports. This is the correct format for sub-VM
guests that run inside a host service via `host_machine()`.

### SPI memory layout

```
0x00000000  Guard (unmapped)
0x00010000  RO data (string literals, constants)
0x00020000+ RW data (global buffers — address depends on RO size)
  ...
STACK_TOP   Stack (grows downward)
0xFEFE0000  Stack segment end
0xFEFF0000  Arguments (read-only, r7 points here, r8 = length)
```

**RW base address** (where globals live):

```
ro_pages = ceil(ro_size / 4096)
rw_base  = 0x10000 + 0x10000 * (1 + ro_pages)    when ro_size > 0
rw_base  = 0x20000                                 when ro_size = 0
```

Examples: `ro=0` → RW at `0x20000`, `ro=44` → RW at `0x30000`, `ro=4097` → RW at `0x40000`.

**Stack range**:

```
stack_bottom = 0xFEFE0000 - stack_size
stack_top    = 0xFEFE0000
r0 (SP)      = 0xFFFF0000
r1 (FP)      = 0xFEFE0000
```

Stack size is set by `--min-stack-size` in the build script (default: 4096).
The stack is writable and does not add to blob size — only the size value
is stored in the SPI header.

## Writing a new guest

1. Create a directory under `programs/`:

```bash
mkdir programs/myguest
```

2. Write a `.c3` source file with a `guest_main` entry point:

```c3
// programs/myguest/myguest.c3
module guest_myguest;

fn ulong guest_main(char* argv, ulong argc) @export("guest_main")
{
    // argv = pointer to arguments buffer (read-only)
    // argc = length of arguments in bytes
    // return value in r7
    return 42;
}
```

3. Build it:

```bash
./scripts/guest-build programs/myguest
```

## How guests run

Guests don't run on JAM standalone. CoreStation's manager service:

1. Creates a sub-VM from the `guest.pvm` blob via `host_machine()`
2. Allocates memory pages via `host_pages()`
3. Injects I/O state (keyboard, console, framebuffer, audio) via `host_poke()`
4. Invokes `guest_main()` via `host_invoke()` with a gas budget and registers
5. Reads back results via `host_peek()` and modified registers

## Local debugging with anan-as

You can run and debug `.pvm` blobs locally using
[anan-as](https://www.npmjs.com/package/@fluffylabs/anan-as), a PVM
debugger/emulator. Install it globally via `npm`:

```bash
npm install -g @fluffylabs/anan-as@next
```

Since `.pvm` files are JAM SPI blobs, use the `--spi` flag.

### Running the `add` guest

`add` reads `ulong` values from the SPI arguments buffer and returns their sum.
Pass the values as hex-encoded SPI args (two u64 LE values: 5 and 3):

```bash
# Sum 5 + 3 = 8
anan-as run --spi --no-logs --gas 100000 \
  programs/add/build/guest.pvm 0x05000000000000000300000000000000
```

Expected output: status HALT, `r7 = 8`.

### Running the `hello` guest

`hello` reads a tick count and text from the SPI arguments (read-only),
writes output to a global console buffer in the RW segment, and returns
tick+1. Pass tick=5 and text "Hello JAM" as SPI args:

```bash
# tick=5 (u32 LE) + "Hello JAM" (ASCII)
anan-as run --spi --no-logs --gas 1000000 \
  --dump "0x30000:0xa0" \
  programs/hello/build/guest.pvm 0x0500000048656c6c6f204a414d
```

Expected output: status HALT, `r7 = 6` (tick incremented), and the dump
at `0x30000` shows:

```
Hello from PVM! Tick:5
Text: Hello JAM
```

The console buffer is a global `char[2000]` in the RW data segment,
mapped at a fixed address (`0x30000` for this build). The host can
`host_peek` this address to read the console output.

### Disassembling a guest

```bash
anan-as disassemble --spi programs/add/build/guest.pvm
```

### SPI register conventions

| Register | ABI Name | Convention |
|----------|----------|------------|
| r0 | SP | Stack pointer (set by SPI loader) |
| r1 | RA/FP | Return address / frame pointer |
| r7 | a0 | argv — pointer to arguments buffer / return value |
| r8 | a1 | argc — length of arguments in bytes |

### Key flags

| Flag | Description |
|------|-------------|
| `--spi` | Input is a JAM SPI blob (.pvm file) |
| `--no-logs` | Suppress per-instruction trace (remove for step-by-step debugging) |
| `--gas <n>` | Gas budget (default: 10000) |
| `--regs <csv>` | 13 comma-separated register values r0-r12 (supports `0x` hex) |
| `--pages <specs>` | Memory pages, semicolon-separated `addr:size` (append `:r` for read-only) |
| `--mem <specs>` | Initialize memory, semicolon-separated `addr:hexbytes` |
| `--dump <specs>` | Dump memory after execution, semicolon-separated `addr:len` |

### Exit status codes

| Status | Meaning |
|--------|---------|
| 0 | HALT — clean exit |
| 1 | PANIC |
| 2 | PAGE_FAULT — `exit_code` is the faulting address |
| 3 | HOST — guest tried an ecalli (sub-VMs have no host calls) |
| 4 | OOG — out of gas |
