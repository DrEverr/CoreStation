// ==========================================================================
// CoreMini Guest: Hello Console
// ==========================================================================
//
// SPI entry: guest_main(argv, argc)
//   argv (r7) = pointer to input args (read-only)
//   argc (r8) = length in bytes
//
// Input layout (at argv):
//   +0:  tick_count (uint LE)
//   +4:  text to print (ASCII bytes, argc-4 chars)
//
// Output: console buffer on the stack, tick+1 returned in r7.
//
// ==========================================================================
module guest_hello;

const uint CON_COLS = 80;
const uint CON_ROWS = 25;
const uint CON_SIZE = CON_COLS * CON_ROWS;
char[CON_SIZE] con;

// ==========================================================================
// Console — stack-allocated buffer
// ==========================================================================

fn void con_print_char(char* con, ushort col, ushort row, char ch)
{
    if (col >= CON_COLS || row >= CON_ROWS) return;
    con[(uint)row * CON_COLS + (uint)col] = ch;
}

fn void con_print(char* con, ushort col, ushort row, char* str)
{
    ushort x = col;
    for (usz i = 0; str[i] != 0; i++) {
        if (x >= CON_COLS) break;
        con_print_char(con, x, row, str[i]);
        x++;
    }
}

fn void con_print_num(char* con, ushort col, ushort row, uint val)
{
    if (val == 0) { con_print_char(con, col, row, '0'); return; }
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
        con_print_char(con, x, row, digits[i]);
        x++;
    }
}

// ==========================================================================
// Entry point
// ==========================================================================

fn ulong guest_main(char* argv, ulong argc) @export("guest_main")
{
    // Read tick from argv (read-only)
    uint tick = *(uint*)argv;

    // "Empty" our console
    for (uint i = 0; i < CON_SIZE; i++) con[i] = ' ';

    // Row 0: hello message with tick
    con_print(&con, 0, 0, "Hello from PVM! Tick: ");
    con_print_num(&con, 21, 0, tick);

    // Row 1: echo the text from args
    if (argc > 4) {
        con_print(&con, 0, 1, "Text: ");
        ushort x = 6;
        for (ulong i = 4; i < argc && x < CON_COLS; i++) {
            con_print_char(&con, x, 1, argv[i]);
            x++;
        }
    }

    return (ulong)(tick + 1);
}
