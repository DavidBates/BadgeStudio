#include "BadgeJPEG.h"
#include <stdlib.h>
#include <string.h>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#include "../Vendor/stb_image_write.h"
typedef struct { uint8_t *data; size_t length; int failed; } Output;
static void append_bytes(void *context, void *data, int length) {
    Output *out = context;
    if (out->failed || length <= 0) return;
    size_t new_length = out->length + (size_t)length;
    if (new_length < out->length) { out->failed = 1; return; }
    void *next = realloc(out->data, new_length);
    if (!next) { out->failed = 1; return; }
    out->data = next;
    memcpy(out->data + out->length, data, (size_t)length);
    out->length = new_length;
}
uint8_t *badge_jpeg_encode(const uint8_t *rgba, int width, int height, int quality, size_t *length) {
    *length = 0;
    if (!rgba || width <= 0 || height <= 0) return NULL;
    Output out = {0};
    int ok = stbi_write_jpg_to_func(append_bytes, &out, width, height, 4, rgba, quality);
    if (!ok || out.failed) { free(out.data); return NULL; }
    *length = out.length;
    return out.data;
}
void badge_jpeg_free(uint8_t *bytes) { free(bytes); }
