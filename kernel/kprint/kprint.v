@[has_globals]
module kprint

import klock

@[markused]
__global (
	printf_lock klock.Lock
	kprint_lock klock.Lock
)

fn C.byteptr_vstring(byteptr) string
fn C.byteptr_vstring_with_len(byteptr, int) string
fn C.char_vstring(charptr) string
