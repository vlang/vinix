// SPDX-License-Identifier: GPL-2.0-or-later
// The desktop build compiles V's generated C with its own Clang command, so
// decoder configuration belongs in an included header rather than V #flags.
#ifndef VINIX_QUICKLOOK_STB_H
#define VINIX_QUICKLOOK_STB_H
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF
#define STBI_NO_STDIO
#define STBI_NO_SIMD
#include "stb_image.h"
#endif
