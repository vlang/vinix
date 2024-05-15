#pragma once

#include <stddef.h>
#include <flanterm/flanterm.h>

size_t flanterm_get_rows(struct flanterm_context *ctx);
size_t flanterm_get_cols(struct flanterm_context *ctx);
void flanterm_set_callback(struct flanterm_context *ctx, void *callback);
