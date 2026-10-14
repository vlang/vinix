// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

fn C.getpid() int
fn C.sscanf(&char, &char, ...) int
fn C.strstr(&char, &char) &char

fn security_event_total(reports bool) u64 {
	unsafe {
		fd := C.open(c'/proc/security_events', C.O_RDONLY)
		mut text := [65536]char{}
		check(fd >= 0 && C.read(fd, &text[0], text.len - 1) > 0 && C.close(fd) == 0, 710)
		mut total := u64(0)
		mut retained := u64(0)
		mut dropped := u64(0)
		check(C.sscanf(&text[0], c'version=1 capacity=256 total=%lu retained=%lu dropped=%lu',
			&total, &retained, &dropped) == 3, 710)
		check(retained == if total < 256 { total } else { 256 }
			&& dropped == total - retained, 710)
		check(C.strstr(&text[0], c'UNPRIVILEGED_COPYUP_REPORT') == nil, 711)
		if reports {
			check(C.strstr(&text[0], c'0123456789012345678901234567890123456789\n') != nil
				&& C.strstr(&text[0], c'0123456789012345678901234567890123456789EXTRA') == nil, 711)
		}
		return total
	}
}

fn security_event_writer() int {
	unsafe {
		fd := C.open(c'/proc/security_events', C.O_WRONLY)
		check(fd >= 0, 712)
		worker := C.fork()
		check(worker >= 0, 712)
		if worker == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 712)
			mut payload := [128]char{}
			length := C.snprintf(&payload[0], payload.len, c'%d 1 UNPRIVILEGED_COPYUP_REPORT\n', C.getpid())
			check(length > 0 && C.write(fd, &payload[0], usize(length)) == -1
				&& *C.__errno_location() == C.EPERM && C.close(fd) == 0, 712)
			C._exit(0)
		}
		mut status := 0
		check(C.waitpid(worker, &status, 0) == worker && C.WIFEXITED(status) != 0
			&& C.WEXITSTATUS(status) == 0, 712)
		// Check before later records could overwrite a forbidden report.
		security_event_total(false)
		return fd
	}
}

fn security_event_report(fd int, denied bool) {
	unsafe {
		mut payload := [128]char{}
		length := C.snprintf(&payload[0], payload.len, c'%d %d 0123456789012345678901234567890123456789EXTRA\n',
			C.getpid(), int(denied))
		check(length > 0 && C.write(fd, &payload[0], usize(length)) == length, 713)
		// The ring must keep its own bounded copy after the caller changes this.
		C.memset(&payload[0], `X`, payload.len)
	}
}
