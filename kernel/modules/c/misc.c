#include <stdint.h>
#include <stddef.h>

int32_t **__ctype_tolower_loc(void) {
    kpanic("__ctype_tolower_loc is a stub");
    return NULL;
}

int32_t **__ctype_toupper_loc(void) {
    kpanic("__ctype_toupper_loc is a stub");
    return NULL;
}

void kpanic(const char *message) {
	asm ("cli");
	kprint("KERNEL PANIC: ", 14);
	kprint(message, strlen(message));
	for (;;) {
		asm ("hlt");
	}
}

void kprint(const char *message, size_t len) {
	for (size_t i = 0; i < len; i++) {
		asm volatile (
			"outb %1, %0"
			:
            : "Nd" (0xe9),
			  "a"  (message[i])
        );
	}

	stivale2__terminal_print(message, len);
}
