// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

pub fn abi_suites() []string {
	return ['abi-scratch', 'capability-exec', 'stack-policy', 'syscall-policy', 'dumpability',
		'shared-streams', 'posix-timer', 'socket-io', 'procfs-allocs', 'network-options',
		'terminal-jobs', 'securelevel', 'execute-only', 'procfs-mount', 'clock-control']
}

fn abi_spec(family string) !AbiSpec {
	return match family {
		'abi-scratch' {
			AbiSpec{ family: 'abi-scratch', module_name: '', features: [
				'ABI SCRATCH PASS: stat records and errors',
				'ABI SCRATCH PASS: poll readiness and signals',
				'ABI SCRATCH PASS: allocation loops',
			], pass: 'ABI SCRATCH GUEST: PASS', failures: ['ABI SCRATCH FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'capability-exec' {
			AbiSpec{ family: 'capability-exec', module_name: '', features: [
				'CAP EXEC PASS: ordinary root exec retains bounding-set behavior',
				'CAP EXEC PASS: no_new_privs prevents root capability regain across repeated exec',
				'CAP EXEC PASS: no_new_privs preserves only previously permitted low and high bits',
				'CAP EXEC PASS: mixed credentials retain capability ceiling and secure-loader state',
				'CAP EXEC PASS: Linux ambient commands and capset maintain the permitted-inheritable invariant',
				'CAP EXEC PASS: valid nonroot ambient privilege survives no_new_privs exec',
			], pass: 'CAP EXEC GUEST: PASS', failures: ['CAP EXEC FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'stack-policy' {
			AbiSpec{ family: 'stack-policy', module_name: '', features: [
				'STACK POLICY PASS: tagging and audit',
				'STACK POLICY PASS: enforcement and inheritance',
			], pass: 'STACK POLICY GUEST: PASS', failures: ['STACK POLICY FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'syscall-policy' {
			AbiSpec{ family: 'syscall-policy', module_name: '', features: [
				'SYSCALL POLICY PASS: installation validation',
				'SYSCALL POLICY PASS: audit and enforcement',
				'SYSCALL POLICY PASS: inheritance and lifetime',
			], pass: 'SYSCALL POLICY GUEST: PASS', failures: ['SYSCALL POLICY FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'dumpability' {
			AbiSpec{ family: 'dumpability', module_name: 'dumpfixture', features: [
				'DUMPABILITY PASS: same uid cannot inspect nondumpable peer',
				'DUMPABILITY PASS: same uid can inspect enabled peer',
			], pass: 'DUMPABILITY GUEST: PASS', failures: ['DUMPABILITY FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'shared-streams' {
			AbiSpec{ family: 'shared-streams', module_name: 'streamfixture', features: [
				'SHARED STREAMS PASS: pipe',
				'SHARED STREAMS PASS: socket',
				'SHARED STREAMS PASS: terminal',
				'SHARED STREAMS PASS: offsets',
			], pass: 'SHARED STREAMS GUEST: PASS', failures: ['SHARED STREAMS FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'posix-timer' {
			AbiSpec{ family: 'posix-timer', module_name: 'timerfixture', features: [
				'POSIX TIMER PASS: musl callback',
				'POSIX TIMER PASS: thread-id',
				'POSIX TIMER PASS: synchronous',
				'POSIX TIMER PASS: ordinary signals',
				'POSIX TIMER PASS: ownership',
			], pass: 'POSIX TIMER GUEST: PASS', failures: ['POSIX TIMER FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'socket-io' {
			AbiSpec{ family: 'socket-io', module_name: 'socketfixture', features: [
				'SOCKET IO PASS: flags',
				'SOCKET IO PASS: rights',
				'SOCKET IO PASS: growth',
			], pass: 'SOCKET IO GUEST: PASS', failures: ['SOCKET IO FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'procfs-allocs' {
			AbiSpec{ family: 'procfs-allocs', module_name: '', features: [
				'PROCFS ALLOCS PASS: contents',
				'PROCFS ALLOCS PASS: records',
				'PROCFS ALLOCS PASS: growth',
			], pass: 'PROCFS ALLOCS GUEST: PASS', failures: ['PROCFS ALLOCS FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'network-options' {
			AbiSpec{ family: 'network-options', module_name: '', features: [
				'NETWORK OPTIONS PASS: transport settings and bounds',
				'NETWORK OPTIONS PASS: unsupported network changes fail',
				'NETWORK OPTIONS PASS: linger waits and times out',
				'NETWORK OPTIONS PASS: exit keeps linger in background',
			], pass: 'NETWORK OPTIONS GUEST: PASS', failures: ['NETWORK OPTIONS FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'terminal-jobs' {
			AbiSpec{ family: 'terminal-jobs', module_name: 'guestfixture', features: [
				'TERMINAL NONROOT PTY',
				'TERMINAL JOBS PASS: permissions and sessions',
				'TERMINAL JOBS PASS: stop and foreground signals',
				'TERMINAL OWNED OPEN rounds=100 errors=0',
			], pass: 'TERMINAL JOBS GUEST: PASS', failures: ['TERMINAL JOBS FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'securelevel' {
			AbiSpec{ family: 'securelevel', module_name: 'securefixture', features: [
				'SECURELEVEL PASS: sealed domain and level transitions',
				'SECURELEVEL PASS: existing disk descriptions are protected',
				'SECURELEVEL PASS: ordinary filesystem writes remain available',
			], pass: 'SECURELEVEL GUEST: PASS', failures: ['SECURELEVEL FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'execute-only' {
			AbiSpec{ family: 'execute-only', module_name: 'execfixture', features: [
				'EXECUTE ONLY PASS: permissions and checked copies',
				'EXECUTE ONLY PASS: fork split remap and demand paging',
			], pass: 'EXECUTE ONLY GUEST: PASS', failures: ['EXECUTE ONLY FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'procfs-mount' {
			AbiSpec{ family: 'procfs-mount', module_name: 'mountfixture', features: [
				'PROC MOUNT PASS: self mounts fail without damaging proc paths or mountinfo',
				'PROC MOUNT PASS: independent aliases and remounts remain usable',
				'PROC MOUNT PASS: inactive view reuse rejects self edges before retarget, concurrently',
				'PROC MOUNT PASS: fresh PID namespace views remain mountable and reject cycles',
				'PROC MOUNT PASS: cached roots cannot cover their own descendants',
			], pass: 'PROC MOUNT GUEST: PASS', failures: ['PROC MOUNT FAIL', 'FATAL EXCEPTION',
				'KERNEL PANIC'] }
		}
		'clock-control' {
			AbiSpec{ family: 'clock-control', module_name: 'clockfixture', features: [
				'CLOCK CONTROL PASS: wall steps preserve uptime',
				'CLOCK CONTROL PASS: discipline ABI validates modes and bounds',
				'CLOCK CONTROL PASS: privilege and securelevel guard changes',
				'CLOCK CONTROL PASS: realtime steps adjust sleeps and absolute timers',
			], pass: 'VINIX CLOCK CONTROL: PASS', failures: [
				'VINIX CLOCK CONTROL: FAIL',
				'CLOCK CONTROL FAIL',
				'FATAL EXCEPTION',
				'KERNEL PANIC',
			] }
		}
		else { return error('Unknown ABI suite: ' + family) }
	}
}
