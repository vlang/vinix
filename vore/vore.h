#ifndef _VORE_H_
#define _VORE_H_ 

#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>

// V types
typedef uint8_t byte;

typedef struct string string;

struct string {
	byte* str;
	int len;
};

void v_panic(string s);
void panic_debug(string s);
int strlen(byte* s);
string tos(byte* s, int len);
string tos2(byte* s);
string tos3(char* s);

void memset(char* addr, char val, int count);
void memput(byte* addr, int off, byte val);

string v_sprintf(const char* fmt, ...);
#define _STR(...) v_sprintf(__VA_ARGS__)

#endif
