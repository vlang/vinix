/* Test-only x86-64/glibc crash observer. It reports the real saved context,
 * then returns to the original fault with SIG_DFL restored by SA_RESETHAND.
 * No game symbols, signal APIs, or crash-reporting APIs are replaced. */
extern long write(int, const void *, unsigned long);
extern int open(const char *, int, ...);
extern long read(int, void *, unsigned long);
extern int close(int);
extern char *getenv(const char *);
extern int unsetenv(const char *);
extern int raise(int);
extern int *__errno_location(void);

struct action {
    void (*handler)(int, void *, void *);
    unsigned long mask[16];
    int flags;
    void (*restorer)(void);
};
extern int sigaction(int, const struct action *, struct action *);
struct context {
    unsigned long flags;
    void *link;
    void *stack_pointer;
    int stack_flags;
    unsigned long stack_size;
    unsigned long registers[23];
};
struct signal_info {
    int number, error, code, padding;
    unsigned long address;
};
_Static_assert(sizeof(struct action) == 152, "glibc x86-64 sigaction ABI");
_Static_assert(__builtin_offsetof(struct action, flags) == 136, "sigaction flags");
_Static_assert(__builtin_offsetof(struct context, registers) == 40, "ucontext registers");
_Static_assert(__builtin_offsetof(struct signal_info, address) == 16, "siginfo address");

struct text_buffer {
    char *data;
    unsigned long capacity, length;
};

static void append(struct text_buffer *buffer, const char *text)
{
    while (*text && buffer->length < buffer->capacity)
        buffer->data[buffer->length++] = *text++;
}

static void append_hex(struct text_buffer *buffer, unsigned long number)
{
    char text[] = "0x0000000000000000";
    const char digits[] = "0123456789abcdef";
    for (int index = 17; index >= 2; --index) {
        text[index] = digits[number & 15];
        number >>= 4;
    }
    append(buffer, text);
}

/* One write for a complete record when the descriptor accepts it. Interrupted
 * or short writes are retried without losing the unwritten suffix. */
static void emit_buffer(const struct text_buffer *buffer)
{
    const char *at = buffer->data;
    unsigned long remaining = buffer->length;
    while (remaining) {
        long count = write(2, at, remaining);
        if (count < 0) {
            if (*__errno_location() == 4) continue;
            return;
        }
        if (!count) return;
        at += count;
        remaining -= (unsigned long)count;
    }
}

static void emit(const char *text)
{
    unsigned long length = 0;
    while (text[length]) ++length;
    const struct text_buffer buffer = {(char *)text, length, length};
    emit_buffer(&buffer);
}

static int parse_hex(const char **text, unsigned long *number)
{
    unsigned long result = 0;
    const char *at = *text;
    int digits = 0;
    for (;;) {
        unsigned long digit;
        if (*at >= '0' && *at <= '9') digit = (unsigned long)(*at - '0');
        else if (*at >= 'a' && *at <= 'f') digit = (unsigned long)(*at - 'a' + 10);
        else return digits ? (*text = at, *number = result, 1) : 0;
        if (result > (~0UL - digit) / 16) return 0;
        result = result * 16 + digit;
        ++at;
        ++digits;
    }
}

struct map_range {
    unsigned long start, end, offset;
    int readable;
    const char *path;
};

static int parse_map(const char *line, struct map_range *mapping)
{
    if (!parse_hex(&line, &mapping->start) || *line++ != '-' ||
        !parse_hex(&line, &mapping->end) || *line++ != ' ' ||
        mapping->start >= mapping->end) return 0;
    /* Validate before looking ahead past a short or malformed line. */
    const char *permissions = line;
    for (int index = 0; index < 4; ++index) if (!*line++) return 0;
    if ((permissions[0] != 'r' && permissions[0] != '-') ||
        (permissions[1] != 'w' && permissions[1] != '-') ||
        (permissions[2] != 'x' && permissions[2] != '-') ||
        (permissions[3] != 'p' && permissions[3] != 's') || *line++ != ' ') return 0;
    mapping->readable = permissions[0] == 'r';
    while (*line == ' ') ++line;
    if (!parse_hex(&line, &mapping->offset) || *line++ != ' ') return 0;
    for (int field = 0; field < 2; ++field) {
        while (*line == ' ') ++line;
        if (!*line) return 0;
        while (*line && *line != ' ') ++line;
        if (field == 0 && !*line) return 0;
    }
    while (*line == ' ') ++line;
    mapping->path = line;
    return 1;
}

