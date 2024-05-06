#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#include <printf/printf.h>

void dev__serial__out(char);
void dev__serial__panic_out(char);
void term__print(const char *, uint64_t);

static void _putchar(char character) {
  (void)character;
#ifndef PROD
  dev__serial__out(character);
#endif
}

static void _putchar_panic(char character) {
#ifndef PROD
  dev__serial__panic_out(character);
#endif
  term__print(&character, 1);
}

static void (*putchar_func)(char) = _putchar;

void putchar_(char c) {
  putchar_func(c);
}

void klock__Lock_acquire(void *);
void klock__Lock_release(void *);
extern char printf_lock;

int printf(const char *fmt, ...) {
  va_list l;
  va_start(l, fmt);
  klock__Lock_acquire(&printf_lock);
  int ret = vprintf_(fmt, l);
  klock__Lock_release(&printf_lock);
  va_end(l);
  return ret;
}

int printf_panic(const char *fmt, ...) {
  va_list l;
  va_start(l, fmt);
  void (*old_func)(char) = putchar_func;
  putchar_func = _putchar_panic;
  int ret = vprintf_(fmt, l);
  va_end(l);
  putchar_func = old_func;
  return ret;
}
