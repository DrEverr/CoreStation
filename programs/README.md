# Guest Programs

Sub-VM guest programs that run inside CoreStation via `host_machine()`.  
Each program is a raw PVM code blob — no JAM service boilerplate.

## Prerequisites

- Docker (the build runs inside `ghcr.io/dreverr/jamc3`)
- Node.js (for the code-blob extraction step)

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
  guest.polkavm    # Full PolkaVM binary
  guest.pvm        # Raw code blob for host_machine() (this is what CoreStation loads)
  guest.jam        # Full JAM service blob (for size comparison only)
  guest.ro         # Required ReadOnly data to be provided at address @ 0x10000
```

## Writing a new guest

1. Create a directory under `programs/`:

```bash
mkdir programs/myguest
```

2. Write a `.c3` source file with a `guest_main` entry point:

```c3
// programs/myguest/myguest.c3
module guest_myguest;

fn ulong guest_main(ulong argc, ulong* argv) @export("guest_main")
{
    // argc = number of arguments
    // argv = pointer to argument array
    // return value passed back via register
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

You can run and debug `.pvm` code blobs locally using
[anan-as](https://www.npmjs.com/package/@fluffylabs/anan-as), a PVM
debugger/emulator. Install it globally via `npm`:

```bash
npm install -g @fluffylabs/anan-as
```

Since `.pvm` files are raw code blobs with no embedded memory layout, you must
provide the stack, memory pages, and initial register values manually.

### Running the `add` guest

`add` expects `r7 = argc`, `r8 = argv pointer`, and reads `u64` values from
memory at the argv address. It returns the sum in `r7`.

```bash
# Sum two numbers: 5 + 3 = 8
# Memory at 0x20000: two u64 LE values (5 and 3)
# Registers: r0=SP, r1=FP, r7=argc(2), r8=argv(0x20000)
anan-as run --no-metadata --no-logs --gas 100000 \
  --regs "0xFFFF0000,0xFFFF0000,0,0,0,0,0,2,0x20000,0,0,0,0" \
  --pages "0xFFFE0000:0x20000;0x20000:0x1000" \
  --mem "0x20000:0500000000000000;0x20008:0300000000000000" \
  programs/add/build/guest.pvm
```

Expected output: status HALT, `r7 = 8`.

To also dump the memory region after execution:

```bash
anan-as run --no-metadata --no-logs --gas 100000 \
  --regs "0xFFFF0000,0xFFFF0000,0,0,0,0,0,2,0x20000,0,0,0,0" \
  --pages "0xFFFE0000:0x20000;0x20000:0x1000" \
  --mem "0x20000:0500000000000000;0x20008:0300000000000000" \
  --dump "0x20000:64" \
  programs/add/build/guest.pvm
```

### Running the `hello` guest

`hello` expects `r7 = argc`, `r8 = argv pointer` where argv points to an I/O
buffer (tick count, keyboard state, console text). It writes console output
back into that same buffer.

```bash
# Tick 1, no keyboard input — writes "CoreMini sub-VM guest! Tick: 1" to console
anan-as run --no-metadata --no-logs --gas 100000 \
  --regs "0xFFFF0000,0xFFFF0000,0,0,0,0,0,0,0x20000,0,0,0,0" \
  --pages "0xFFFE0000:0x20000;0x20000:0x1000;0x10000:0x1000:r" \
  --mem "0x20000:0100000000;0x10000:$(xxd -p -c9999 programs/hello/build/guest.ro)" \
  --dump "0x2010a:80" \
  programs/hello/build/guest.pvm
```

The `--dump` at offset `0x2010a` (= `0x20000 + 266`) shows the console text
buffer where the guest writes its output.

### Disassembling a guest

```bash
anan-as disassemble --no-metadata programs/add/build/guest.pvm
```

### Register conventions

| Register | ABI Name | Convention |
|----------|----------|------------|
| r0 | SP | Stack pointer (set to top of stack) |
| r1 | RA/FP | Return address / frame pointer (set = SP) |
| r7 | a0 | First argument / return value |
| r8 | a1 | Second argument |
| r9 | a2 | Third argument |

### Key flags

| Flag | Description |
|------|-------------|
| `--no-metadata` | Input is a raw code blob (no metadata prefix) |
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
