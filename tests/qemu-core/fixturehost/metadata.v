// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import hosttest
import json2

fn source_schema(kind string) json2.Any {
	return hosttest.decode_json(match kind {
		'signal' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","signal_range":[543,619],"signal_lines":77,"reference_support_range":[88,95],"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		'touch' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","range":[169,281],"original_lines":113,"reference_support_range":[88,95],"support_translation_credit":0,"adaptation":"Function linkage/names and exact original #line directives only"}'
		}
		'restart' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","restart_range":[620,670],"restart_lines":51,"reference_support_range":[88,95],"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		'nanosleep' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","nanosleep_ranges":[[74,74],[82,86],[710,743]],"nanosleep_lines":40,"reference_support_range":[88,95],"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		'blocked' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","blocked_ranges":[[671,708]],"blocked_lines":38,"reference_support_ranges":[[88,95],[3377,3390]],"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		'poll' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","poll_ranges":[[2404,2425]],"poll_lines":22,"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		'epoll' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","epoll_ranges":[[2501,2530]],"epoll_lines":30,"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		'int' {
			'{"revision":"bbf1e243e21ab58b46a4853c0e88383ff45b290a","path":"tests/qemu-core/test.c","blob":"f6868d5ad82b92c66d62ac8cedfe37892b121b3a","sha256":"3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb","int_ranges":[[2535,2544]],"int_lines":10,"support_translation_credit":0,"adaptation":"Only function linkage/names and exact original #line directives"}'
		}
		else { panic('Unknown core fixture: ' + kind) }
	}) or { panic(err) }
}

fn host_schema(kind string) json2.Any {
	return hosttest.decode_json(match kind {
		'signal' {
			'{"result":"PASS","cases":6,"signal_lines":77,"host_arch":"<arch>","native_OS_calls":"real fork, signals, busy loop, nanosleep, wait/reap","fork_failure_input":"EAGAIN at first or second native fork; exact return/count/errno compared","original_helper_boundary":"Shared immutable original status helper; maintained driver retains exact body","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'touch' {
			'{"result":"PASS","host_arch":"<arch>","cases":5,"original_lines":113,"native_calls":"real mappings/fork/COW/pipes/protection/pthreads/join/reap","shared_API_inputs":"Linux free-memory timeline plus EIO at each of four sysinfo calls","provider_boundary":"Darwin POSIX barriers supplied in V using native mutex/condition; MAP_POPULATE stripped only for host calls","native_guest_required":"actual Linux barrier ABI and physical memory population/accounting","comparison":"return/errno/sysinfo count/ordered API request trace","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'restart' {
			'{"result":"PASS","cases":3,"restart_lines":51,"host_arch":"<arch>","native_OS_calls":"real fork, signals, interrupted pipe read, nanosleep, wait/reap","fork_failure_input":"EAGAIN at first or second native fork; exact return/count/errno compared","original_helper_boundary":"Shared immutable original status helper; maintained driver retains exact body","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'nanosleep' {
			'{"result":"PASS","cases":3,"nanosleep_lines":40,"host_arch":"<arch>","native_OS_calls":"real fork, SIGUSR1, interrupted 1s nanosleep/remainder, wait/reap","fork_failure_input":"EIO at sigaction or EAGAIN at fork; exact return/count/errno compared","original_helper_boundary":"Shared immutable original status helper; maintained driver retains exact body","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'blocked' {
			'{"result":"PASS","cases":6,"blocked_lines":38,"host_arch":"<arch>","native_OS_calls":"real fork, pipe, blocked pthread read, process exit/exec, wait/reap","fork_failure_input":"EAGAIN at both forks or pthread create, EIO at pipe/exec; exact return/count/errno/status compared","original_helper_boundary":"Shared immutable status and exec probe bodies; maintained driver retains both unchanged","host_only_inputs":"Linux auxv constants/nonzero values and /proc auxv read from /dev/zero; exec path redirects to same executable","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'poll' {
			'{"result":"PASS","cases":11,"poll_lines":22,"host_arch":"<arch>","native_OS_calls":"real pipe, poll, write, read, close, independent fork and reap","failure_inputs":"EIO at pipe/poll/write/read/both closes and corrupted event/byte sentinels; exact return/errno/API counts compared","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'epoll' {
			'{"result":"PASS","cases":15,"epoll_lines":30,"host_arch":"<arch>","native_OS_calls":"real pipe, poll, write, read, close, independent fork/reap; Linux epoll host declaration ABI","host_only_provider":"Ephemeral /dev/null epoll descriptor and copied native requested fields, real poll readiness; target guests use actual epoll","failure_inputs":"EIO at pipe/create/ctl/all3waits/write/read/all3closes plus event/data/byte sentinels; exact return/errno/API counts compared","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		'int' {
			'{"result":"PASS","cases":3,"int_lines":10,"host_arch":"<arch>","native_OS_calls":"real native openat/close and independent fork/reap; typed native syscall variadic capture","host_only_provider":"Only host syscall implementation uses native openat with SDK AT_FDCWD; target guests call actual syscall with original zero-extended word","failure_inputs":"EIO at syscall and close; exact return/errno/API counts and native argument bits compared","implicit_allocator_imports":[],"executable_sha256":"<executable_sha256>"}'
		}
		else { panic('Unknown core fixture: ' + kind) }
	}) or { panic(err) }
}

fn native_schema(kind string) json2.Any {
	return hosttest.decode_json(match kind {
		'signal' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","reference_helper":"Exact original retained reap body, no translation credit","implicit_allocator_imports":[]}'
		}
		'touch' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","reference_helper":"Exact original retained reap body, no translation credit","implicit_allocator_imports":[]}'
		}
		'restart' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","reference_helper":"Exact original retained reap body, no translation credit","implicit_allocator_imports":[]}'
		}
		'nanosleep' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","reference_helper":"Exact retained original reap body, no translation credit","implicit_allocator_imports":[]}'
		}
		'blocked' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","reference_helper":"Exact retained original reap body, no translation credit","implicit_allocator_imports":[]}'
		}
		'poll' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","comparison":"Exact original poll ABI body and ten original checksites, real native OS calls","implicit_allocator_imports":[]}'
		}
		'epoll' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","comparison":"Exact original epoll ABI body and fourteen original checksites, actual native epoll calls","implicit_allocator_imports":[]}'
		}
		'int' {
			'{"result":"PASS","arch":"<arch>","commands":[],"executable_sha256":"<executable_sha256>","comparison":"Exact original syscall C-int body and two original checksites, actual native syscall calls","implicit_allocator_imports":[]}'
		}
		else { panic('Unknown core fixture: ' + kind) }
	}) or { panic(err) }
}

fn missing_marker(kind string) string {
	return match kind {
		'signal' { 'Missing native signal differential verdict' }
		'touch' { 'Missing differential verdict' }
		'restart' { 'Missing native restart differential verdict' }
		'nanosleep' { 'Missing native interrupted nanosleep differential verdict' }
		'blocked' { 'Missing native blocked-thread differential verdict' }
		'poll' { 'Missing native poll differential verdict' }
		'epoll' { 'Missing native epoll differential verdict' }
		'int' { 'Missing native int differential verdict' }
		else { 'Missing differential verdict' }
	}
}
