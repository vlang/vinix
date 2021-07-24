#include <stdint.h>

struct symbol {
	uint64_t address;
	char *string;
};

__attribute__((section(".symbol_table")))
struct symbol symbol_table[] = {
    {0xffffffffffffffff, ""}
};

struct symbol *get_symbol_table(void) {
    return symbol_table;
}
