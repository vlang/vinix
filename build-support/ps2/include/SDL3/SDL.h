/* SPDX-License-Identifier: MIT
 * The core's software rasterizer only uses these presentation types. Vinix
 * reads the rasterized GS framebuffer directly and never creates SDL objects.
 */
#ifndef VINIX_PS2_SDL_TYPES_H
#define VINIX_PS2_SDL_TYPES_H
typedef struct SDL_Window SDL_Window;
typedef struct SDL_GPUDevice SDL_GPUDevice;
typedef struct SDL_GPUCommandBuffer SDL_GPUCommandBuffer;
typedef struct SDL_GPURenderPass SDL_GPURenderPass;
typedef struct SDL_Rect { int x, y, w, h; } SDL_Rect;
static inline int SDL_GetWindowSize(SDL_Window *window, int *w, int *h) {
    (void)window;
    *w = 640;
    *h = 480;
    return 1;
}
#endif
