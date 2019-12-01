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

const char* v_info_commit_hash = V_COMMIT_HASH;
const char* v_info_build_date = __DATE__ " " __TIME__;

string v_version() {
    return tos3(v_info_commit_hash);
}

string v_build_date() {
    return tos3(v_info_build_date);
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

int v_itoa(uint64_t value, byte radix, bool uppercase, bool unsig, bool unpad, char* out, unsigned int idx, unsigned int max_idx) {
    unsigned int len = 0;
    char buf[32] = {0};
            
    if (radix > 16) {
        return 0;
    } else if (radix == 16) {
        bool padded = false;
        int ctr = sizeof(uint64_t) * 2;

        if (value < 0 && !unsig) {
            buf[len++] = '-';
        }

        while (ctr-- > 0) {
            byte n = (byte) (value >> (ctr * 4)) & 0xf;
            if (n == 0 && !padded) {
                continue;
            } else {
                padded = !unpad;
                buf[len++] = (char) (n < 10 ? '0' + n : (uppercase ? 'A' : 'a') + n - 10);
            }
        }
        
        if (len == 0) {
            buf[0] = '0';
            len = 1;
        } else if (len != 32) {
            buf[len] = 0;
        }

        int cnt = (max_idx - idx) < len ? (max_idx - idx) : len;
        
        for (int i = 0; i < cnt; ++i) {
            out[i] = buf[i];
        }

        return cnt;
    } else {
        byte n = 0;

        while (value > 0) {
            n = (byte) (value % radix);
            buf[len++] = (char) (n < 10 ? '0' + n : (uppercase ? 'A' : 'a') + n - 10);
            value /= radix;
        }

        if (value < 0 && !unsig) {
            buf[len++] = '-';
        }

        if (len == 0) {
            buf[0] = '0';
            len = 1;
        } else if (len != 32) {
            buf[len] = 0;
        }

        int cnt = (max_idx - idx) < len ? (max_idx - idx) : len;

        for (int i = 0; i < cnt; ++i) {
            out[i] = buf[cnt - i - 1];
        }

        return cnt;
    }
}

#define V_STR_SLOT_NUM 8
#define V_STR_SLOT_SIZE 1024
#define V_STR_PUT(C) if (idx < V_STR_SLOT_SIZE) { strptr[idx++] = C; }

char str_internal_buf[V_STR_SLOT_NUM * V_STR_SLOT_SIZE];
int str_internal_slot = 0;

//#define _E9_DBG_
#ifdef _E9_DBG_
void printn(char x, int num) {
    byte port = 0xe9;
    outb(port, x);
    outb(port, ' ');

    int ctr = sizeof(int) * 2;
    while (ctr-- > 0) {
        byte n = (byte) (num >> (ctr * 4)) & 0xf;
        outb(port, (char) (n < 10 ? '0' + n : ('a') + n - 10));
    }
    outb(port, '\n');
}
#endif

string v_sprintf(const char* fmt, ...) {
    va_list va;
    unsigned int idx = 0;
    char* strptr = str_internal_buf + (V_STR_SLOT_SIZE * str_internal_slot);

    va_start(va, fmt);

    memset(strptr, 0, V_STR_SLOT_SIZE);

    char c;
    for (int i = 0; i < V_STR_SLOT_SIZE - 1; ++i) {
        c = fmt[i];
        if (c == 0) {
            break;
        } else if (c == '%') {
next:       ;
            c = fmt[++i];
            switch (c) {
                case 0:
                    goto end;
                case 'd':
                case 'u':
                    idx += v_itoa((long) va_arg(va, unsigned int), 10, false, (c == 'u'), true, 
                            strptr + idx, idx, V_STR_SLOT_SIZE - 1);
                    break;
                case 'p':
                    V_STR_PUT('0');
                    V_STR_PUT('x');
                case 'x':
                case 'X':
                    idx += v_itoa((long) va_arg(va, unsigned int), 16, (c == 'X'), false, true, 
                            strptr + idx, idx, V_STR_SLOT_SIZE - 1);
                    break;
                case 's': {
                    char* ptr = va_arg(va, char*);
                    int len = strlen((byte*) ptr);
                    for (int j = 0; j < len; j++) {
                        V_STR_PUT(ptr[j]);
                    }
                    break;
                }
                case 'l':
                    goto next;
                    break;
                case '.': {
                    c = fmt[++i];
                    if (i < V_STR_SLOT_SIZE && c == '*') {
                        unsigned int slen = va_arg(va, unsigned int);
                        c = fmt[++i];
                        if (i < V_STR_SLOT_SIZE && c == 's') {
                            char* ptr = va_arg(va, char*);
                            for (int j = 0; j < slen; j++) {
                                V_STR_PUT(ptr[j]);
                            }
                        }
                    }
                    break;
                }
                case '%': {
                    V_STR_PUT('%');
                    break;
                }
                default:
                    break;
            }
        } else {
            V_STR_PUT(c);
        }
    }
end: ;
    string str = {
        .str = strptr,
        .len = strlen(strptr)
    };

    if (str_internal_slot++ == V_STR_SLOT_NUM) {
        str_internal_slot = 0;
    }

    return str;
}

void memset(char* s, char c, int sz) {
    uint32_t* p;
    uint32_t x = c & 0xff;
    byte xx = c & 0xff;
    byte* pp = (byte*)s;
    uint32_t tail;

    while (((uint32_t)pp & 3) && sz--) {
        *pp++ = xx;
    }

    p = (uint32_t*)pp;

    tail = sz & 3;

    x |= x << 8;
    x |= x << 16;

    sz >>= 2;

    while (sz--) {
        *p++ = x;
    }

    pp = (byte*) p;
    while (tail--) {
        *pp++ = xx;
    }
}

void memput(byte* addr, int off, byte val) {
    addr[off] = val;
}