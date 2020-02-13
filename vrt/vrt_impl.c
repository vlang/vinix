#include <vrt.h>

void v_panic(string s)
{
    // to-do
}

void panic_debug(string s)
{
    // to-do
}

int strlen(byte *s)
{
    int i = 0;

    while (s[i] != 0)
    {
        i++;
    }

    return i;
}

const char *v_info_commit_hash = V_COMMIT_HASH;
const char *v_info_build_date = __DATE__ " " __TIME__;

string v_version()
{
    return tos3(v_info_commit_hash);
}

string v_build_date()
{
    return tos3(v_info_build_date);
}

string tos(byte *s, int len)
{
    string str = {
        .len = len,
        .str = s
    };
    return str;
}

string tos2(byte *s)
{
    string str = {
        .len = strlen(s),
        .str = s
    };
    return str;
}

string tos3(char *s)
{
    string str = {
        .len = strlen((byte *)s),
        .str = (byte *)s
    };
    return str;
}

int v_itoa(uint64_t value, byte radix, bool uppercase, bool unsig, bool unpad, char *out, unsigned int idx, unsigned int max_idx)
{
    unsigned int len = 0;
    char buf[32] = {0};

    if (radix > 16)
    {
        return 0;
    }
    else
    {
        byte n = 0;

        while (value > 0)
        {
            n = (byte)(value % radix);
            buf[len++] = (char)(n < 10 ? '0' + n : (uppercase ? 'A' : 'a') + n - 10);
            value /= radix;
        }

        if (value < 0 && !unsig)
        {
            buf[len++] = '-';
        }

        if (len == 0)
        {
            buf[0] = '0';
            len = 1;
        }
        else if (len != 32)
        {
            buf[len] = 0;
        }

        int cnt = (max_idx - idx) < len ? (max_idx - idx) : len;

        for (int i = 0; i < cnt; ++i)
        {
            out[i] = buf[cnt - i - 1];
        }

        return cnt;
    }
}

#define V_STR_SLOT_NUM 16
#define V_STR_SLOT_SIZE 1024
#define V_STR_PUT(C)           \
    if (idx < V_STR_SLOT_SIZE) \
    {                          \
        strptr[idx++] = C;     \
    }

char str_internal_buf[V_STR_SLOT_NUM * V_STR_SLOT_SIZE];
int str_internal_slot = 0;

string v_sprintf(const char *fmt, ...)
{
    va_list va;
    unsigned int idx = 0;
    char *strptr = str_internal_buf + (V_STR_SLOT_SIZE * str_internal_slot);

    va_start(va, fmt);

    memset(strptr, 0, V_STR_SLOT_SIZE);

    char c;
    for (int i = 0; i < V_STR_SLOT_SIZE - 1; ++i)
    {
        c = fmt[i];
        if (c == 0)
        {
            break;
        }
        else if (c == '%')
        {
        next:;
            c = fmt[++i];
            switch (c)
            {
            case 0:
                goto end;
            case 'd':
            case 'u':
                idx += v_itoa((long)va_arg(va, unsigned long), 10, false, (c == 'u'), true,
                              strptr + idx, idx, V_STR_SLOT_SIZE - 1);
                break;
            case 'p':
                V_STR_PUT('0');
                V_STR_PUT('x');
            case 'x':
            case 'X':
                idx += v_itoa((long)va_arg(va, unsigned long), 16, (c == 'X'), false, true,
                              strptr + idx, idx, V_STR_SLOT_SIZE - 1);
                break;
            case 's':
            {
                char *ptr = va_arg(va, char *);
                int len = strlen((byte *)ptr);
                for (int j = 0; j < len; j++)
                {
                    V_STR_PUT(ptr[j]);
                }
                break;
            }
            case 'l':
                goto next;
                break;
            case '.':
            {
                c = fmt[++i];
                if (i < V_STR_SLOT_SIZE && c == '*')
                {
                    unsigned int slen = va_arg(va, unsigned int);
                    c = fmt[++i];
                    if (i < V_STR_SLOT_SIZE && c == 's')
                    {
                        char *ptr = va_arg(va, char *);
                        for (int j = 0; j < slen; j++)
                        {
                            V_STR_PUT(ptr[j]);
                        }
                    }
                }
                break;
            }
            case '%':
            {
                V_STR_PUT('%');
                break;
            }
            default:
                break;
            }
        }
        else
        {
            V_STR_PUT(c);
        }
    }
end:;
    string str = {
        .len = strlen(strptr),
        .str = strptr
    };

    if (str_internal_slot++ == V_STR_SLOT_NUM)
    {
        str_internal_slot = 0;
    }

    return str;
}

