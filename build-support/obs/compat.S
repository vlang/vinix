// Qt's XCB platform creates a D-Bus manager thread while the platform plugin
// is being loaded. On Vinix that thread waits for musl's loader lock while
// the loading thread waits for D-Bus, so the first OBS window never appears.
// Return an empty QDBusConnection for OBS's optional desktop integration.
// QDBusConnection contains one private pointer and has a nontrivial destructor;
// the AArch64 C++ ABI passes its result address in x8.
.text
.global _ZN15QDBusConnection10sessionBusEv
.type _ZN15QDBusConnection10sessionBusEv, %function
_ZN15QDBusConnection10sessionBusEv:
    str xzr, [x8]
    ret
.size _ZN15QDBusConnection10sessionBusEv, .-_ZN15QDBusConnection10sessionBusEv

.global _ZN15QDBusConnection9systemBusEv
.type _ZN15QDBusConnection9systemBusEv, %function
_ZN15QDBusConnection9systemBusEv:
    str xzr, [x8]
    ret
.size _ZN15QDBusConnection9systemBusEv, .-_ZN15QDBusConnection9systemBusEv

// The generic Unix Qt theme queries D-Bus when checking for a system tray.
// With no desktop bus or tray service, OBS must take its normal no-tray path.
.global _ZN15QSystemTrayIcon21isSystemTrayAvailableEv
.type _ZN15QSystemTrayIcon21isSystemTrayAvailableEv, %function
_ZN15QSystemTrayIcon21isSystemTrayAvailableEv:
    mov w0, #0
    ret
.size _ZN15QSystemTrayIcon21isSystemTrayAvailableEv, .-_ZN15QSystemTrayIcon21isSystemTrayAvailableEv

// OBS's destruction-task worker stops permanently when sem_wait is interrupted
// by a signal. Vinix can deliver SIGCHLD during startup, and POSIX permits
// sem_wait to return EINTR. Retry that transient error so scene cleanup can
// reach the worker. libobs's os_sem_data contains sem_t as its first field.
.global os_sem_wait
.type os_sem_wait, %function
os_sem_wait:
    stp x19, x30, [sp, #-16]!
    mov x19, x0
    cbz x19, .Los_sem_bad
.Los_sem_retry:
    mov x0, x19
    bl sem_wait
    cbz w0, .Los_sem_done
    bl __errno_location
    ldr w1, [x0]
    cmp w1, #4          // EINTR
    b.eq .Los_sem_retry
.Los_sem_bad:
    mov w0, #-1
.Los_sem_done:
    ldp x19, x30, [sp], #16
    ret
.size os_sem_wait, .-os_sem_wait

// musl reports ENOSYS for unsupported priority-inheritance mutexes, while
// PulseAudio expects ENOTSUP and otherwise aborts. Leave the default mutex
// attributes in place and report that optional protocol as unsupported.
.global pthread_mutexattr_setprotocol
.type pthread_mutexattr_setprotocol, %function
pthread_mutexattr_setprotocol:
    cbz w1, .Los_protocol_ok      // PTHREAD_PRIO_NONE is the default
    cmp w1, #1                     // PTHREAD_PRIO_INHERIT
    b.eq .Los_protocol_unsupported
    cmp w1, #2                     // PTHREAD_PRIO_PROTECT
    b.eq .Los_protocol_unsupported
    mov w0, #22                    // EINVAL
    ret
.Los_protocol_unsupported:
    mov w0, #95                    // ENOTSUP
    ret
.Los_protocol_ok:
    mov w0, #0
    ret
.size pthread_mutexattr_setprotocol, .-pthread_mutexattr_setprotocol
