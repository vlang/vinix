// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module compatcore

// Linux 6.6.157 lib/kstrtox.c user-memory wrappers. Copy the complete
// clamped input before parsing, even when an earlier byte is NUL. The
// fixed buffers and the result remain borrowed for this synchronous call.
fn kstrtox_copy_user_text(buffer &char, capacity usize, source &char, count usize) i32 {
	mut copied := count
	if copied >= capacity {
		copied = capacity - 1
	}
	if checked_copy_from_user(buffer, source, copied, capacity) != 0 {
		return -14
	}
	unsafe { buffer[copied] = 0 }
	return 0
}

@[export: 'kstrtoull_from_user']
pub fn kstrtoull_from_user(source &char, count usize, base u32, result &u64) i32 {
	mut buffer := [67]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 67, source, count) != 0 {
		return -14
	}
	return kstrtoull(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtoll_from_user']
pub fn kstrtoll_from_user(source &char, count usize, base u32, result &i64) i32 {
	mut buffer := [67]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 67, source, count) != 0 {
		return -14
	}
	return kstrtoll(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtoul_from_user']
pub fn kstrtoul_from_user(source &char, count usize, base u32, result &u64) i32 {
	mut buffer := [67]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 67, source, count) != 0 {
		return -14
	}
	return kstrtoul(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtol_from_user']
pub fn kstrtol_from_user(source &char, count usize, base u32, result &i64) i32 {
	mut buffer := [67]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 67, source, count) != 0 {
		return -14
	}
	return kstrtol(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtouint_from_user']
pub fn kstrtouint_from_user(source &char, count usize, base u32, result &u32) i32 {
	mut buffer := [35]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 35, source, count) != 0 {
		return -14
	}
	return kstrtouint(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtoint_from_user']
pub fn kstrtoint_from_user(source &char, count usize, base u32, result &i32) i32 {
	mut buffer := [35]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 35, source, count) != 0 {
		return -14
	}
	return kstrtoint(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtou16_from_user']
pub fn kstrtou16_from_user(source &char, count usize, base u32, result &u16) i32 {
	mut buffer := [19]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 19, source, count) != 0 {
		return -14
	}
	return kstrtou16(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtos16_from_user']
pub fn kstrtos16_from_user(source &char, count usize, base u32, result &i16) i32 {
	mut buffer := [19]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 19, source, count) != 0 {
		return -14
	}
	return kstrtos16(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtou8_from_user']
pub fn kstrtou8_from_user(source &char, count usize, base u32, result &u8) i32 {
	mut buffer := [11]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 11, source, count) != 0 {
		return -14
	}
	return kstrtou8(unsafe { &buffer[0] }, base, result)
}

@[export: 'kstrtos8_from_user']
pub fn kstrtos8_from_user(source &char, count usize, base u32, result &i8) i32 {
	mut buffer := [11]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 11, source, count) != 0 {
		return -14
	}
	return kstrtos8(unsafe { &buffer[0] }, base, unsafe { &char(result) })
}

@[export: 'kstrtobool_from_user']
pub fn kstrtobool_from_user(source &char, count usize, result &bool) i32 {
	mut buffer := [4]char{}
	if kstrtox_copy_user_text(unsafe { &buffer[0] }, 4, source, count) != 0 {
		return -14
	}
	return kstrtobool(unsafe { &buffer[0] }, result)
}
