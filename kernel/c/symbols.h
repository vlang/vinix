// symbols.h: External linker symbols for use.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

#ifndef _SYMBOLS_H
#define _SYMBOLS_H

#include <stdint.h>

extern char interrupt_thunks[];

struct symbol {
	uint64_t address;
	char *string;
};

struct symbol *get_symbol_table(void);

#endif
