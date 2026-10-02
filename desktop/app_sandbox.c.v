// SPDX-License-Identifier: GPL-2.0-or-later
// Calculator needs only its existing compositor pipes and anonymous memory
// once its model and translations have been initialized. Apply the boundary
// before accepting any application-protocol input. Host UI tests run without
// Vinix syscalls; Vinix never continues after a failed security operation.
module main

struct AppSandboxCapHeader {
	version u32 = 0x20080522
	pid     i32
}

struct AppSandboxCapData {
	effective   u32
	permitted   u32
	inheritable u32
}

fn native_app_has_sandbox(name string) bool {
	return name == 'vinix-calculator'
}

fn native_app_apply_sandbox(options AppProcessOptions) ! {
	if !native_app_has_sandbox(options.name) {
		return
	}
	if options.request_fd < 3 || options.response_fd < 3
		|| options.request_fd > 2147483647 || options.response_fd > 2147483647
		|| options.request_fd == options.response_fd {
		return error('invalid application sandbox pipe descriptors')
	}
	$if linux || vinix {
		unsafe {
			mut prctl_nr := i32(167)
			mut uname_nr := i32(160)
			mut capget_nr := i32(90)
			mut capset_nr := i32(91)
			mut getgroups_nr := i32(158)
			mut setgroups_nr := i32(159)
			mut getresgid_nr := i32(150)
			mut getresuid_nr := i32(148)
			mut setresgid_nr := i32(149)
			mut setresuid_nr := i32(147)
			mut unveil_nr := i32(249)
			mut pledge_nr := i32(248)
			$if amd64 {
				prctl_nr = 157
				uname_nr = 63
				capget_nr = 125
				capset_nr = 126
				getgroups_nr = 115
				setgroups_nr = 116
				getresgid_nr = 120
				getresuid_nr = 118
				setresgid_nr = 119
				setresuid_nr = 117
				unveil_nr = 502
				pledge_nr = 501
			}
			// Production desktop binaries target the Linux libc ABI. Identify the
			// running kernel directly, before dropping privileges; the host's Linux
			// UI tests must not issue Vinix-specific syscall numbers.
			mut platform := [390]u8{}
			if C.syscall(uname_nr, &platform[0]) != 0 {
				return error('could not identify the running kernel')
			}
			is_vinix := platform[0] == `V` && platform[1] == `i` && platform[2] == `n`
				&& platform[3] == `i` && platform[4] == `x` && platform[5] == 0
			// In a private UTS namespace Vinix reports Linux to applications,
			// but keeps its kernel-owned -vinix release suffix.
			mut release_end := 130
			for release_end < 195 && platform[release_end] != 0 {
				release_end++
			}
			is_container := release_end >= 136 && platform[release_end - 6] == `-`
				&& platform[release_end - 5] == `v` && platform[release_end - 4] == `i`
				&& platform[release_end - 3] == `n` && platform[release_end - 2] == `i`
				&& platform[release_end - 1] == `x`
			if !is_vinix && !is_container {
				return
			}
			if C.syscall(prctl_nr, voidptr(38), voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0
				|| C.syscall(prctl_nr, voidptr(39), voidptr(0), voidptr(0), voidptr(0), voidptr(0)) != 1 {
				return error('could not enforce no_new_privs')
			}
			if C.syscall(prctl_nr, voidptr(47), voidptr(4), voidptr(0), voidptr(0), voidptr(0)) != 0 {
				return error('could not clear ambient capabilities')
			}
			groups := C.syscall(getgroups_nr, voidptr(0), voidptr(0))
			if groups < 0 || (groups > 0 && C.syscall(setgroups_nr, voidptr(0), voidptr(0)) != 0)
				|| C.syscall(getgroups_nr, voidptr(0), voidptr(0)) != 0 {
				return error('could not clear supplementary groups')
			}
			if C.syscall(prctl_nr, voidptr(8), voidptr(0), voidptr(0), voidptr(0), voidptr(0)) != 0 {
				return error('could not disable keepcaps')
			}
			// Collapse real/effective/saved IDs, including a saved root identity.
			// This purely computational app needs no privileged user or group.
			mut uids := [3]u32{}
			mut gids := [3]u32{}
			if C.syscall(getresuid_nr, &uids[0], &uids[1], &uids[2]) != 0
				|| C.syscall(getresgid_nr, &gids[0], &gids[1], &gids[2]) != 0 {
				return error('could not read process credentials')
			}
			mut target_uid := uids[1]
			mut target_gid := gids[1]
			for i in 0 .. 3 {
				if uids[i] == 0 || gids[i] == 0 {
					target_uid = 65534
					target_gid = 65534
				}
			}
			if C.syscall(setresgid_nr, voidptr(target_gid), voidptr(target_gid), voidptr(target_gid)) != 0
				|| C.syscall(setresuid_nr, voidptr(target_uid), voidptr(target_uid), voidptr(target_uid)) != 0 {
				return error('could not drop privileged credentials')
			}
			if C.syscall(getresuid_nr, &uids[0], &uids[1], &uids[2]) != 0
				|| C.syscall(getresgid_nr, &gids[0], &gids[1], &gids[2]) != 0 {
				return error('could not verify process credentials')
			}
			for i in 0 .. 3 {
				if uids[i] != target_uid || gids[i] != target_gid {
					return error('credential removal was not enforced')
				}
			}
			header := AppSandboxCapHeader{}
			mut capabilities := [2]AppSandboxCapData{}
			if C.syscall(capset_nr, &header, &capabilities[0]) != 0 {
				return error('could not clear capabilities')
			}
			if C.syscall(capget_nr, &header, &capabilities[0]) != 0 {
				return error('could not verify capability removal')
			}
			for capability in capabilities {
				if capability.effective != 0 || capability.permitted != 0 || capability.inheritable != 0 {
					return error('capability removal was not enforced')
				}
			}
			for capability in 0 .. 41 {
				if C.syscall(prctl_nr, voidptr(47), voidptr(3), voidptr(capability), voidptr(0), voidptr(0)) != 0 {
					return error('ambient capability removal was not enforced')
				}
			}
			// Close every inherited descriptor except the protocol channels and
			// standard streams; their descriptor numbers need not be adjacent.
			first := u32(if options.request_fd < options.response_fd {
				options.request_fd
			} else {
				options.response_fd
			})
			last := u32(if options.request_fd > options.response_fd {
				options.request_fd
			} else {
				options.response_fd
			})
			if (first > 3 && C.syscall(436, voidptr(3), voidptr(first - 1), voidptr(0)) != 0)
				|| (last > first + 1 && C.syscall(436, voidptr(first + 1), voidptr(last - 1), voidptr(0)) != 0)
				|| C.syscall(436, voidptr(last + 1), voidptr(~u32(0)), voidptr(0)) != 0 {
				return error('could not close inherited descriptors')
			}
			if C.syscall(unveil_nr, voidptr(0), voidptr(0)) != 0 {
				return error('could not lock an empty filesystem view')
			}
			// Giving exec an explicit empty promise set also prevents an accidental
			// future change from resetting the locked filesystem view on exec.
			if C.syscall(pledge_nr, c'stdio', c'') != 0 {
				return error('could not enforce calculator promises')
			}
		}
	}
}
