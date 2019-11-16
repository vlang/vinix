#include <stdint.h>

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
void memput(byte* addr, int off, byte val);
void vrt_main();

void v_panic(string s) {
    // to-do
}

void panic_debug(string s) {
    // to-do
}

int strlen(byte* s) {
    int i = 0;
    
    while (s[i] != 0) {
        i++;
    }

    return i;
}

string tos(byte* s, int len) {
    string str = {
        .str = s,
        .len = len
    };
    return str;
}

string tos2(byte* s) {
    string str = {
        .str = s,
        .len = strlen(s)
    };
    return str;
}

string tos3(char* s) {
    string str = {
        .str = (byte*) s,
        .len = strlen((byte*) s)
    };
    return str;
}

void memput(byte* addr, int off, byte val) {
    addr[off] = val;
}

void sys__init_consts();
void sys__kmain();

void vrt_main() {
    sys__init_consts();
    sys__kmain();
}