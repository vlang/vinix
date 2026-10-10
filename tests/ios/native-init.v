// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 for the standalone V compatibility checks; no host interpreter.
module main

import os

#include <unistd.h>
#include <sys/wait.h>
#include <stdio.h>

fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pause() i32
fn C.fflush(voidptr) i32

fn run_child(path string, args []string) i32 {
	mut pointers := []&char{}
	pointers << path.str
	for arg in args { pointers << arg.str }
	pointers << &char(unsafe { nil })
	child := C.fork()
	if child < 0 { panic('fork') }
	if child == 0 {
		C.execv(path.str, pointers.data)
		exit(127)
	}
	mut status := i32(0)
	if C.waitpid(child, unsafe { &status }, 0) != child { panic('waitpid') }
	println('IOS-NATIVE: ${path} wait status ${status}')
	C.fflush(unsafe { nil })
	return status
}

fn require_child(path string) {
	if run_child(path, []) != 0 {
		println('IOS-NATIVE: FAIL ' + path)
		C.fflush(unsafe { nil })
		panic('native check failed')
	}
}

fn main() {
	mode := os.read_file('/opt/ios/check-mode') or { panic(err) }
	if mode == 'regression' {
		require_child('/opt/ios/select-checks')
		require_child('/opt/ios/semaphore-checks')
		require_child('/opt/ios/signal-checks')
		require_child('/opt/ios/error-checks')
		require_child('/opt/ios/sysctl-checks')
		require_child('/opt/ios/terminal-checks')
		require_child('/opt/ios/thread-policy-checks')
		require_child('/opt/ios/file-time-checks')
		require_child('/opt/ios/uuid-checks')
		require_child('/opt/ios/audio-session-checks')
		require_child('/opt/ios/cf-dictionary-checks')
		require_child('/opt/ios/objc-storage-checks')
		require_child('/opt/ios/objc-associated-checks')
		require_child('/opt/ios/objc-property-checks')
		require_child('/opt/ios/objc-sync-checks')
		require_child('/opt/ios/swift-string-checks')
		require_child('/opt/ios/swift-metadata-checks')
		require_child('/opt/ios/swift-protocol-checks')
		require_child('/opt/ios/swift-hash-checks')
		require_child('/opt/ios/swift-hasher-checks')
		require_child('/opt/ios/swift-raw-representable-checks')
		require_child('/opt/ios/swift-array-checks')
		require_child('/opt/ios/swift-integer-checks')
		require_child('/opt/ios/swift-integer-hash-checks')
		require_child('/opt/ios/swift-fatal-checks')
		require_child('/opt/ios/regression')
	} else {
		args := if mode == 'audit' {
			['--audit', '/opt/ios/FortniteClient-IOS-Shipping']
		} else {
			['/opt/ios/FortniteClient-IOS-Shipping']
		}
		status := run_child('/opt/ios/run-ios', args)
		println('FORTNITE PROBE: process exit status ${if status & 127 == 0 {
			status >> 8
		} else {
			128 + (status & 127)
		}}')
		println('FORTNITE PROBE COMPLETE')
		C.fflush(unsafe { nil })
	}
	for { C.pause() }
}