static int equal(const char *left, const char *right)
{
    while (*left && *left == *right) { ++left; ++right; }
    return *left == *right;
}

static void copy_line(char *destination, const char *source)
{
    unsigned long index = 0;
    while (source[index] && index < 1023) {
        destination[index] = source[index];
        ++index;
    }
    destination[index] = 0;
}

struct map_scan {
    const struct context *context;
    unsigned long fault, low, high;
    char module_path[1024], module_low_map[1024];
    int module_emitted;
};

static void emit_map(const char *line, int clipped)
{
    char output[1152];
    struct text_buffer buffer = {output, sizeof output, 0};
    append(&buffer, "VINIX-DOTA2-SIGNAL-MAP: ");
    append(&buffer, line);
    append(&buffer, "\n");
    if (clipped) append(&buffer, "VINIX-DOTA2-SIGNAL-MAP-PATH-TRUNCATED\n");
    emit_buffer(&buffer);
}

static void map_line(const char *line, int clipped, struct map_scan *scan)
{
    struct map_range mapping;
    if (!parse_map(line, &mapping)) return;
    unsigned long stack = scan->context->registers[15];
    if (mapping.readable && stack >= mapping.start && stack < mapping.end) {
        scan->low = mapping.start;
        scan->high = mapping.end;
    }
    /* Adjacent ELF segments share a pathname. Remember an offset-zero load
     * map as context without emitting the hundreds of unrelated modules. */
    if (!clipped && mapping.path[0] == '/' && mapping.offset == 0) {
        copy_line(scan->module_path, mapping.path);
        copy_line(scan->module_low_map, line);
        scan->module_emitted = 0;
    }
    int selected = scan->fault >= mapping.start && scan->fault < mapping.end;
    for (int index = 0; index < 17; ++index) {
        unsigned long address = scan->context->registers[index];
        if (address >= mapping.start && address < mapping.end) selected = 1;
    }
    if (!selected) return;
    if (!clipped && mapping.path[0] == '/' &&
        equal(mapping.path, scan->module_path) && !scan->module_emitted) {
        if (!equal(line, scan->module_low_map)) emit_map(scan->module_low_map, 0);
        scan->module_emitted = 1;
    }
    emit_map(line, clipped);
}

/* One scan, fixed buffers, 16 MiB and 32768 read calls at most. No allocator,
 * loader lock or symbol unwinder runs in the faulting thread. */
static void maps(struct map_scan *scan)
{
    int descriptor = open("/proc/self/maps", 0);
    if (descriptor < 0) { emit("VINIX-DOTA2-SIGNAL-MAPS-UNAVAILABLE\n"); return; }
    char input[1024], line[1024];
    unsigned long used = 0, total = 0, calls = 0;
    const unsigned long limit = 16UL * 1024 * 1024;
    int clipped = 0, ended = 0;
    while (total < limit && calls++ < 32768) {
        unsigned long wanted = limit - total;
        if (wanted > sizeof input) wanted = sizeof input;
        long count = read(descriptor, input, wanted);
        if (count < 0 && *__errno_location() == 4) continue;
        if (count <= 0) { ended = 1; break; }
        total += (unsigned long)count;
        for (long index = 0; index < count; ++index) {
            if (input[index] == '\n') {
                line[used] = 0;
                map_line(line, clipped, scan);
                used = 0;
                clipped = 0;
            } else if (used < sizeof line - 1) line[used++] = input[index];
            else clipped = 1;
        }
    }
    if (used) { line[used] = 0; map_line(line, clipped, scan); }
    if (!ended) emit("VINIX-DOTA2-SIGNAL-MAPS-TRUNCATED\n");
    close(descriptor);
}

