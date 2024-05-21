// symbol_table.c: Symbol table definitions.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

#include <stdint.h>
#include <symbols.h>

const struct symbol symbol_table[] = {
    {0xffffffffffffffff, ""}
};

const struct symbol *get_symbol_table(void) {
    return symbol_table;
}
