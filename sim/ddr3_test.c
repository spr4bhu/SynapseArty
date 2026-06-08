// DDR3 read/write bring-up test for the Arty A7-35T (arty_ddr3_top).
// The core is held in reset until MIG calibration completes, so by the time main
// runs DDR3 is ready. We write patterns to the DDR3 window, read them back, and
// report each result over UART at 115200 baud (83.33 MHz / 723).

#define UART_BASE     0x20000000
#define UART_DATA     (UART_BASE + 0x00)
#define UART_STATUS   (UART_BASE + 0x04)
#define UART_CONTROL  (UART_BASE + 0x08)
#define UART_STATUS_TX_BUSY (1 << 2)

#define DDR3_BASE     0x80000000u

static inline void     wr(unsigned a, unsigned v) { *(volatile unsigned *)a = v; }
static inline unsigned rd(unsigned a)             { return *(volatile unsigned *)a; }

static void uart_putc(char c) {
    while (rd(UART_STATUS) & UART_STATUS_TX_BUSY) { }
    wr(UART_DATA, (unsigned char)c);
}
static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
static void uart_hex(unsigned v) {
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc("0123456789ABCDEF"[(v >> i) & 0xF]);
}

// Four addresses: two lanes of one 128-bit line (exercises the byte mask), the
// next line, and a far address (exercises a higher row/bank).
static const unsigned ADDRS[]    = { 0x00000000, 0x00000004, 0x00000010, 0x00100000 };
static const unsigned PATTERNS[] = { 0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xA5A5A5A5 };
#define N 4

int main(void) {
    wr(UART_CONTROL, 1);
    uart_puts("\r\nDDR3 bring-up test\r\n");

    // Write phase
    for (int i = 0; i < N; i++)
        wr(DDR3_BASE + ADDRS[i], PATTERNS[i]);

    // Read-back / compare phase
    int fails = 0;
    for (int i = 0; i < N; i++) {
        unsigned got = rd(DDR3_BASE + ADDRS[i]);
        uart_puts("  ["); uart_hex(DDR3_BASE + ADDRS[i]); uart_puts("] = ");
        uart_hex(got);
        if (got == PATTERNS[i]) {
            uart_puts("  OK\r\n");
        } else {
            uart_puts("  FAIL exp "); uart_hex(PATTERNS[i]); uart_puts("\r\n");
            fails++;
        }
    }

    uart_puts(fails ? "DDR3 FAIL\r\n" : "DDR3 OK\r\n");
    while (1) { }
    return 0;
}
