// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import accountcore

$if track_heap ? {
	#include "heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn test_parent_environment_has_independent_ownership_across_logins() {
	user := accountcore.User{
		name:  'alice'
		uid:   1000
		gid:   1000
		home:  '/home/alice'
		shell: '/bin/sh'
	}
	for _ in 0 .. 1000 {
		$if track_heap ? {
			C.vinix_heap_begin()
		}
		inherited := inherited_environment()
		mut environment := session_environment(user, inherited)
		unsafe { inherited.free() }
		assert 'HOME=/home/alice' in environment
		assert 'USER=alice' in environment && 'XDG_RUNTIME_DIR=/run/user/1000' in environment
		environment << 'VINIX_SESSION_FD=3'
		assert environment[environment.len - 1] == 'VINIX_SESSION_FD=3'
		unsafe { environment.free() }
		injected := ['HOME=/root'.clone(), 'VINIX_SESSION_FD=99'.clone(),
			'VINIX_SYSTEM_SESSION=1'.clone(), 'LD_PRELOAD=/root/inject.so'.clone(),
			'XDG_CONFIG_HOME=/root/.config'.clone(), 'LANG=C.UTF-8'.clone()]
		filtered := session_environment(user, injected)
		unsafe { injected.free() }
		assert filtered.len == 7
		assert 'LANG=C.UTF-8' in filtered && 'PATH=/usr/local/bin:/usr/bin:/bin' in filtered
		assert 'HOME=/home/alice' in filtered
		assert !filtered.any(it.contains('/root') || it.starts_with('VINIX_SESSION_FD=')
			|| it.starts_with('VINIX_SYSTEM_SESSION=') || it.starts_with('LD_PRELOAD='))
		unsafe { filtered.free() }
		$if track_heap ? {
			assert C.vinix_heap_end() == 0
		}
	}
}

fn test_session_report_refuses_partial_malformed_and_overflow_ids() {
	for _ in 0 .. 1000 {
		$if track_heap ? {
			C.vinix_heap_begin()
		}
		assert reported_session(c'1\n', 2) == 1
		assert reported_session(c'4294967295\n', 11) == u32(0xffffffff)
		assert reported_session(c'0\n', 2) == 0
		assert reported_session(c'01\n', 3) == 0
		assert reported_session(c'12', 2) == 0
		assert reported_session(c'12\n3', 4) == 0
		assert reported_session(c'4294967296\n', 11) == 0
		assert reported_session(c'-1\n', 3) == 0
		assert reported_session(c' 1\n', 3) == 0
		assert reported_session(c'1\n', 0) == 0
		assert reported_session(c'1\n', -1) == 0
		$if track_heap ? {
			assert C.vinix_heap_end() == 0
		}
	}
}
