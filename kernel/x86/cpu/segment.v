module cpu

// asm/x86_64/segment.S
fn C.x86_access_rights(selector u16) u32
fn C.x86_segment_limit(selector u16, limit &u32) bool
fn C.x86_load_ldt(selector u16)
fn C.x86_fs_selector() u16
fn C.x86_gs_selector() u16
fn C.x86_load_fs(selector u16)
fn C.x86_load_gs(selector u16)
fn C.x86_load_user_gs(selector u16)

// The bits of access_rights(): those of a descriptor's high word LAR reports.
pub const ar_accessed = u32(1) << 8
pub const ar_writable = u32(1) << 9 // data; readable, for code
pub const ar_conforming = u32(1) << 10 // code; expand-down, for data
pub const ar_code = u32(1) << 11
pub const ar_code_or_data = u32(1) << 12
pub const ar_dpl_shift = 13
pub const ar_present = u32(1) << 15
pub const ar_long = u32(1) << 21

// The access rights of the descriptor `selector` names in this CPU's GDT or
// LDT, or 0 when there is none a selector of its RPL may see.
pub fn access_rights(selector u16) u32 {
	return C.x86_access_rights(selector)
}

// The limit, in bytes, of the segment `selector` names.
pub fn segment_limit(selector u16) ?u32 {
	mut limit := u32(0)
	if !C.x86_segment_limit(selector, &limit) {
		return none
	}
	return limit
}

pub fn load_ldt(selector u16) {
	C.x86_load_ldt(selector)
}

pub fn fs_selector() u16 {
	return C.x86_fs_selector()
}

pub fn gs_selector() u16 {
	return C.x86_gs_selector()
}

pub fn load_fs_selector(selector u16) {
	C.x86_load_fs(selector)
}

// Only while the GS base is not the one the kernel finds itself by.
pub fn load_gs_selector(selector u16) {
	C.x86_load_gs(selector)
}

// From a syscall, whose user GS base SWAPGS has put aside.
pub fn load_user_gs_selector(selector u16) {
	C.x86_load_user_gs(selector)
}
