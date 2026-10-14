// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

fn overlay_depth_options(options &char) {
	unsafe { check(C.snprintf(options, 512, c'lowerdir=/tmp/overlay-state/depth-7') > 0, 704) }
}

fn overlay_depth_limit() {
	unsafe {
		owned_directory(c'/tmp/overlay-state/depth-lower', 704)
		owned_directory(c'/tmp/overlay-state/depth-lower/nested', 704)
		owned_directory(c'/tmp/overlay-state/depth-lower/work', 704)
		write_file(c'/tmp/overlay-state/depth-lower/nested/file', c'COPYDATA', 704)
		check(C.chown(c'/tmp/overlay-state/depth-lower/nested/file', 1000, 1000) == 0, 704)
		for level in 0 .. 9 {
			mut path := [512]char{}
			mut options := [512]char{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/depth-%d', level) > 0, 704)
			owned_directory(&path[0], 704)
			if level == 0 {
				check(C.snprintf(&options[0], 512, c'lowerdir=/tmp/overlay-state/depth-lower') > 0, 704)
			} else {
				check(C.snprintf(&options[0], 512, c'lowerdir=/tmp/overlay-state/depth-%d', level - 1) > 0, 704)
			}
			mut prior := C.stat{}
			if level == 8 { check(C.lstat(&path[0], &prior) == 0, 705) }
			result := C.mount(c'overlay', &path[0], c'overlay', 0, &options[0])
			failure := *C.__errno_location()
			if level == 8 {
				if result != -1 || failure != C.ELOOP {
					C.printf(c'OVERLAY DEPTH: level=9 result=%d errno=%d expected=%d\n', result, failure, C.ELOOP)
					C.fflush(nil)
				}
				check(result == -1 && failure == C.ELOOP, 705)
				mut after := C.stat{}
				check(C.lstat(&path[0], &after) == 0 && prior.st_dev == after.st_dev
					&& prior.st_ino == after.st_ino, 705)
			} else { check(result == 0, 705) }
		}
		worker := C.fork()
		check(worker >= 0, 706)
		if worker == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 706)
			check(contents(c'/tmp/overlay-state/depth-7/nested/file', c'COPYDATA'), 706)
			C._exit(0)
		}
		mut status := 0
		check(C.waitpid(worker, &status, 0) == worker && C.WIFEXITED(status) != 0
			&& C.WEXITSTATUS(status) == 0, 706)
		mut options := [512]char{}
		overlay_depth_options(&options[0])
		upper_options := &char(c'lowerdir=/tmp/overlay-state/depth-lower,upperdir=/tmp/overlay-state/depth-7,workdir=/tmp/overlay-state/depth-7/work')
		work_options := &char(c'lowerdir=/tmp/overlay-state/depth-lower,upperdir=/tmp/overlay-state/depth-lower/nested,workdir=/tmp/overlay-state/depth-7/work')
		report_fd := security_event_writer()
		for phase in 70 .. 72 {
			before := security_event_total(false)
			for iteration in 0 .. 200 {
				check(C.mount(c'overlay', c'/tmp/overlay-state/depth-8', c'overlay', 0, &options[0]) == -1
					&& *C.__errno_location() == C.ELOOP, 707)
				for extra in [upper_options, work_options]! {
					check(C.mount(c'overlay', c'/tmp/overlay-state/depth-8', c'overlay', 0, extra) == -1
						&& *C.__errno_location() == C.ELOOP, 707)
				}
				security_event_report(report_fd, iteration % 2 != 0)
			}
			check(security_event_total(true) >= before + 800, 714)
			check(C.usleep(25000000) == 0, 707)
			sample(phase)
		}
		check(C.close(report_fd) == 0, 714)
		mut absent := C.stat{}
		check(C.lstat(c'/tmp/overlay-state/depth-lower/work/work', &absent) == -1
			&& *C.__errno_location() == C.ENOENT, 708)
		for remaining in 0 .. 8 {
			mut path := [512]char{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/depth-%d', 7 - remaining) > 0
				&& C.umount(&path[0]) == 0, 708)
		}
		C.puts(c'OVERLAY STACK DEPTH: PASS')
		C.puts(c'SECURITY EVENT PRODUCERS: PASS')
		C.fflush(nil)
	}
}
