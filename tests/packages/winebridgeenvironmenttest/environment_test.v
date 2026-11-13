// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#define wine_environment_open open
#define wine_environment_close close
#define wine_environment_fcntl fcntl
#define wine_environment_getenv getenv
#define wine_environment_strcmp strcmp
fn C.wine_environment_open(&char, i32, ...i32) i32
fn C.wine_environment_close(i32) i32
fn C.wine_environment_fcntl(i32, i32) i32
fn C.wine_environment_getenv(&char) &char
fn C.wine_environment_strcmp(&char, &char) i32

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

struct SavedVariable { key string value string present bool }

fn need(ok bool, message string) { if !ok { panic(message) } }
fn present(key string, value string) {
	actual := os.getenv_opt(key) or { panic('expected variable is absent: ' + key) }
	defer { unsafe { actual.free() } }
	need(actual == value, 'environment value changed: ' + key)
}
fn absent(key string) {
	if value := os.getenv_opt(key) {
		unsafe { value.free() }
		panic('expected variable is present: ' + key)
	}
}
fn poison() {
	for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV', 'QEMU_UNSET_ENV', 'VINIX_ALLOW_WX', 'WINEDLLOVERRIDES', 'WINEDEBUG']! {
		need(os.setenv(key, 'untrusted override', true) == 0, 'cannot set fixture override')
	}
}
fn cleared() {
	for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV', 'QEMU_UNSET_ENV', 'VINIX_ALLOW_WX', 'WINEDLLOVERRIDES', 'WINEDEBUG']! { absent(key) }
	present('VINIX_APP_ID', 'org.vinix.fixture')
}

// One test owns all environment mutation and restores absent/empty values too.
// Explicit guards remain active in production builds.
fn test_bridge_environment_policy_and_ownership() {
	mut saved := []SavedVariable{cap: 10}
	for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV', 'QEMU_UNSET_ENV', 'VINIX_ALLOW_WX', 'WINEDLLOVERRIDES', 'WINEDEBUG', 'WINESERVERSOCKET', 'VINIX_APP_ID']! {
		mut exists := true
		value := os.getenv_opt(key) or { exists = false; '' }
		saved << SavedVariable{key, value, exists}
	}
	defer {
		for variable in saved {
			result := if variable.present { os.setenv(variable.key, variable.value, true) } else { os.unsetenv(variable.key) }
			need(result == 0, 'cannot restore fixture environment')
			unsafe { variable.value.free() }
		}
		unsafe { (&array(&saved)).free() }
	}
	need(os.setenv('VINIX_APP_ID', 'org.vinix.fixture', true) == 0, 'cannot set SDK fixture context')
	fd := C.wine_environment_open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 3, 'cannot create borrowed descriptor control')
	defer { C.wine_environment_close(fd) }
	flags := C.wine_environment_fcntl(fd, C.F_GETFD)
	text := fd.str()
	defer { unsafe { text.free() } }
	// Top-level values are discarded without parsing or touching the named FD.
	for value in [text, '', '0', '-1', ' 03junk; $literal', '99999999999999999999999999999999']! {
		poison()
		need(os.setenv('WINESERVERSOCKET', value, true) == 0, 'cannot set top-level socket fixture')
		wineadapter.clear_bridge_overrides('wine-runner')!
		absent('WINESERVERSOCKET'); cleared()
		need(C.wine_environment_fcntl(fd, C.F_GETFD) == flags, 'top-level cleanup changed borrowed descriptor')
	}
	// Aliases retain even empty or opaque values; Wine owns their interpretation.
	for mode in ['wine', 'wine64', 'wineserver']! {
		for value in [text, '', ' 03junk; $literal']! {
			poison()
			need(os.setenv('WINESERVERSOCKET', value, true) == 0, 'cannot set alias handoff fixture')
			wineadapter.clear_bridge_overrides(mode)!
			present('WINESERVERSOCKET', value); cleared()
			need(C.wine_environment_fcntl(fd, C.F_GETFD) == flags, 'alias changed handoff descriptor')
		}
		need(os.unsetenv('WINESERVERSOCKET') == 0, 'cannot clear alias fixture')
		wineadapter.clear_bridge_overrides(mode)!
		absent('WINESERVERSOCKET')
	}
	poison()
	need(os.setenv('WINESERVERSOCKET', text, true) == 0, 'cannot set refusal fixture')
	mut rejected := false
	wineadapter.clear_bridge_overrides('unknown') or {
		rejected = err.msg() == 'unknown Wine adapter mode'
		unsafe { err.free() }
	}
	need(rejected, 'unknown bridge mode accepted')
	present('WINESERVERSOCKET', text)
	for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV', 'QEMU_UNSET_ENV', 'VINIX_ALLOW_WX', 'WINEDLLOVERRIDES', 'WINEDEBUG']! { present(key, 'untrusted override') }
	wineadapter.clear_bridge_overrides('wine-runner')!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		need(os.setenv('WINESERVERSOCKET', '03literal', true) == 0, 'cannot set repeated handoff')
		wineadapter.clear_bridge_overrides('wine')!
		value := C.wine_environment_getenv(c'WINESERVERSOCKET')
		need(value != unsafe { nil } && C.wine_environment_strcmp(value, c'03literal') == 0, 'repeated alias handoff changed')
		wineadapter.clear_bridge_overrides('wine-runner')!
		need(C.wine_environment_getenv(c'WINESERVERSOCKET') == unsafe { nil }, 'repeated top-level handoff survived')
	}
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'bridge sanitation retained V bytes') }
	need(C.wine_environment_fcntl(fd, C.F_GETFD) == flags, 'repeated sanitation changed descriptor')
	cleared()
	println('WINE BRIDGE ENVIRONMENT PASS top-level reset; nested handoff; borrowed descriptor; 1000 cycles')
}
