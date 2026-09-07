#ifndef VINIX_LWIP_ARCH_CC_H
#define VINIX_LWIP_ARCH_CC_H

#include <stdint.h>

#define BYTE_ORDER LITTLE_ENDIAN
#define LWIP_NO_INTTYPES_H 1
#define X8_F "02x"
#define U16_F "u"
#define S16_F "d"
#define X16_F "04x"
#define U32_F "u"
#define S32_F "d"
#define X32_F "08x"
#define SZT_F "lu"

#define LWIP_PLATFORM_DIAG(x) do { } while (0)
void vinix_lwip_assert(const char *message, const char *file, int line);
#define LWIP_PLATFORM_ASSERT(message) \
    vinix_lwip_assert((message), __FILE__, __LINE__)

uint32_t vinix_lwip_rand(void);
#define LWIP_RAND() vinix_lwip_rand()

#define PACK_STRUCT_BEGIN
#define PACK_STRUCT_END
#define PACK_STRUCT_STRUCT __attribute__((packed))
#define PACK_STRUCT_FIELD(x) x

#endif
