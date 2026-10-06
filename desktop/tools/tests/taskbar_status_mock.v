// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The client tests build platform.c.v without the desktop. Its Terminal launch
// hands the shell a taskbar status file, which taskbar_status.v provides from
// the whole Desktop; these stand in for the two names it uses.
const taskbar_status_env = 'VINIX_TASKBAR_STATUS'

struct TaskbarStatusWriter {
mut:
	path string
}

fn (mut w TaskbarStatusWriter) resolve() {}

__global taskbar_status_writer = TaskbarStatusWriter{}
// Native-client launch code borrows the active profile from registration.
// Device-only fixtures have no registered user.
__global desktop_user_home = ''
