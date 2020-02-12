#ifndef _VRT_H_
#define _VRT_H_

#ifndef V_COMMIT_HASH
#define V_COMMIT_HASH "unknown"
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>

// V types
typedef int64_t i64;
typedef int16_t i16;
typedef int8_t i8;
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint16_t u16;
typedef uint8_t byte;
typedef uint32_t rune;
typedef float f32;
typedef double f64;
typedef unsigned char *byteptr;
typedef int *intptr;
typedef void *voidptr;

typedef struct string string;

struct string
{
	byte *str;
	int len;
};

string v_version();
string v_build_date();
void v_panic(string s);
void panic_debug(string s);
int strlen(byte *s);
string tos(byte *s, int len);
string tos2(byte *s);
string tos3(char *s);

void memset(char *addr, char val, int count);
void memset16(u16 *addr, u16 val, int count);
void memset32(u32 *addr, u32 val, int count);
void memcpy(void *desti, void *srci, int length);
void memput(byte *addr, int off, byte val);

inline char atomic_load(void *ptr);
inline void atomic_store(void *ptr, char val);

string v_sprintf(const char *fmt, ...);

#define _STR(...) v_sprintf(__VA_ARGS__)
#define EMPTY_STRUCT_DECLARATION void *whatever

#endif
