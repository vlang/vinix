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

string v_sprintf(char* fmt, va_list va) {
    byte buf[512];

    string str = {
        .str = &buf,
        .len = strlen(buf)
    };

    return str;
}

void memput(byte* addr, int off, byte val) {
    addr[off] = val;
}