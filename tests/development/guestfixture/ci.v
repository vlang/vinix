// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

fn C.mkdir(&char, u32) i32
fn C.strlen(&char) usize

fn ci_payload() i32 {
	unsafe {
		check(C.getuid() == 1000 && C.geteuid() == 1000 && C.getgid() == 1000 && C.getegid() == 1000, 410)
		check(C.getenv(c'CI_TOKEN') == nil && C.getenv(c'TEST_TOKEN') == nil
			&& C.getenv(c'UNSELECTED_PARENT_SECRET') == nil, 411)
		proof := &char(c'{"schema":1,"uid":1000,"gid":1000,"credential_absent":true}\n')
		write_text(c'ci-account.json', proof, C.strlen(proof))
		return 0
	}
}

fn ci_prepare() {
	unsafe {
		fd := C.open(c'/home/developer/ci-jobs.json', C.O_RDONLY)
		if fd < 0 { return }
		check(C.close(fd) == 0 && C.chown(c'/home/developer/ci-jobs.json', 1000, 1000) == 0
			&& C.chmod(c'/home/developer/ci-jobs.json', 0o600) == 0, 412)
	}
}

fn ci_finish() {
	unsafe {
		snapshot_job(c'/home/developer/ci-state/state.json', c'/home/developer/ci-completed.json')
		job_state(c'/home/developer/ci-completed.json', false, c'"attempts":2', c'"runs":2')
		private_receipt(c'/home/developer/ci-state/plan.json', c'ci-{attempt}')
		// A fresh attempt must refuse an existing output rather than truncate
		// it. Its failure must also advance the persisted attempt/completion.
		check(C.mkdir(c'/home/developer/ci-3', 0o700) == 0, 413)
		write_text(c'/home/developer/ci-3/sentinel', c'preserved', 9)
		C.usleep(1100000)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/ci-state', nil) == 1, 414)
		job_state(c'/home/developer/ci-state/state.json', false, c'"exit_code":1', c'"runs":3')
		mut data := [10]char{}
		fd := C.open(c'/home/developer/ci-3/sentinel', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &data[0], 9) == 9 && C.close(fd) == 0
			&& C.strcmp(&data[0], c'preserved') == 0, 415)
		check(C.open(c'/home/developer/ci-3/receipt.json', C.O_RDONLY) == -1
			&& *C.__errno_location() == C.ENOENT, 416)
		C.puts(c'DEVELOPMENT CI PASS: UID 1000, two scheduled native Go builds, fresh attempts, private credentials and existing-output refusal')
	}
}
