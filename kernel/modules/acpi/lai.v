//! ## Resources
//! * <https://github.com/managarm/lai>

module acpi

/// Sets the ACPI revision to the provided `revison`.
fn C.lai_set_acpi_revision(revision int)
/// Creates the ACPI namespace.
fn C.lai_create_namespace()

// host functions:
//
// defined in lai/include/lai/host.h
const (
    laihost_debug_log = 1
    laihost_warn_log = 2 
)

/// Logs a message. level can either be [`LAI_DEBUG_LOG`] for debugging info,
/// or [`LAI_WARN_LOG`] for warnings.
[export: "laihost_log"]
fn laihost_log(level int, _msg charptr) {
    // SAFETY: valid `cstring` is provided
    msg := unsafe { cstring_to_vstring(_msg) }

    if level == laihost_debug_log {
        println("lai_debug: $msg")
    } else if level == laihost_warn_log {
        println("lai_warn: $msg")
    } else {
        // invalid log level
        println("laihost_log: invalid log level (level=$level, msg=$msg)")
    }
}

/// Reports a fatal error, and halts.
[export: "laihost_panic"]
[noreturn]
fn laihost_panic(_msg charptr) {
    // SAFETY: valid `cstring` is provided
    msg := unsafe { cstring_to_vstring(_msg) }
    panic("lai: $msg")
}

[export: "laihost_malloc"]
fn laihost_malloc(size int) voidptr {
	return malloc(size)
}

[export: "laihost_realloc"]
fn laihost_realloc(ptr voidptr, new_size u64) voidptr {
	return realloc(ptr, new_size)
}

[export: "laihost_free"]
fn laihost_free(ptr voidptr) {
	return free(ptr)
}
