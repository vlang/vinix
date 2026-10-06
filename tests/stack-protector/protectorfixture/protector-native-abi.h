#ifndef VINIX_STACK_PROTECTOR_FIXTURE_NATIVE_ABI_H
#define VINIX_STACK_PROTECTOR_FIXTURE_NATIVE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "stack_protector.h"
extern uintptr_t __stack_chk_guard;
struct vstack_protected_bytes { volatile unsigned char bytes[64]; };
__attribute__((no_stack_protector)) int main(void);
__attribute__((no_stack_protector)) int protectorfixture__run(void);
#endif
