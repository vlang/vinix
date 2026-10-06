#ifndef _SYMBOLS_H
#define _SYMBOLS_H

extern char text_start[];
extern char text_end[];
extern char rodata_start[];
extern char rodata_end[];
extern char data_start[];
extern char data_end[];

extern char interrupt_thunks[];

/* AArch64 assembly symbols */
extern void exception_vectors(void);
extern void sched_switch_context(void *gpr_state, unsigned long kernel_stack);
extern void yield_dispatch(void *handler_fn_ptr);

/* Borrowed native callback, exact ARM stack read and bounded UART trace. */
void vinix_call_void_fn(void *);
unsigned long read_current_sp(void);
void trace_syscall_nr(unsigned long);

#endif
