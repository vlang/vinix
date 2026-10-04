module lib

// kprintf prints as print() does, formatted as C's printf formats, into a
// buffer on the stack; see c/printf.c. print() of an interpolated string
// allocates the text and a string for every value in it, and none of them is
// ever freed. V's int is 64 bits: pass integers as u64 or i64 for %llu, %lld
// and %llx, and a V string as "%.*s" with `i32(s.len), s.str`.
fn C.kprintf(fmt charptr, ...voidptr) i32
