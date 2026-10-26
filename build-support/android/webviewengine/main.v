// SPDX-License-Identifier: GPL-2.0-or-later
// Separate, principal-owned WebKit engine. Never load this into the ART libc.
module main

import os
import time

#include <signal.h>

fn C.signal(i32, voidptr) voidptr

fn run() ! {
	$if !linux {
		return error('engine supports the Linux AArch64 runtime only')
	}
	$if !arm64 {
		return error('engine supports the Linux AArch64 runtime only')
	}
	$if !vgc ? {
		return error('engine must be built with -gc vgc')
	}
	if os.args.len != 5 || os.args[1] != '--control-fd' || os.args[3] != '--profile' {
		return error('usage: webview-engine --control-fd N --profile ABSOLUTE_DIRECTORY')
	}
	fd := os.args[2].int()
	if fd < 3 || fd.str() != os.args[2] { return error('invalid control descriptor') }
	if os.getuid() < 10000 || os.getuid() > 19999 || os.geteuid() != os.getuid()
		|| os.getegid() != os.getgid() {
		return error('exclusive application UID required')
	}
	control(fd)!
	C.umask(0o077)
	private_profile := profile(os.args[4])!
	profile_lock := lock_profile(private_profile)!
	defer { C.close(i32(profile_lock)) }
	if os.getenv('DISPLAY') == '' || os.getenv('GDK_BACKEND') != 'x11' {
		return error('private X11 display required')
	}
	authority := os.getenv('XAUTHORITY')
	if authority == '' { return error('private Xauthority required') }
	stat := os.lstat(authority)!
	if stat.mode & 0o170000 != 0o100000 || stat.mode & 0o7777 != 0o600
		|| stat.uid != u32(os.getuid()) || stat.nlink != 1 {
		return error('invalid private Xauthority')
	}
	// The local diagnostic intentionally disables the sandbox. Production
	// never inherits that exception, even when the kernel cannot launch it.
	if os.getenv('WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS') != '' {
		return error('browser sandbox bypass is forbidden')
	}
	C.signal(C.SIGPIPE, C.SIG_IGN)
	a := api()!
	if a.webkit_major() != 2 || a.webkit_minor() != 48 || a.webkit_micro() != 1
		|| a.gtk_major() != 4 || a.gtk_minor() != 24 || a.gtk_micro() != 1 {
		return error('unqualified browser library versions')
	}
	if a.init() == 0 { return error('private display initialization failed') }
	data := private_profile + '/data'
	cache := private_profile + '/cache'
	session := a.session_new(data.str, cache.str)
	if session == unsafe { nil } { return error('network session creation failed') }
	defer { a.unref(session) }
	cookies := a.session_cookies(session)
	if cookies == unsafe { nil } { return error('cookie manager unavailable') }
	jar := private_profile + '/data/cookies.sqlite'
	for suffix in ['', '-wal', '-shm', '-journal'] { private_file(jar + suffix)! }
	// WebKitGTK does not enable persistent cookies merely because the network
	// session has data/cache directories. Storage enum SQLITE=1 in 2.48.1.
	a.cookie_storage(cookies, jar.str, 1)
	mut engine := &Engine{ api: a, fd: fd, session: session, cookies: cookies }
	for !engine.closed {
		engine.read()
		a.iterate(unsafe { nil }, 0)
		engine.tick()
		engine.flush()
		for _, job in engine.jobs {
			if time.sys_mono_now() >= job.deadline {
				engine.closed = true
				break
			}
		}
		for _, job in engine.text_jobs {
			if time.sys_mono_now() >= job.deadline {
				engine.closed = true
				break
			}
		}
		mut ready := C.pollfd{
			fd:     i32(fd)
			events: (if engine.text_jobs.len == 0 && !engine.input_pending {
				C.POLLIN
			} else {
				i16(0)
			}) | if engine.output.len > 0 {
				C.POLLOUT
			} else {
				i16(0)
			}
		}
		if C.poll(&ready, 1, 5) < 0 && C.errno != C.EINTR { engine.closed = true }
	}
	engine.state.close()
	mut views := []&EngineView{}
	for _, view in engine.views { views << view }
	for view in views { engine.destroy(view) }
	C.close(i32(fd))
}

fn main() {
	run() or {
		// Errors contain fixed setup codes and never incoming browser payloads.
		eprintln('webview-engine: ${err}')
		exit(1)
	}
}
