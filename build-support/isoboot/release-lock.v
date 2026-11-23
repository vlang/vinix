// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <errno.h>
#include <sys/file.h>

fn C.flock(int, int) int

// deploy-iso.sh opens its work directory on this descriptor before invoking
// the helper. The shell retains the same open file description after it exits.
const workspace_fd = 9

fn run() ! {
	if os.args.len != 2 { return error('usage: release-lock lock|unlock') }
	operation := match os.args[1] {
		'lock' { C.LOCK_EX | C.LOCK_NB }
		'unlock' { C.LOCK_UN }
		else { return error('usage: release-lock lock|unlock') }
	}
	for C.flock(workspace_fd, operation) != 0 {
		if C.errno == C.EINTR { continue }
		if C.errno in [C.EAGAIN, C.EWOULDBLOCK]! {
			return error('another ISO release is using build-release/work')
		}
		return error('cannot ${os.args[1]} the ISO release workspace: ${os.last_error()}')
	}
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
