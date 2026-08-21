// stb_image shim: compiles the implementation once, exports a thin decode
// surface to Zig. Decode happens on the widget's art worker thread, never
// the render thread. Output is always RGBA (4 channels).
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#include "../vendor/stb_image.h"

int kidul_img_decode(const char *path, unsigned char **out_rgba, int *out_w, int *out_h) {
    int w = 0, h = 0, n = 0;
    unsigned char *px = stbi_load(path, &w, &h, &n, 4);
    if (!px) return -1;
    *out_rgba = px;
    *out_w = w;
    *out_h = h;
    (void)n;
    return 0;
}

void kidul_img_free(unsigned char *px) {
    if (px) stbi_image_free(px);
}
