/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IOS_TEXT_H
#define VINIX_IOS_TEXT_H
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdint.h>
static int ios_ft_init(void **library) { return FT_Init_FreeType((FT_Library *)library); }
static int ios_ft_open(void *library, const char *path, long index, void **face) {
    return FT_New_Face(library, path, index, (FT_Face *)face);
}
/* Accessors keep FreeType's platform-dependent C structs out of the Darwin ABI.
 * Font selection, layout, clipping and bitmap compositing live in V. */
static long ios_ft_face_count(void *face) { return ((FT_Face)face)->num_faces; }
static int ios_ft_render(void *face) { return FT_Render_Glyph(((FT_Face)face)->glyph, FT_RENDER_MODE_NORMAL); }
static long ios_ft_traits(void *face) {
    FT_Long flags = ((FT_Face)face)->style_flags;
    return (flags & FT_STYLE_FLAG_ITALIC ? 1 : 0) | (flags & FT_STYLE_FLAG_BOLD ? 2 : 0);
}
static const char *ios_ft_family(void *face) { return ((FT_Face)face)->family_name; }
static const char *ios_ft_style(void *face) { return ((FT_Face)face)->style_name; }
static void ios_ft_metrics(void *face, int64_t *output) {
    FT_Size_Metrics *m = &((FT_Face)face)->size->metrics;
    output[0] = m->ascender; output[1] = m->descender; output[2] = m->height;
}
static unsigned char *ios_ft_glyph(void *face, int64_t *output) {
    FT_GlyphSlot g = ((FT_Face)face)->glyph;
    output[0] = g->advance.x; output[1] = g->bitmap_left; output[2] = g->bitmap_top;
    output[3] = g->bitmap.width; output[4] = g->bitmap.rows; output[5] = g->bitmap.pitch;
    output[6] = g->bitmap.pixel_mode;
    return g->bitmap.buffer;
}
static long ios_ft_kern(void *face, unsigned left, unsigned right) {
    FT_Vector delta = {0, 0};
    return FT_Get_Kerning(face, left, right, FT_KERNING_DEFAULT, &delta) ? 0 : delta.x;
}
#endif
