// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit administrator-selected Unix credentials for a native APK process.
// This is not an account allocator or a per-package isolation service.
module nativeidentity

import os

#flag linux -D_GNU_SOURCE
#include <unistd.h>
#include <grp.h>
#include <pwd.h>
#include <errno.h>
#include <sys/resource.h>

struct C.rlimit {
pub:
	rlim_cur u64
	rlim_max u64
}

fn C.getrlimit(int, &C.rlimit) int
fn C.setrlimit(int, &C.rlimit) int

$if linux {
	#include <sys/prctl.h>
}

fn C.getuid() u32
fn C.geteuid() u32
fn C.getpwuid(u32) voidptr
fn C.getgrgid(u32) voidptr
fn C.getresuid(&u32, &u32, &u32) int
fn C.getresgid(&u32, &u32, &u32) int
fn C.setresuid(u32, u32, u32) int
fn C.setresgid(u32, u32, u32) int
fn C.getgroups(int, voidptr) int
fn C.setgroups(usize, voidptr) int
fn C.access(&char, int) int
fn C.prctl(int, u64, u64, u64, u64) int
fn C.syscall(i64, ...voidptr) i64

struct CapabilityHeader {
	version u32 = 0x20080522
	pid     i32
}

struct CapabilitySet {
	effective   u32
	permitted   u32
	inheritable u32
}

pub struct Config {
pub:
	enabled bool
	uid     u32
	gid     u32
	data    string
	home    string
}

pub fn parse(uid string, gid string, data string, home string) !Config {
	for value in [uid, gid] {
		if value.len != 5 || !value.bytes().all(it >= `0` && it <= `9`)
			|| value.int() < 10000 || value.int() > 19999 {
			return error('VINIX_ANDROID_UID and VINIX_ANDROID_GID must both be in 10000..19999')
		}
	}
	if !os.is_abs_path(data) || !os.is_abs_path(home) {
		return error('credential launch requires absolute ANDROID_APP_DATA_DIR and VINIX_ANDROID_HOME')
	}
	return Config{ enabled: true, uid: uid.u32(), gid: gid.u32(), data: data, home: home }
}

pub fn from_environment() !Config {
	environment := os.environ()
	if 'VINIX_ANDROID_UID' !in environment && 'VINIX_ANDROID_GID' !in environment {
		return Config{}
	}
	return parse(os.getenv('VINIX_ANDROID_UID'), os.getenv('VINIX_ANDROID_GID'),
		os.getenv('ANDROID_APP_DATA_DIR'), os.getenv('VINIX_ANDROID_HOME'))
}

fn (config Config) owned_directory(path string) ! {
	info := os.lstat(path)!
	if info.get_filetype() != .directory || info.uid != config.uid || info.gid != config.gid {
		return error('credential launch directory must be owned by target UID/GID: ' + path)
	}
}

fn (config Config) account() ! {
	if C.getpwuid(config.uid) == unsafe { nil } || C.getgrgid(config.gid) == unsafe { nil } {
		return error('credential launch requires a pre-provisioned Unix account and group for target UID/GID')
	}
}

fn accessible(path string, mode int) ! {
	if unsafe { C.access(&char(path.str), mode) } != 0 {
		return error('credential launch cannot access: ' + path)
	}
}

fn readable_runtime(path string, mut visited map[string]bool) ! {
	accessible(path, if os.is_dir(path) { 5 } else { 4 })!
	if os.is_dir(path) {
		canonical := os.real_path(path)
		if canonical in visited { return }
		visited[canonical] = true
		for name in os.ls(path)! { readable_runtime(path + '/' + name, mut visited)! }
	}
}

fn (config Config) surface(path string) ! {
	if !os.is_abs_path(path) {
		return error('credential launch requires an absolute VINIX_SURFACE_PATH')
	}
	accessible(os.dir(path), 3)!
	info := os.lstat(path) or {
		// Parent traversal and write access were checked under the actual target
		// credentials. A missing file is created by the native WS runtime.
		if err.code() != C.ENOENT { return err }
		return
	}
	if info.get_filetype() != .regular || info.uid != config.uid || info.gid != config.gid
		|| info.nlink != 1 {
		return error('credential launch surface must be fresh or a regular target-owned file: ' + path)
	}
	accessible(path, 6)!
}

