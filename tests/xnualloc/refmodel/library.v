// Copyright (c) 2000-2020 Apple Inc. All rights reserved.
//
// @APPLE_OSREFERENCE_LICENSE_HEADER_START@
//
// This file contains Original Code and/or Modifications of Original Code
// as defined in and that are subject to the Apple Public Source License
// Version 2.0 (the 'License'). You may not use this file except in
// compliance with the License. The rights granted to you under the License
// may not be used to create, or enable the creation or redistribution of,
// unlawful or unlicensed copies of an Apple operating system, or to
// circumvent, violate, or enable the circumvention or violation of, any
// terms of an Apple operating system software license agreement.
//
// Please obtain a copy of the License at
// http://www.opensource.apple.com/apsl/ and read it before using this file.
//
// The Original Code and all software distributed under the License are
// distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
// EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
// INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
// Please see the License for the specific language governing rights and
// limitations under the License.
//
// @APPLE_OSREFERENCE_LICENSE_HEADER_END@
// @OSF_COPYRIGHT@
// Mach Operating System
// Copyright (c) 1991,1990,1989,1988,1987 Carnegie Mellon University
// All Rights Reserved.
//
// Permission to use, copy, modify and distribute this software and its
// documentation is hereby granted, provided that both the copyright
// notice and this permission notice appear in all copies of the
// software, derivative works or modified versions, and any portions
// thereof, and that both notices appear in supporting documentation.
//
// CARNEGIE MELLON ALLOWS FREE USE OF THIS SOFTWARE IN ITS "AS IS"
// CONDITION.  CARNEGIE MELLON DISCLAIMS ANY LIABILITY OF ANY KIND FOR
// ANY DAMAGES WHATSOEVER RESULTING FROM THE USE OF THIS SOFTWARE.
//
// Carnegie Mellon requests users of this software to return to
//
// Software Distribution Coordinator  or  Software.Distribution@CS.CMU.EDU
// School of Computer Science
// Carnegie Mellon University
// Pittsburgh PA 15213-3890
//
// any improvements or extensions that they make and grant Carnegie Mellon
// the rights to redistribute these changes.
// Modified 2026-09-11: Python differential harness and translated buddy model.
// Upstream: apple-oss-distributions/xnu f6217f891ac0bb64f3d375211650a4c1ff8ca1ea,
// osfmk/kern/zalloc.c. See docs/xnualloc/PORT_STATUS.md and
// kernel/xnualloc/APPLE_LICENSE.
// These translations retain APSL 2.0; they are NOT relicensed as GPL.
//
//
// Build and load the unchanged independent C fixture with UBSan.
module refmodel

import os

#flag linux -ldl
#include <dlfcn.h>
#include <stdlib.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlerror() &char
fn C.dlclose(voidptr) i32
fn C.mkdtemp(&char) &char

type BuddyInit = fn (u32) i32
type BuddyAlloc = fn (u32, bool) u64
type BuddyFree = fn (u64, u32, bool)
type BuddySnapshot = fn (voidptr)
type BuddyDestroy = fn ()
type Scan = fn (&u64, u32, u64) u64
type Merge = fn (&u64, u32, u32)
type MarkFree = fn (&u64, u64) bool

pub struct Reference {
	handle voidptr
pub:
	initialize BuddyInit @[required]
	allocate   BuddyAlloc @[required]
	release    BuddyFree @[required]
	snapshot   BuddySnapshot @[required]
	destroy    BuddyDestroy @[required]
	scan       Scan @[required]
	merge      Merge @[required]
	mark_free  MarkFree @[required]
}

pub fn temporary() !string {
	mut bytes := (os.join_path(os.temp_dir(), 'xnu-reference-XXXXXX') + '\x00').bytes()
	pointer := unsafe { C.mkdtemp(&char(bytes.data)) }
	if pointer == unsafe { nil } { return os.error_posix() }
	return unsafe { cstring_to_vstring(pointer) }
}

fn loader_error() IError {
	pointer := C.dlerror()
	return error(if pointer == unsafe { nil } { 'Could not load reference fixture' } else { unsafe { cstring_to_vstring(pointer) } })
}

fn symbol(handle voidptr, name string) !voidptr {
	pointer := C.dlsym(handle, name.str)
	if pointer == unsafe { nil } { return loader_error() }
	return pointer
}

pub fn load(shift int, destination string, root string) !Reference {
	output := os.join_path(destination, 'ref${shift}.so')
	mut flags := ['-fsanitize=undefined', '-fno-sanitize-recover=all']
	$if macos { flags = ['-fsanitize=undefined', '-fsanitize-trap=undefined'] }
	mut args := ['-std=c11', '-D_POSIX_C_SOURCE=200809L', '-DPAGE_MAX_SHIFT=${shift}', '-O1', '-g', '-Wall', '-Wextra', '-Werror']
	args << flags
	args << ['-shared', '-fPIC', os.join_path(root, 'tests/xnualloc/reference.c'), '-o', output]
	mut process := os.new_process(os.getenv_opt('CC') or { 'cc' })
	process.set_args(args)
	process.run()
	defer { process.close() }
	if process.pid <= 0 { return error('Cannot start C reference compiler: ' + process.err) }
	process.wait()
	if process.code != 0 { return error('C reference compiler exited ${process.code}') }
	handle := C.dlopen(output.str, C.RTLD_NOW)
	if handle == unsafe { nil } { return loader_error() }
	mut ready := false
	defer { if !ready { C.dlclose(handle) } }
	result := Reference{
		handle: handle
		initialize: unsafe { BuddyInit(symbol(handle, 'ref_buddy_init')!) }
		allocate: unsafe { BuddyAlloc(symbol(handle, 'ref_buddy_alloc')!) }
		release: unsafe { BuddyFree(symbol(handle, 'ref_buddy_free')!) }
		snapshot: unsafe { BuddySnapshot(symbol(handle, 'ref_buddy_snapshot')!) }
		destroy: unsafe { BuddyDestroy(symbol(handle, 'ref_buddy_destroy')!) }
		scan: unsafe { Scan(symbol(handle, 'ref_scan64')!) }
		merge: unsafe { Merge(symbol(handle, 'ref_merge64')!) }
		mark_free: unsafe { MarkFree(symbol(handle, 'ref_mark_free64')!) }
	}
	ready = true
	return result
}

pub fn (reference Reference) close() {
	reference.destroy()
	C.dlclose(reference.handle)
}
