// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module hostfixture

#include <native-abi.h>

// ABI native-scalar: sandbox_prctl_word const_unsigned_long_64
@[typedef]
struct C.sandbox_prctl_word {}

struct C.sb_cap_data {
mut:
	effective u32
	permitted u32
	inheritable u32
}

@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.puts(&char) i32
fn C.vinix_sandbox_main(i32, &&char) i32

__global sandbox_calls i32
__global sandbox_fail_at i32
__global sandbox_execs i32
__global sandbox_groups i32
__global sandbox_lying_nnp i32
__global sandbox_lying_caps i32
__global sandbox_lying_ids i32
__global sandbox_lying_groups i32
__global sandbox_lying_ambient i32
__global sandbox_uids [3]u32
__global sandbox_gids [3]u32
__global sandbox_current_caps [2]C.sb_cap_data
__global sandbox_exec_path &char
__global sandbox_target_promises &char
__global sandbox_launcher_promises &char
__global sandbox_exec_argv [8]&char
__global sandbox_exec_env [66]&char
__global sandbox_unveiled i32
__global sandbox_locked i32

fn step() i32 {
	sandbox_calls++
	if sandbox_calls == sandbox_fail_at {
		C.errno = C.EPERM
		return -1
	}
	return 0
}

fn reset() {
	unsafe {
		sandbox_calls = 0
		sandbox_fail_at = 0
		sandbox_execs = 0
		sandbox_unveiled = 0
		sandbox_locked = 0
		sandbox_groups = 2
		sandbox_lying_nnp = 0
		sandbox_lying_caps = 0
		sandbox_lying_ids = 0
		sandbox_lying_groups = 0
		sandbox_lying_ambient = 0
		for i := i32(0); i < 3; i++ {
			sandbox_uids[i] = 0
			sandbox_gids[i] = 0
		}
		C.memset(&sandbox_current_caps[0], 0xff, sizeof(sandbox_current_caps))
		sandbox_exec_path = nil
		sandbox_target_promises = nil
		sandbox_launcher_promises = nil
		C.memset(&sandbox_exec_argv[0], 0, sizeof(sandbox_exec_argv))
		C.memset(&sandbox_exec_env[0], 0, sizeof(sandbox_exec_env))
	}
}

@[export: 'sb_prctl']
fn prctl(option i32, arg C.sandbox_prctl_word) i32 {
	if step() != 0 { return -1 }
	if option == C.SB_PR_GET_NO_NEW_PRIVS {
		return if sandbox_lying_nnp != 0 { 0 } else { 1 }
	}
	if option == C.SB_PR_CAPBSET_READ {
		mut word := u64(0)
		unsafe { C.memcpy(&word, &arg, sizeof(word)) }
		if word > 40 {
			C.errno = C.EINVAL
			return -1
		}
		return 1
	}
	return 0
}

@[export: 'sb_capget']
fn capget(data &C.sb_cap_data) i32 {
	if step() != 0 { return -1 }
	unsafe { C.memcpy(data, &sandbox_current_caps[0], sizeof(sandbox_current_caps)) }
	return 0
}

@[export: 'sb_capset']
fn capset(data &C.sb_cap_data) i32 {
	if step() != 0 { return -1 }
	if sandbox_lying_caps == 0 {
		unsafe { C.memcpy(&sandbox_current_caps[0], data, sizeof(sandbox_current_caps)) }
	}
	return 0
}

@[export: 'sb_verify_ambient']
fn verify_ambient() i32 {
	if step() != 0 { return -1 }
	return if sandbox_lying_ambient != 0 { -1 } else { 0 }
}

@[export: 'sb_getids']
fn getids(uid &u32, gid &u32) i32 {
	if step() != 0 { return -1 }
	unsafe {
		C.memcpy(uid, &sandbox_uids[0], sizeof(sandbox_uids))
		C.memcpy(gid, &sandbox_gids[0], sizeof(sandbox_gids))
	}
	return 0
}

@[export: 'sb_setids']
fn setids(uid u32, gid u32) i32 {
	if step() != 0 { return -1 }
	if sandbox_lying_ids == 0 {
		unsafe {
			for i := i32(0); i < 3; i++ {
				sandbox_uids[i] = uid
				sandbox_gids[i] = gid
			}
		}
	}
	return 0
}

@[export: 'sb_groups']
fn groups(clear i32) i32 {
	if step() != 0 { return -1 }
	if clear != 0 && sandbox_lying_groups == 0 { sandbox_groups = 0 }
	return if clear != 0 { 0 } else { sandbox_groups }
}

@[export: 'sb_close_fds']
fn close_fds() i32 { return step() }

// All captured strings are borrowed from synchronous callers and string literals.
// No callback retains the caller's argv or environment pointer-array storage.
@[export: 'sb_unveil']
fn unveil(path &char, perms &char) i32 {
	if step() != 0 { return -1 }
	unsafe {
		if path == nil {
			C.assert(perms == nil)
			sandbox_locked = 1
		} else {
			C.assert(sandbox_locked == 0)
			if sandbox_unveiled == 0 {
				C.assert(C.strcmp(path, c'/sbin/probe') == 0)
				C.assert(C.strcmp(perms, c'rx') == 0)
			}
			sandbox_unveiled++
		}
	}
	return 0
}

@[export: 'sb_pledge']
fn pledge(promises &char, execpromises &char) i32 {
	if step() != 0 { return -1 }
	C.assert(sandbox_locked != 0)
	sandbox_launcher_promises = promises
	sandbox_target_promises = execpromises
	return 0
}

