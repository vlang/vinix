module userland

import errno
import usercopy

const exec_vector_max = 4096
const exec_string_max = u64(4096)
const exec_strings_max_bytes = u64(2 * 1024 * 1024)

fn free_exec_strings(mut values []string) {
	for value in values {
		unsafe { value.free() }
	}
	unsafe { values.free() }
}

fn copy_exec_vector(vector u64) ?[]string {
	mut values := []string{}
	if vector == 0 {
		return values
	}
	mut total := u64(0)
	for i := 0; i < exec_vector_max; i++ {
		offset := u64(i) * sizeof(u64)
		if vector > u64(-1) - offset {
			errno.set(errno.efault)
			free_exec_strings(mut values)
			return none
		}
		mut string_pointer := u64(0)
		if !usercopy.copy_from_user(voidptr(&string_pointer), vector + offset, sizeof(u64)) {
			errno.set(errno.efault)
			free_exec_strings(mut values)
			return none
		}
		if string_pointer == 0 {
			return values
		}
		value := usercopy.string_from_user(string_pointer, exec_string_max) or {
			errno.set(errno.efault)
			free_exec_strings(mut values)
			return none
		}
		charged := u64(value.len) + 1
		if charged > exec_strings_max_bytes - total {
			unsafe { value.free() }
			errno.set(errno.e2big)
			free_exec_strings(mut values)
			return none
		}
		total += charged
		values << value
	}
	errno.set(errno.e2big)
	free_exec_strings(mut values)
	return none
}
