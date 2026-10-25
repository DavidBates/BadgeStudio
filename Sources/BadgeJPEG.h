#include <stddef.h>
#include <stdint.h>
uint8_t *badge_jpeg_encode(const uint8_t *rgba, int width, int height, int quality, size_t *length);
void badge_jpeg_free(uint8_t *bytes);