@[export: 'sb_exec']
fn exec(path &char, argv &&char, envp &&char) i32 {
	unsafe {
		C.assert(sandbox_locked != 0 && sandbox_target_promises != nil)
		sandbox_execs++
		C.assert(sandbox_current_caps[0].effective == 0 && sandbox_current_caps[1].effective == 0)
		sandbox_exec_path = path
		for i := usize(0); argv[i] != nil; i++ {
			C.assert(i < 7)
			sandbox_exec_argv[i] = argv[i]
		}
		for i := usize(0); envp[i] != nil; i++ {
			C.assert(i < C.SB_MAX_ENV + 1)
			sandbox_exec_env[i] = envp[i]
		}
		C.errno = C.ENOENT
	}
	return -1
}

fn run(argv &&char) i32 {
	mut argc := i32(0)
	unsafe { for argv[argc] != nil { argc++ } }
	return C.vinix_sandbox_main(argc, argv)
}

fn bad(argv &&char) {
	reset()
	C.assert(run(argv) == 125)
	C.assert(sandbox_calls == 0 && sandbox_execs == 0)
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		mut valid := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio rpath error'), &char(c'--uid'), &char(c'1000'),
			&char(c'--gid'), &char(c'1000'), &char(c'--unveil'), &char(c'/tmp/data'), &char(c'r'), &char(c'--env'),
			&char(c'TOKEN=$(id);touch /tmp/unsafe'), &char(c'--'), &char(c'/sbin/probe'), &char(c'literal;argument'), &char(c'--uid'), &char(nil)]!
		reset()
		C.assert(run(&valid[0]) == 125 && sandbox_execs == 1)
		C.assert(C.strcmp(sandbox_exec_path, &char(c'/sbin/probe')) == 0)
		C.assert(C.strcmp(sandbox_exec_argv[1], &char(c'literal;argument')) == 0 && C.strcmp(sandbox_exec_argv[2], &char(c'--uid')) == 0 && sandbox_exec_argv[3] == nil)
		C.assert(C.strcmp(sandbox_exec_env[0], &char(c'TOKEN=$(id);touch /tmp/unsafe')) == 0 && sandbox_exec_env[1] == nil)
		C.assert(C.strcmp(sandbox_launcher_promises, &char(c'stdio rpath exec')) == 0)
		C.assert(C.strcmp(sandbox_target_promises, &char(c'stdio rpath error')) == 0 && sandbox_unveiled == 2)
		setup_calls := sandbox_calls
		// Every original setup call must fail closed at its original position.
		for i := i32(1); i <= setup_calls; i++ {
			reset()
			sandbox_fail_at = i
			C.assert(run(&valid[0]) == 125 && sandbox_execs == 0)
		}
		for i := i32(0); i < 5; i++ {
			reset()
			if i == 0 { sandbox_lying_nnp = 1 }
			if i == 1 { sandbox_lying_caps = 1 }
			if i == 2 { sandbox_lying_ids = 1 }
			if i == 3 { sandbox_lying_groups = 1 }
			if i == 4 { sandbox_lying_ambient = 1 }
			C.assert(run(&valid[0]) == 125 && sandbox_execs == 0)
		}
		mut bad01 := [&char(c'vinix-sandbox'), &char(nil)]!
		bad(&bad01[0])
		mut bad02 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--'), &char(c'relative'), &char(nil)]!
		bad(&bad02[0])
		mut bad03 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--uid'), &char(c'1000'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad03[0])
		mut bad04 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--uid'), &char(c'-1'), &char(c'--gid'), &char(c'1000'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad04[0])
		mut bad05 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--uid'), &char(c'4294967295'), &char(c'--gid'), &char(c'1000'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad05[0])
		mut bad06 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--uid'), &char(c'4294967296'), &char(c'--gid'), &char(c'1000'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad06[0])
		mut bad07 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--uid'), &char(c'0'), &char(c'--gid'), &char(c'1000'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad07[0])
		mut bad08 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--gid'), &char(c'1000'), &char(c'--gid'), &char(c'1001'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad08[0])
		mut bad09 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--unveil'), &char(c'/tmp'), &char(c'rZ'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad09[0])
		mut bad10 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--unveil'), &char(c'tmp'), &char(c'r'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad10[0])
		mut bad11 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--unveil'), &char(c'/tmp'), &char(c'r'), &char(c'--unveil'), &char(c'/tmp'), &char(c'rw'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad11[0])
		mut bad12 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--env'), &char(c'1TOKEN=x'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad12[0])
		mut bad13 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--env'), &char(c'TOKEN=x'), &char(c'--env'), &char(c'TOKEN=y'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad13[0])
		mut bad14 := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--promises'), &char(c'rpath'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad14[0])
		mut bad15 := [&char(c'vinix-sandbox'), &char(c'--unknown'), &char(c'--promises'), &char(c'stdio'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		bad(&bad15[0])
		reset()
		mut root_default := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		C.assert(run(&root_default[0]) == 125 && sandbox_execs == 0)
		reset()
		sandbox_groups = 0
		C.memset(&sandbox_current_caps[0], 0, sizeof(sandbox_current_caps))
		for i := i32(0); i < 3; i++ {
			sandbox_uids[i] = 1000
			sandbox_gids[i] = 1000
		}
		mut user_default := [&char(c'vinix-sandbox'), &char(c'--promises'), &char(c'stdio'), &char(c'--'), &char(c'/sbin/probe'), &char(nil)]!
		C.assert(run(&user_default[0]) == 125 && sandbox_execs == 1)
		C.assert(sandbox_exec_env[0] == nil)
		C.puts(&char(c'APPLICATION SANDBOX HOST PASS'))
	}
	return 0
}