fn (config Config) verify() ! {
	$if linux {
		mut nice := C.rlimit{}
		mut realtime := C.rlimit{}
		if C.getrlimit(C.RLIMIT_NICE, &nice) != 0 || nice.rlim_cur != 40 || nice.rlim_max != 40
			|| C.getrlimit(C.RLIMIT_RTPRIO, &realtime) != 0 || realtime.rlim_cur != 0 || realtime.rlim_max != 0 {
			return error('credential launch did not retain bounded Android scheduling limits')
		}
		mut real := u32(0)
		mut effective := u32(0)
		mut saved := u32(0)
		if C.getresuid(&real, &effective, &saved) != 0 || real != config.uid
			|| effective != config.uid || saved != config.uid {
			return error('credential launch did not change every user ID')
		}
		if C.getresgid(&real, &effective, &saved) != 0 || real != config.gid
			|| effective != config.gid || saved != config.gid || C.getgroups(0, unsafe { nil }) != 0 {
			return error('credential launch did not clear the original groups')
		}
		if C.prctl(39, 0, 0, 0, 0) != 1 {
			return error('credential launch did not retain no_new_privs')
		}
		header := CapabilityHeader{}
		mut sets := [2]CapabilitySet{}
		get := $if amd64 { i64(125) } $else { i64(90) }
		if C.syscall(get, &header, &sets[0]) != 0 {
			return error('cannot verify credential launch capabilities')
		}
		for set in sets {
			if set.effective != 0 || set.permitted != 0 || set.inheritable != 0 {
				return error('credential launch retained capabilities')
			}
		}
		if C.setresuid(0, 0, 0) == 0 { return error('credential launch could regain root') }
	}
}

// Returns only with the selected credentials and accessible launch inputs.
// On error the caller must exit: the credential change is intentionally one way.
pub fn (config Config) activate(apk string, runtime string, surface string) ! {
	if !config.enabled { return }
	$if linux {
		if C.getuid() != 0 || C.geteuid() != 0 {
			return error('credential launch requires real and effective Unix root')
		}
		if !os.is_abs_path(apk) || !os.is_abs_path(runtime) {
			return error('credential launch requires absolute APK and VINIX_ANDROID_ROOT paths')
		}
		config.account()!
		config.owned_directory(config.data)!
		config.owned_directory(config.home)!
		// Android init admits fair nice values -20..19 through RLIMIT_NICE.
		// Resource admission remains independent of the kernel's UID checks and
		// grants no real-time scheduling privilege or capability to the app.
		nice := C.rlimit{rlim_cur: 40, rlim_max: 40}
		realtime := C.rlimit{}
		if C.setrlimit(C.RLIMIT_NICE, &nice) != 0 || C.setrlimit(C.RLIMIT_RTPRIO, &realtime) != 0 {
			return error('cannot establish bounded Android scheduling limits')
		}
		for capability in 0 .. 64 {
			if C.prctl(23, u64(capability), 0, 0, 0) == 1 && C.prctl(24, u64(capability), 0, 0, 0) != 0 {
				return error('cannot drop credential launch capability bounding set')
			}
		}
		if C.prctl(47, 4, 0, 0, 0) != 0 || C.prctl(8, 0, 0, 0, 0) != 0
			|| C.setgroups(0, unsafe { nil }) != 0
			|| C.setresgid(config.gid, config.gid, config.gid) != 0
			|| C.setresuid(config.uid, config.uid, config.uid) != 0 {
			return error('cannot permanently change credential launch IDs and groups')
		}
		header := CapabilityHeader{}
		empty := [2]CapabilitySet{}
		set := $if amd64 { i64(126) } $else { i64(91) }
		if C.syscall(set, &header, &empty[0]) != 0 || C.prctl(38, 1, 0, 0, 0) != 0 {
			return error('cannot clear credential launch capabilities or set no_new_privs')
		}
		config.verify()!
		config.account()!
		for path in [config.data, config.home] { accessible(path, 7)! }
		if !os.is_file(apk) { return error('credential launch APK is not a regular file') }
		accessible(apk, 4)!
		if !os.is_dir(runtime) { return error('credential launch runtime is not a directory') }
		mut visited := map[string]bool{}
		readable_runtime(runtime, mut visited)!
		for path in [runtime + '/lib/ld-musl-aarch64.so.1', runtime + '/usr/bin/vinix-android-native'] {
			accessible(path, 5)!
		}
		config.surface(surface)!
		os.chdir(config.data)!
		os.setenv('HOME', config.home, true)
		for name, suffix in {
			'XDG_DATA_HOME':   '/.local/share'
			'XDG_CONFIG_HOME': '/.config'
			'XDG_CACHE_HOME':  '/.cache'
			'XDG_STATE_HOME':  '/.local/state'
		} {
			os.setenv(name, config.home + suffix, true)
		}
		for name in ['USER', 'LOGNAME', 'XDG_RUNTIME_DIR'] { os.unsetenv(name) }
	} $else {
		return error('credential launch requires the Linux credential ABI')
	}
}