const char *strstr(const char *in, const char *substring)
{
    int in_sz = strlen(in);
    int sub_sz = strlen(substring);

    if (*substring == '\0' || sub_sz == 0)
    {
        return in;
    }

    if (*in == '\0' || sub_sz > in_sz)
    {
        return 0;
    }

    int next[sub_sz + 1];

    for (int i = 0; i < sub_sz + 1; i++)
    {
        next[i] = 0;
    }

    for (int i = 1; i < sub_sz; i++)
    {
        int j = next[i + 1];

        while (j > 0 && substring[j] != substring[i])
        {
            j = next[j];
        }

        if (j > 0 || substring[j] == substring[i])
        {
            next[i + 1] = j + 1;
        }
    }

    for (int i = 0, j = 0; i < in_sz; i++)
    {
        if (*(in + i) == *(substring + j))
        {
            if (++j == sub_sz)
            {
                return (in + i - j + 1);
            }
        }
        else if (j > 0)
        {
            j = next[j];
            i--; // // since i will be incremented in next iteration
        }
    }

    return 0;
}

void memset16(u16 *s, u16 c, int sz)
{
    for (int i = 0; i < sz; i++)
    {
        s[i] = c;
    }
}

void memset32(u32 *s, u32 c, int sz)
{
    for (int i = 0; i < sz; i++)
    {
        s[i] = c;
    }
}

void memset(char *s, char c, int sz)
{
    uint32_t *p;
    uint32_t x = c & 0xff;
    byte xx = c & 0xff;
    byte *pp = (byte *)s;
    uint32_t tail;

    while (((uint32_t)pp & 3) && sz--)
    {
        *pp++ = xx;
    }

    p = (uint32_t *)pp;

    tail = sz & 3;

    x |= x << 8;
    x |= x << 16;

    sz >>= 2;

    while (sz--)
    {
        *p++ = x;
    }

    pp = (byte *)p;
    while (tail--)
    {
        *pp++ = xx;
    }
}

void memcpy(void *desti, void *srci, int length)
{
    if (length == 0 || desti == srci)
    {
        return desti;
    }

    if ((u64)desti < (u64)srci)
    {
        int n = (length + 7) / 8;
        char *dest = desti, *src = srci;
        switch (length % 8)
        {
        case 0:
            do
            {
                *(dest++) = *(src++);
            case 7:
                *(dest++) = *(src++);
            case 6:
                *(dest++) = *(src++);
            case 5:
                *(dest++) = *(src++);
            case 4:
                *(dest++) = *(src++);
            case 3:
                *(dest++) = *(src++);
            case 2:
                *(dest++) = *(src++);
            case 1:
                *(dest++) = *(src++);
            } while (--n > 0);
        }
    }
    else
    {
        int n = (length + 7) / 8;
        char *dest = desti + length, *src = srci + length;
        switch (length % 8)
        {
        case 0:
            do
            {
                *(--dest) = *(--src);
            case 7:
                *(--dest) = *(--src);
            case 6:
                *(--dest) = *(--src);
            case 5:
                *(--dest) = *(--src);
            case 4:
                *(--dest) = *(--src);
            case 3:
                *(--dest) = *(--src);
            case 2:
                *(--dest) = *(--src);
            case 1:
                *(--dest) = *(--src);
            } while (--n > 0);
        }
    }
}

void memput(byte *addr, int off, byte val)
{
    addr[off] = val;
}

void memputd(u32 *addr, int off, u32 val)
{
    addr[off] = val;
}

inline static char atomic_load(void *ptr)
{
    return __atomic_load_n((char *)ptr, __ATOMIC_RELAXED);
}

inline static void atomic_store(void *ptr, char val)
{
    __atomic_store_n((char *)ptr, val, __ATOMIC_RELAXED);
}