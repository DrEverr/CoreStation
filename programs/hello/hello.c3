// ==========================================================================
// CoreMini Guest: Hello Console (sub-VM version)
// ==========================================================================
//
// This is a MINIMAL guest program that runs as a sub-VM inside CoreStation.
// It does NOT have JAM service entry points (no refine/accumulate).
//
// Memory layout (set up by CoreMini via host_pages + host_poke):
//   argv + 0:    tick_count (uint LE)
//   argv + 4:    kbd_key_count (ushort LE)
//   argv + 6:    kbd_keys[256]
//   argv + 262:  con_cursor_x (ushort LE)
//   argv + 264:  con_cursor_y (ushort LE)
//   argv + 266:  con_text[2000]
//   argv + 2266: con_dirty (char)
//
// The guest runs to completion (HALT). CoreStation peeks the
// modified memory regions to capture output.
//
// ==========================================================================
module guest_hello;

// ==========================================================================
// Memory-mapped I/O addresses (must match coremini.c3 layout)
// ==========================================================================

const uint TICK_COUNT = 0;       // uint
const uint KBD_COUNT  = 4;       // ushort
const uint KBD_KEYS   = 6;       // char[256]
const uint CON_CX     = 262;     // ushort
const uint CON_CY     = 264;     // ushort
const uint CON_TEXT   = 266;     // char[2000]
const uint CON_DIRTY  = 2266;    // char

const uint CON_COLS = 80;
const uint CON_ROWS = 25;

// ==========================================================================
// Raw memory access (sub-VM has no host calls, just direct memory)
// ==========================================================================

fn char peek8(uint addr) @inline
{
    return *(char*)((usz)addr);
}

fn void poke8(uint addr, char val) @inline
{
    *(char*)((usz)addr) = val;
}

fn ushort peek16(uint addr) @inline
{
    char lo = peek8(addr);
    char hi = peek8(addr + 1);
    return (ushort)lo | ((ushort)hi << 8);
}

fn void poke16(uint addr, ushort val) @inline
{
    poke8(addr, (char)val);
    poke8(addr + 1, (char)(val >> 8));
}

fn uint peek32(uint addr) @inline
{
    ushort lo = peek16(addr);
    ushort hi = peek16(addr + 2);
    return (uint)lo | ((uint)hi << 16);
}

fn void poke32(uint addr, uint val) @inline
{
    poke16(addr, (ushort)val);
    poke16(addr + 2, (ushort)(val >> 16));
}

// ==========================================================================
// Console helpers
// ==========================================================================

fn void con_putch_at(uint addr, ushort col, ushort row, char ch)
{
    if (col >= CON_COLS || row >= CON_ROWS) { return; }
    uint off = (uint)row * CON_COLS + (uint)col;
    poke8(addr + CON_TEXT + off, ch);
    poke8(addr + CON_DIRTY, 1);
}

fn void con_print_at(uint addr, ushort col, ushort row, char* str)
{
    ushort x = col;
    for (usz i = 0; str[i] != 0; i++) {
        if (x >= CON_COLS) { break; }
        con_putch_at(addr, x, row, str[i]);
        x++;
    }
}

fn void con_print_num(uint addr, ushort col, ushort row, uint val)
{
    if (val == 0) { con_putch_at(addr, col, row, '0'); return; }
    char[10] digits;
    int count = 0;
    uint tmp = val;
    while (tmp > 0 && count < 10) {
        digits[count] = (char)('0' + (char)(tmp % 10));
        tmp /= 10;
        count++;
    }
    ushort x = col;
    for (int i = count - 1; i >= 0; i--) {
        con_putch_at(addr, x, row, digits[i]);
        x++;
    }
}

// ==========================================================================
// Entry point — called by CoreMini via host_invoke
// ==========================================================================

fn ulong guest_main(ulong argc, uint argv) @export("guest_main")
{
    // Read tick count from persistent state
    uint tick = peek32(argv + TICK_COUNT);

    // Read keyboard input
    ushort key_count = peek16(argv + KBD_COUNT);

    // Clear first two rows
    for (ushort col = 0; col < CON_COLS; col++) {
        con_putch_at(argv, col, 0, ' ');
        con_putch_at(argv, col, 1, ' ');
    }

    // Print hello message with tick count
    con_print_at(argv, 0, 0, "CoreMini sub-VM guest! Tick: ");
    con_print_num(argv, 28, 0, tick);

    // Echo any keys
    if (key_count > 0) {
        con_print_at(argv, 0, 1, "Keys: ");
        ushort x = 6;
        for (ushort i = 0; i < key_count && x < CON_COLS; i++) {
            char key = peek8(argv + KBD_KEYS + (uint)i);
            con_putch_at(argv, x, 1, key);
            x++;
        }
    }

    // Increment tick count
    tick++;
    return (ulong)tick;
}