static void emit_context(int number, const struct signal_info *info,
                         const struct context *context, int saved_errno)
{
    char output[2048];
    struct text_buffer buffer = {output, sizeof output, 0};
    append(&buffer, "VINIX-DOTA2-SIGNAL: number="); append_hex(&buffer, (unsigned long)number);
    append(&buffer, " code="); append_hex(&buffer, (unsigned long)(long)info->code);
    append(&buffer, " address="); append_hex(&buffer, info->address);
    append(&buffer, " rip="); append_hex(&buffer, context->registers[16]);
    append(&buffer, " rsp="); append_hex(&buffer, context->registers[15]);
    append(&buffer, " rbp="); append_hex(&buffer, context->registers[10]);
    append(&buffer, "\n");
    const char *names[] = {"r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
                          "rdi", "rsi", "rbp", "rbx", "rdx", "rax", "rcx"};
    for (unsigned long index = 0; index < 15; ++index) {
        append(&buffer, "VINIX-DOTA2-SIGNAL-REGISTER: "); append(&buffer, names[index]);
        append(&buffer, "="); append_hex(&buffer, context->registers[index]); append(&buffer, "\n");
    }
    append(&buffer, "VINIX-DOTA2-SIGNAL-ERRNO: ");
    append_hex(&buffer, (unsigned long)saved_errno); append(&buffer, "\n");
    emit_buffer(&buffer);
}

static void failure(int number, void *raw_info, void *raw_context)
{
    int saved_errno = *__errno_location();
    const struct signal_info *info = raw_info;
    const struct context *context = raw_context;
    unsigned long stack = context->registers[15];
    emit_context(number, info, context, saved_errno);
    struct map_scan scan = {0};
    scan.context = context;
    scan.fault = info->address;
    maps(&scan);
    if (scan.low && stack >= scan.low && stack < scan.high && !(stack & 7)) {
        unsigned long available = (scan.high - stack) / sizeof(unsigned long);
        if (available > 256) available = 256;
        const unsigned long *words = (const unsigned long *)stack;
        for (unsigned long index = 0; index < available;) {
            char output[4096];
            struct text_buffer buffer = {output, sizeof output, 0};
            unsigned long end = index + 64;
            if (end > available) end = available;
            for (; index < end; ++index) {
                append(&buffer, "VINIX-DOTA2-SIGNAL-STACK: ");
                append_hex(&buffer, stack + index * sizeof(unsigned long));
                append(&buffer, "="); append_hex(&buffer, words[index]); append(&buffer, "\n");
            }
            emit_buffer(&buffer);
        }
    }
    unsigned long frame = context->registers[10];
    for (unsigned long index = 0; index < 24; ++index) {
        if (!scan.high || scan.high - scan.low < 16 || frame < stack || frame < scan.low ||
            frame > scan.high - 16 || frame - stack > 2 * 1024 * 1024 || (frame & 7)) break;
        const unsigned long *words = (const unsigned long *)frame;
        unsigned long previous = words[0], caller = words[1];
        char output[64];
        struct text_buffer buffer = {output, sizeof output, 0};
        append(&buffer, "VINIX-DOTA2-SIGNAL-FRAME: "); append_hex(&buffer, caller);
        append(&buffer, "\n"); emit_buffer(&buffer);
        if (previous <= frame) break;
        frame = previous;
    }
    emit("VINIX-DOTA2-SIGNAL: returning to the original fault with SIG_DFL\n");
    /* The observed signal is blocked during the handler. Queue that same
     * signal for this thread; its original default disposition terminates
     * the process after return, including for asynchronous signals. */
    raise(number);
}

#ifndef SIGNAL_PROBE_HOST_TEST
__attribute__((constructor))
#endif
static void arm(void)
{
    int error = *__errno_location();
    const char *gate = getenv("VINIX_DOTA2_SIGNAL_PROBE");
    if (!gate || gate[0] != '1' || gate[1]) { *__errno_location() = error; return; }
    unsetenv("VINIX_DOTA2_SIGNAL_PROBE");
    struct action action = {0};
    action.handler = failure;
    action.flags = (int)(0x80000000U | 4U); /* RESETHAND | SIGINFO */
    if (sigaction(11, &action, 0) || sigaction(7, &action, 0) || sigaction(4, &action, 0))
        emit("VINIX-DOTA2-SIGNAL-PROBE-FAIL: sigaction\n");
    else emit("VINIX-DOTA2-SIGNAL-PROBE-ARMED\n");
    *__errno_location() = error;
}
