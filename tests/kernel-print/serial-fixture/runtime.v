module fixture

// The freestanding generator excludes builtin implementations. Supply only
// the two checked-index primitives used by these production bodies, in V.
@[export: 'v_fixed_index']
fn fixed_index(index int, length int) int {
	C.assert(index >= 0 && index < length)
	return index
}

@[export: 'string__at']
fn string_at(text string, index int) u8 {
	C.assert(index >= 0 && index < text.len)
	// The pointer is the first field of V's string ABI; no-builtin mode has
	// no frontend declaration of that field.
	bytes := unsafe { *(&&u8(voidptr(&text))) }
	return unsafe { bytes[index] }
}
