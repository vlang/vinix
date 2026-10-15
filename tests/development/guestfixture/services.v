// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

fn service_export_checks() {
	unsafe {
		path := &char(c'/home/developer/scheduled-ci.service')
		check(command_output(c'/usr/bin/vinix-jobs', c'service-unit', c'/home/developer/good', nil, path) == 0, 440)
		mut unit := [2048]char{}
		fd := C.open(path, C.O_RDONLY)
		mut st := C.stat{}
		check(fd >= 0 && C.fstat(fd, &st) == 0 && st.st_uid == 1000
			&& st.st_mode & 0o077 == 0, 441)
		count := C.read(fd, &unit[0], unit.len - 1)
		check(count > 0 && count < unit.len - 1 && C.close(fd) == 0, 442)
		expected := &char(c'[Unit]\nDescription=Vinix scheduled jobs\n[Service]\nType=simple\nExecStart="/usr/bin/vinix-jobs" watch "/home/developer/good"\nRestart=on-failure\nRestartSec=1s\nTimeoutStopSec=10s\n[Install]\nWantedBy=default.target\n')
		check(C.strcmp(&unit[0], expected) == 0, 443)
		check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 444)
		job_state(c'/home/developer/good/state.json', false, c'finished', c'"runs":1')
		emit_command_log(path)
		C.puts(c'DEVELOPMENT SERVICE EXPORT PASS: UID 1000, native importer validated literal watcher argv, private unit, credentials omitted, schedule unchanged')
	}
}
