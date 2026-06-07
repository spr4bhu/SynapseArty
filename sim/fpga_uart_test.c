// Standalone UART banner test for FPGA bring-up on the Arty A7-35T.
// Transmits a known string forever at the default 115200 baud (50 MHz / 434),
// so a serial terminal can be attached at any time after programming.

#define UART_BASE     0x20000000
#define UART_DATA     (UART_BASE + 0x00)
#define UART_STATUS   (UART_BASE + 0x04)
#define UART_CONTROL  (UART_BASE + 0x08)

#define UART_STATUS_TX_BUSY (1 << 2)

static inline void   wr(unsigned a, unsigned v) { *(volatile unsigned *)a = v; }
static inline unsigned rd(unsigned a)            { return *(volatile unsigned *)a; }

static void uart_putc(char c) {
    while (rd(UART_STATUS) & UART_STATUS_TX_BUSY) { }  // wait until not busy
    wr(UART_DATA, (unsigned char)c);
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

int main(void) {
    wr(UART_CONTROL, 1);  // enable TX (already default, set explicitly)
    while (1) {
        uart_puts("SYNAPSE32 ON ARTY OK\r\n");
        // crude delay between banners so the output is readable
        for (volatile unsigned i = 0; i < 200000u; i++) { }
    }
    return 0;
}
