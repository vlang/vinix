#include <vore.h>

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

int v_itoa(long value, byte radix, bool uppercase, bool unsig, bool unpad, char* out) {
    char* start = out;

    if (radix > 16) {
        return 0;
    } else if (radix == 16) {
        bool padded = false;
        int ctr = sizeof(long) * 2;

        if (value < 0 && !unsig) {
            *(out++) = '-';
        }

        while (ctr-- > 0) {
            byte n = (byte) (value >> (ctr * 4)) & 0xf;
            if (n == 0 && !padded) {
                continue;
            } else {
                padded = !unpad;
                *(out++) = (char) (n < 10 ? '0' + n : (uppercase ? 'A' : 'a') + n - 10);
            }
        }
        return out - start;
    } else {
        byte n;
        while (value > 0) {
            n = (byte) (value % radix);
            *(out++) = (char) (n < 10 ? '0' + n : (uppercase ? 'A' : 'a') + n - 10);
            value /= radix;
        }

        if (value < 0 && !unsig) {
            *(out++) = '-';
        }

        int len = out - start;
        for (int i = 0; i < len / 2; i++) {
            n = (byte) start[i];
            start[i] = start[len - i - 1];
            start[len - i - 1] = (char) n;
        }

        return len;
    }
}

#define V_STR_SLOT_NUM 8
#define V_STR_SLOT_SIZE 512
char str_internal_buf[V_STR_SLOT_NUM * V_STR_SLOT_SIZE];
int str_internal_slot = 0;

string v_sprintf(const char* fmt, ...) {
    va_list va;

    char* strptr = &str_internal_buf + (V_STR_SLOT_SIZE * str_internal_slot);
    memset(strptr, 0, V_STR_SLOT_SIZE);

    string str = {
        .str = strptr,
        .len = strlen(strptr)
    };

    if (str_internal_slot++ == V_STR_SLOT_NUM) {
        str_internal_slot = 0;
    }

    return str;
}

void memset(char* addr, char val, int count) {
    if (((uintptr_t) addr & 0x03) == 0 && (count & 0x03) == 0) {
        uint32_t n = val | (val << 8) | (val << 16) | (val << 24);
        for (int i = 0; i < count; i += 4) {
            *((uint32_t*)addr + i) = n;
        }
    } else if (((uintptr_t) addr & 0x01) == 0 && (count & 0x01) == 0) {
        uint16_t n = val | (val << 8);
        for (int i = 0; i < count; i += 2) {
            *((uint16_t*)addr + i) = n;
        }
    } else { // todo: faster handling of unaligned addresses?
        for (int i = 0; i < count; i++) {
            *(addr + i) = val;
        }
    }
}

void memput(byte* addr, int off, byte val) {
    addr[off] = val;
}