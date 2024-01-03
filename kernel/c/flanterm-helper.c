#include <stddef.h>
#include <flanterm/flanterm.h>

size_t flanterm_get_rows(struct flanterm_context *ctx) {
    return ctx->rows;
}

size_t flanterm_get_cols(struct flanterm_context *ctx) {
    return ctx->cols;
}

void flanterm_set_callback(struct flanterm_context *ctx, void *callback) {
    ctx->callback = callback;
}
