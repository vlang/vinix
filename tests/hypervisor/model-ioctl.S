/* Native variadic call boundary for the independent host model. */
#ifdef __APPLE__
.text
.globl _hv_model_ioctl
_hv_model_ioctl:
#if defined(__aarch64__)
    /* Darwin places ioctl's first variadic argument on the caller's stack. */
    ldr x2, [sp]
    b _hv_model_ioctl_backend
#else
    jmp _hv_model_ioctl_backend
#endif
#else
.text
.global hv_model_ioctl
hv_model_ioctl:
#if defined(__aarch64__)
    b hv_model_ioctl_backend
#else
    jmp hv_model_ioctl_backend
#endif
.section .note.GNU-stack,"",%progbits
#endif
