#include <stddef.h>

#include "../flanterm-c/flanterm.h"

size_t flanterm_get_rows(struct flanterm_context *ctx) {
    return ctx->rows;
}

size_t flanterm_get_cols(struct flanterm_context *ctx) {
    return ctx->cols;
}