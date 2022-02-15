#ifndef __STDINT_H__
#define __STDINT_H__

typedef __UINT8_TYPE__ uint8_t;
typedef __UINT16_TYPE__ uint16_t;
typedef __UINT32_TYPE__ uint32_t;
typedef __UINT64_TYPE__ uint64_t;

typedef __INT8_TYPE__ int8_t;
typedef __INT16_TYPE__ int16_t;
typedef __INT32_TYPE__ int32_t;
typedef __INT64_TYPE__ int64_t;

typedef __UINTPTR_TYPE__ uintptr_t;
typedef __INTPTR_TYPE__ intptr_t;

typedef __UINTMAX_TYPE__ uintmax_t;
typedef __INTMAX_TYPE__ intmax_t;

#define INT8_MAX __INT8_MAX__
#define INT16_MAX __INT16_MAX__
#define INT32_MAX __INT32_MAX__
#define INT64_MAX __INT64_MAX__

#define UINT8_MAX __UINT8_MAX__
#define UINT16_MAX __UINT16_MAX__
#define UINT32_MAX __UINT32_MAX__
#define UINT64_MAX __UINT64_MAX__

#define INT8_MIN (-INT8_MAX - 1)
#define INT16_MIN (-INT16_MAX - 1)
#define INT32_MIN (-INT32_MAX - 1)
#define INT64_MIN (-INT64_MAX - 1)

#define UINTPTR_MAX __UINTPTR_MAX__
#define INTPTR_MAX __INTPTR_MAX__
#define INTPTR_MIN (-INTPTR_MAX - 1)

#define UINTMAX_MAX __UINTMAX_MAX__
#define INTMAX_MAX __INTMAX_MAX__
#define INTMAX_MIN (-INTMAX_MAX - 1)

#define PTRDIFF_MAX __PTRDIFF_MAX__
#define PTRDIFF_MIN (-PTRDIFF_MAX - 1)

#define SIZE_MAX __SIZE_MAX__

#define WCHAR_MAX __WCHAR_MAX__
#define WCHAR_MIN __WCHAR_MIN__

#define WINT_MAX __WINT_MAX__
#define WINT_MIN __WINT_MIN__

#endif
