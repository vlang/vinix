// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <sys/mount.h>
#include <unistd.h>

fn C.umount(&char) i32
fn C.sync()

fn cold_boot_account(phase i32) {
	unsafe {
		check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
			&& C.chdir(c'/home/developer') == 0, 490)
		check(C.setenv(c'UNSELECTED_PARENT_SECRET', c'parent-must-not-reach-job', 1) == 0
			&& C.setenv(c'VINIX_SESSION_RUNTIME', c'/run/development-service', 1) == 0, 491)
		mut before := [8192]char{}
		if phase == 1 {
			snapshot_job(c'/fixture/service-jobs.json', c'/home/developer/service-jobs.json')
			write_text(c'/home/developer/token', c'vinix-native-fixture-secret', 27)
			check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/service-jobs.json',
				c'/home/developer/service-state') == 0, 493)
			check(command_output(c'/usr/bin/vinix-jobs', c'service-unit', c'/home/developer/service-state',
				nil, c'/home/developer/service.service') == 0, 494)
			check(C.open(c'/home/developer/.vinix-services', C.O_RDONLY) == -1, 495)
		} else {
			// Read the previous boot's state before starting any broker or job.
			private_receipt(c'/home/developer/service-state/state.json', c'job interrupted')
			service_config(mut before)
		}
		check(C.open(c'/home/developer/service.parent.pid', C.O_RDONLY) == -1
			&& C.open(c'/home/developer/service.child.pid', C.O_RDONLY) == -1
			&& C.open(c'/home/developer/service.owner.pid', C.O_RDONLY) == -1, 496)
		broker := service_broker()
		service_call(c'attach', nil, nil)
		if phase == 1 {
			_ = service_request([&char(c'service.import'), &char(c'vinix-jobs.service'),
				&char(c'/home/developer/service.service'), &char(c'0')]!, 4, false)
			service_wait(true)
			service_call(c'service.enable', c'0', c'1')
		}
		// Later boots restore the enabled record themselves; no Start/import.
		guardian := service_wait(false)
		parent := job_pid(c'/home/developer/service', c'parent')
		child := job_pid(c'/home/developer/service', c'child')
		watcher := job_pid(c'/home/developer/service', c'owner')
		check(C.getpgid(watcher) == guardian && C.getpgid(parent) == parent
			&& C.getpgid(child) == parent, 497)
		mut running := [8192]char{}
		service_config(mut running)
		if phase > 1 { check(C.strcmp(&before[0], &running[0]) == 0, 498) }
		start := job_clock()
		if phase == 3 {
			service_call(c'service.enable', c'0', c'0')
			service_wait(true)
			service_call(c'service.remove', c'vinix-jobs.service', nil)
		}
		service_call(c'shutdown', nil, nil)
		wait_jobs(broker, 0)
		for pid in [guardian, watcher, parent, child]! { retired_job(pid) }
		elapsed := (job_clock() - start) / 1000000
		check(elapsed < 10000, 499)
		mut after := [8192]char{}
		service_config(mut after)
		if phase < 3 { check(C.strcmp(&running[0], &after[0]) == 0, 500) }
		check(C.unlink(c'/home/developer/service.parent.pid') == 0
			&& C.unlink(c'/home/developer/service.child.pid') == 0
			&& C.unlink(c'/home/developer/service.owner.pid') == 0, 501)
		snapshot_job(c'/home/developer/service-state/state.json', c'/home/developer/service-after.json')
		private_receipt(c'/home/developer/service-after.json', c'job interrupted')
		mut proof := [24576]char{}
		length := C.snprintf(&proof[0], proof.len,
			c'{"schema":1,"uid":1000,"phase":%d,"guardian":%d,"watcher":%d,"parent":%d,"child":%d,"stop_millis":%lu,"before":"%s","running":"%s","after":"%s"}',
			phase, guardian, watcher, parent, child, elapsed, &before[0], &running[0], &after[0])
		check(length > 0 && length < proof.len, 502)
		write_text(c'/home/developer/service-cold-proof.json', &proof[0], usize(length))
		private_receipt(c'/home/developer/service-cold-proof.json', c'"schema":1')
		emit_command_log(c'/home/developer/service-broker.log')
	}
}

// Three independent QEMU boots share only this explicitly mounted test volume.
// Root mounts/unmounts it; all schedule and service operations run as UID 1000.
fn service_cold_boot() bool {
	unsafe {
		fd := C.open(c'/fixture/service-cold-phase', C.O_RDONLY)
		if fd < 0 { return false }
		mut phase_text := [2]char{}
		check(C.read(fd, &phase_text[0], 2) == 1 && C.close(fd) == 0
			&& phase_text[0] >= char(`1`) && phase_text[0] <= char(`3`), 503)
		phase := i32(phase_text[0]) - i32(`0`)
		mut device := [64]char{}
		device_fd := C.open(c'/fixture/service-cold-device', C.O_RDONLY)
		count := C.read(device_fd, &device[0], device.len - 1)
		check(device_fd >= 0 && count > 0 && count < device.len - 1 && C.close(device_fd) == 0, 504)
		check(C.mount(&device[0], c'/home/developer', c'ext2', 0, nil) == 0, 505)
		if phase == 1 {
			check(C.chown(c'/home/developer', 1000, 1000) == 0
				&& C.chmod(c'/home/developer', 0o700) == 0, 506)
		}
		mut st := C.stat{}
		check(C.stat(c'/home/developer', &st) == 0 && st.st_uid == 1000
			&& st.st_mode & 0o777 == 0o700, 507)
		// Runtime sockets belong on volatile storage, as in an installed session.
		// Only the account's home is the shared ext2 volume in this fixture.
		check((C.mkdir(c'/run', 0o755) == 0 || *C.__errno_location() == C.EEXIST)
			&& C.mkdir(c'/run/development-service', 0o700) == 0
			&& C.chown(c'/run/development-service', 1000, 1000) == 0, 492)
		pid := C.fork()
		check(pid >= 0, 508)
		if pid == 0 { cold_boot_account(phase); C._exit(0) }
		mut status := i32(0)
		for {
			reaped := C.waitpid(-1, &status, C.WNOHANG)
			check(reaped >= 0 || *C.__errno_location() == C.EINTR, 509)
			if reaped == pid { check(status == 0, 510); break }
			if reaped <= 0 { C.usleep(10000) }
		}
		// The tested kernel defers removed-node/resource release for five
		// seconds, serviced by its one-second writeback worker. Preserve that
		// lifetime: this gate explicitly qualifies a quiescent shutdown. An
		// immediate sync/unmount left orphan allocations in the control run;
		// draining deferred cleanup on immediate unmount remains a kernel gap.
		settle := job_clock() + 7000000000
		for job_clock() < settle { C.usleep(100000) }
		C.sync()
		check(C.umount(c'/home/developer') == 0, 511)
		C.sync()
		// The controller may stop QEMU only after the disk has been unmounted.
		C.printf(c'DEVELOPMENT SERVICE COLD BOOT PASS: phase=%d, persistent ext2 home, UID 1000, seven-second quiescence, all processes retired, volume unmounted\n', phase)
		for { C.pause() }
		return true
	}
}
