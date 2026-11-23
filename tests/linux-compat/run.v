// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct CaseResult {
	name          string
	source_sha256 string
	source_inputs map[string]string
	init_sha256   string
	iso_sha256    string
	exit_code     int
	detail        string
}

struct Receipt {
	architecture  string
	context       string = 'QEMU guest; native musl ELF64'
	kernel_sha256 string
	results       []CaseResult
}

fn digest(path string) string {
	bytes := os.read_bytes(path) or { return '' }
	return sha256.sum(bytes).hex()
}

fn fixture_files(name string) []string {
	// compile_init compiles the complete frozen module directory. Install the
	// five qualified semwait sources together so every compiled input is pinned.
	return if name == 'semwait' {
		['core.v', 'snapshot.v', 'storage.v', 'queued.v', 'lifetime.v']
	} else if name in ['selecttimeout','ppolltime','ppollsignal'] {
		['core.v', 'storage.v', 'bounds.v']
	} else if name in ['selectempty', 'execown', 'selectfds', 'selectword', 'selectorder', 'selecttimeout', 'selecttimeval', 'ppollargs', 'pollcount', 'ppolltime', 'ppollsignal', 'pollcopy', 'selectwake', 'pipeready', 'epollkey', 'epollchurn'] {
		['core.v', 'storage.v']
	} else {
		['core.v']
	}
}

fn freeze_fixture(source string, frozen string, names []string) !map[string]string {
	os.mkdir_all(frozen)!
	mut inputs := map[string]string{}
	for name in names {
		path := source + '/' + name
		bytes := os.read_bytes(path)!
		os.write_file_array(frozen + '/' + name, bytes)!
		inputs[path] = sha256.sum(bytes).hex()
	}
	return inputs
}

fn fixture_timeout(name string, requested int, explicit bool) int {
	if explicit { return requested }
	// These probes include repeated reclamation grace periods and SMP churn.
	return if name in ['ppollsignal','selectwake','pipeready','epollkey','epollchurn'] { 600 } else if name == 'semwait' { 7200 } else if name == 'procns' { 1200 }
		else if name in ['execown', 'selectfds', 'selectbad', 'selectword', 'selectorder', 'selecttimeout', 'selecttimeval', 'ppollargs', 'pollcount', 'ppolltime', 'ppollsignal', 'pollcopy', 'selectwake', 'pipeready', 'epollkey', 'epollchurn'] { 300 } else { requested }
}

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--cases', value: true },
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: tests/linux-compat/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--cases bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,futex2,mseal,textbusy,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd,iovstream,iovpacket,opathseek,scalarabi,seekerror,seekextent,truncateaccess,truncateabi,truncatepath,readlinkabi,readlinkempty,procself,execnames,statx,statabi,dupabi,duppublish,fcntlabi,fcntlpath,fcntlquery,fcntlcreated,fcntlsync,ofdlocks,lockrange,lockaccess,flocksame,fcntlsig,fcntlowner,ownerquery,proctask,procpid,accessflags,pipeabi,pipepair,pipenull,pipecmd,pipesize,schedabi,schext,rrabi,attrquery,attrimport,affabi,attrnice,rtadmit,idleexit,attrclass,niceabi,niceadmit,threadnice,prioquery,priochange,priozombie,randomflags,randomcopy,randomrange,randomsignal,groupabi,grouptid,grouporder,groupzombie,waitabi,pidfdwait,waitempty,waituid,waitevent,waitusage,waitconsume,waitstatus,robustquery,robustwake,robustcreds,tidwake,tidfault,tidlast,clonesignal,clonecgroup,clonestack,cloneflags,cloneclear,cloneextend,clonetidpair,clonetidcopy,cloneparent,clonefsns,clonethreadns,clonecgshare,clonecgparent,clonecgperm,clonefuture,clonepidguard,cloneipc,procns,semwait,semabi,semword,sempid,semarray,semrange,semperm,semmeta,seminfo,semns,semundo,shmremap,shmflags,shmabi,shmset,shmtime,shmremove,shmimport,sigpending,sigwaitcopy,sigwaitorder,altstackcopy,sigmaskcopy,sigactioncopy,sigactionabi,altstackabi,altstackhandler,altstacksp,altstackframe,altstacknest,altstackrestore,altstackclone,autodisarm,sigactionflags,resethand,maskwait,selectempty,selectready,execown,selectfds,selectbad,selectword,selectorder,selecttimeout,selecttimeval,ppollargs,pollcount,ppolltime,ppollsignal,pollcopy,selectwake,pipeready,epollkey,epollchurn,kcmp,ioprio,personality,pidfdgetfd,fchmodat2,readahead,syslog,sigqueue,fsuid,mqueue] [--timeout SECONDS]') or {
		eprintln(err.msg())
		exit(2)
	}
	for key in ['--arch', '--kernel-dir', '--state-dir'] {
		if !options.has(key) {
			eprintln('missing ' + key)
			exit(2)
		}
	}
	arch := options.value('--arch', '')
	timeout := options.integer('--timeout', 180) or {
		eprintln(err.msg())
		exit(2)
	}
	cases := options.value('--cases', 'bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,futex2,mseal,textbusy,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd,iovstream,iovpacket,opathseek,scalarabi,seekerror,seekextent,truncateaccess,truncateabi,truncatepath,readlinkabi,readlinkempty,procself,execnames,statx,statabi,dupabi,duppublish,fcntlabi,fcntlpath,fcntlquery,fcntlcreated,fcntlsync,ofdlocks,lockrange,lockaccess,flocksame,fcntlsig,fcntlowner,ownerquery,proctask,procpid,accessflags,pipeabi,pipepair,pipenull,pipecmd,pipesize,schedabi,schext,rrabi,attrquery,attrimport,affabi,attrnice,rtadmit,idleexit,attrclass,niceabi,niceadmit,threadnice,prioquery,priochange,priozombie,randomflags,randomcopy,randomrange,randomsignal,groupabi,grouptid,grouporder,groupzombie,waitabi,pidfdwait,waitempty,waituid,waitevent,waitusage,waitconsume,waitstatus,robustquery,robustwake,robustcreds,tidwake,tidfault,tidlast,clonesignal,clonecgroup,clonestack,cloneflags,cloneclear,cloneextend,clonetidpair,clonetidcopy,cloneparent,clonefsns,clonethreadns,clonecgshare,clonecgparent,clonecgperm,clonefuture,clonepidguard,cloneipc,procns,semwait,semabi,semword,sempid,semarray,semrange,semperm,semmeta,seminfo,semns,semundo,shmremap,shmflags,shmabi,shmset,shmtime,shmremove,shmimport,sigpending,sigwaitcopy,sigwaitorder,altstackcopy,sigmaskcopy,sigactioncopy,sigactionabi,altstackabi,altstackhandler,altstacksp,altstackframe,altstacknest,altstackrestore,altstackclone,autodisarm,sigactionflags,resethand,maskwait,selectempty,selectready,execown,selectfds,selectbad,selectword,selectorder,selecttimeout,selecttimeval,ppollargs,ppolltime,ppollsignal,pollcopy,selectwake,pipeready,epollkey,epollchurn,kcmp,ioprio,personality,pidfdgetfd,fchmodat2,readahead,syslog,userns').split(',')
	mut seen := map[string]bool{}
	for name in cases {
		if name == 'pollcount' && arch != 'x86_64' { eprintln('pollcount requires native x86-64 poll'); exit(2) }
		if name !in ['bpf', 'access', 'open', 'mmap', 'runtime', 'namespace', 'sharedmem', 'seccomp', 'futex', 'futexkeys', 'futexbits', 'futexop', 'futexerror', 'futexqueue', 'futex2', 'mseal', 'textbusy', 'sparsefork', 'seccompquery', 'budget', 'mapstorage', 'sysrq', 'jit', 'nnp', 'nnpthread', 'keepcaps', 'securebits', 'ambient', 'capbset', 'capset', 'cappid', 'capabi', 'seccompthread', 'seccompkill', 'seccompinstall', 'seccompalloc', 'sysnr', 'pipezero', 'readerror', 'pathio', 'iovpin', 'iovimport', 'iovrange', 'iovoffset', 'iovposition', 'iovflags', 'iovfd', 'iovstream', 'iovpacket', 'opathseek', 'scalarabi', 'seekerror', 'seekextent', 'truncateaccess', 'truncateabi', 'truncatepath', 'readlinkabi', 'readlinkempty', 'procself', 'execnames', 'statx', 'statabi', 'dupabi', 'duppublish', 'fcntlabi', 'fcntlpath', 'fcntlquery', 'fcntlcreated', 'fcntlsync', 'ofdlocks', 'lockrange', 'lockaccess', 'flocksame', 'fcntlsig', 'fcntlowner', 'ownerquery', 'proctask', 'procpid', 'accessflags', 'pipeabi', 'pipepair', 'pipenull', 'pipecmd', 'pipesize', 'schedabi', 'schext', 'rrabi', 'attrquery', 'attrimport', 'affabi', 'attrnice', 'rtadmit', 'idleexit', 'attrclass', 'niceabi', 'niceadmit', 'threadnice', 'prioquery', 'priochange', 'priozombie', 'randomflags', 'randomcopy', 'randomrange', 'randomsignal', 'groupabi', 'grouptid', 'grouporder', 'groupzombie', 'waitabi', 'pidfdwait', 'waitempty', 'waituid', 'waitevent', 'waitusage', 'waitconsume', 'waitstatus', 'robustquery', 'robustwake', 'robustcreds', 'tidwake', 'tidfault', 'tidlast', 'clonesignal', 'clonecgroup', 'clonestack', 'cloneflags', 'cloneclear', 'cloneextend', 'clonetidpair', 'clonetidcopy', 'cloneparent', 'clonefsns', 'clonethreadns', 'clonecgshare', 'clonecgparent', 'clonecgperm', 'clonefuture', 'clonepidguard', 'cloneipc', 'procns', 'semwait', 'semabi', 'semword', 'sempid', 'semarray', 'semrange', 'semperm', 'semmeta', 'seminfo', 'semns', 'semundo', 'shmremap', 'shmflags', 'shmabi', 'shmset', 'shmtime', 'shmremove', 'shmimport', 'sigpending', 'sigwaitcopy', 'sigwaitorder', 'altstackcopy', 'sigmaskcopy', 'sigactioncopy', 'sigactionabi', 'altstackabi', 'altstackhandler', 'altstacksp', 'altstackframe', 'altstacknest', 'altstackrestore', 'altstackclone', 'autodisarm', 'sigactionflags', 'resethand', 'maskwait', 'selectempty', 'selectready', 'execown', 'selectfds', 'selectbad', 'selectword', 'selectorder', 'selecttimeout', 'selecttimeval', 'ppollargs', 'pollcount', 'ppolltime', 'ppollsignal', 'pollcopy', 'selectwake', 'pipeready', 'epollkey', 'epollchurn', 'kcmp', 'ioprio', 'personality', 'pidfdgetfd', 'fchmodat2', 'readahead', 'syslog', 'sigqueue', 'fsuid', 'mqueue', 'userns'] || name in seen {
			eprintln('unknown or repeated case: ' + name)
			exit(2)
		}
		seen[name] = true
	}
	if timeout <= 0 {
		eprintln('timeout must be positive')
		exit(2)
	}
	kernel := os.real_path(options.value('--kernel-dir', '') + '/bin/vinix')
	header := os.read_bytes(kernel) or {
		eprintln(err.msg())
		exit(2)
	}
	machine := if header.len >= 20 { int(header[18]) + (int(header[19]) << 8) } else { 0 }
	if header.len < 20 || header[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' {
		183
	} else {
		62
	} {
		eprintln('kernel must be a matching little-endian ELF64')
		exit(2)
	}
	state := options.value('--state-dir', '')
	if os.exists(state) {
		eprintln('state directory must be fresh')
		exit(2)
	}
	os.mkdir_all(state + '/kernel/bin') or {
		eprintln(err.msg())
		exit(1)
	}
	work := os.real_path(state)
	// Freeze the exact read bytes, even if another build replaces the input.
	os.write_file_array(work + '/kernel/bin/vinix', header) or {
		eprintln(err.msg())
		exit(1)
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut results := []CaseResult{}
	for name in cases {
		source_dir := root + '/tests/linux-compat/' + name + 'fixture'
		frozen_source := work + '/sources/' + name + 'fixture'
		source_inputs := freeze_fixture(source_dir, frozen_source, fixture_files(name)) or {
			eprintln(err.msg())
			exit(1)
		}
		marker := 'LINUX ' + name.to_upper() + ': PASS'
		case_timeout := fixture_timeout(name, timeout, options.has('--timeout'))
		mut detail := ''
		code := guesthost.guest(frozen_source + '/core.v', '', work + '/' + name, work + '/kernel', arch,
			if added := added_markers(name, arch, marker) {
				added
			} else if name == 'runtime' {
				[marker, 'LINUX RUNTIME PASS: atomics SIMD TLS', 'LINUX RUNTIME PASS: JIT page sizes']
			} else if name == 'priozombie' {
				[marker, 'LINUX PRIOZOMBIE SUMMARY: checks=1728 failures=0']
			} else if name == 'priochange' {
				[marker, 'LINUX PRIOCHANGE SUMMARY: checks=23508 failures=0']
			} else if name == 'prioquery' {
				[marker, 'LINUX PRIOQUERY SUMMARY: checks=6199 failures=0']
			} else if name == 'semabi' {
				[marker, 'LINUX SEMABI SUMMARY: checks=175 failures=0']
			} else if name == 'semword' {
				[marker, 'LINUX SEMWORD SUMMARY: checks=276 failures=0']
			} else if name == 'sempid' {
				[marker, 'LINUX SEMPID SUMMARY: checks=261 failures=0']
			} else if name == 'semarray' {
				[marker, 'LINUX SEMARRAY SUMMARY: checks=457 failures=0']
			} else if name == 'semrange' {
				[marker, 'LINUX SEMRANGE SUMMARY: checks=4200 failures=0']
			} else if name == 'sigactionflags' {
				[marker, 'LINUX SIGACTIONFLAGS SUMMARY: checks=6480 failures=0']
			} else if name == 'selectready' {
				[marker, 'LINUX SELECTREADY SUMMARY: checks=' + (if arch == 'aarch64' { '6720' } else { '8960' }) + ' failures=0']
			} else if name == 'epollchurn' {
				[marker, 'LINUX EPOLLCHURN SUMMARY: checks=5760 failures=0']
			} else if name == 'epollkey' {
				[marker, 'LINUX EPOLLKEY SUMMARY: checks=5760 failures=0']
			} else if name == 'pipeready' {
				[marker, 'LINUX PIPEREADY SUMMARY: checks=' + (if arch == 'aarch64' { '24180' } else { '30960' }) + ' failures=0']
			} else if name == 'selectwake' {
				[marker, 'LINUX SELECTWAKE SUMMARY: checks=' + (if arch == 'aarch64' { '5040' } else { '6720' }) + ' failures=0']
			} else if name == 'pollcopy' {
				[marker, 'LINUX POLLCOPY SUMMARY: checks=' + (if arch == 'aarch64' { '10368' } else { '13824' }) + ' failures=0']
			} else if name == 'pollcount' {
				[marker, 'LINUX POLLCOUNT SUMMARY: checks=350 failures=0']
			} else if name == 'ppollsignal' {
				[marker, 'LINUX PPOLLSIGNAL SUMMARY: checks=672 failures=0']
			} else if name == 'ppolltime' {
				[marker, 'LINUX PPOLLTIME SUMMARY: checks=360 failures=0']
			} else if name == 'ppollargs' {
				[marker, 'LINUX PPOLLARGS SUMMARY: checks=19600 failures=0']
			} else if name == 'selecttimeval' {
				[marker, 'LINUX SELECTTIMEVAL SUMMARY: checks=' + (if arch == 'aarch64' { '5184' } else { '10368' }) + ' failures=0']
			} else if name == 'selecttimeout' {
				[marker, 'LINUX SELECTTIMEOUT SUMMARY: checks=' + (if arch == 'aarch64' { '1536' } else { '2208' }) + ' failures=0']
			} else if name == 'selectorder' {
				[marker, 'LINUX SELECTORDER SUMMARY: checks=' + (if arch == 'aarch64' { '9720' } else { '11340' }) + ' failures=0']
			} else if name == 'selectword' {
				[marker, 'LINUX SELECTWORD SUMMARY: checks=' + (if arch == 'aarch64' { '45780' } else { '91560' }) + ' failures=0']
			} else if name == 'selectfds' {
				[marker, 'LINUX SELECTFDS SUMMARY: checks=' + (if arch == 'aarch64' { '54252' } else { '72336' }) + ' failures=0']
			} else if name == 'selectbad' {
				[marker, 'LINUX SELECTBAD SUMMARY: checks=' + (if arch == 'aarch64' { '2520' } else { '3360' }) + ' failures=0']
			} else if name == 'execown' {
				[marker, 'LINUX EXECOWN SUMMARY: checks=14 failures=0']
			} else if name == 'selectempty' {
				[marker, 'LINUX SELECTEMPTY SUMMARY: checks=' + (if arch == 'aarch64' { '2176' } else { '2752' }) + ' failures=0']
			} else if name == 'maskwait' {
				[marker, 'LINUX MASKWAIT SUMMARY: checks=1256 failures=0']
			} else if name == 'resethand' {
				[marker, 'LINUX RESETHAND SUMMARY: checks=420 failures=0']
			} else if name == 'autodisarm' {
				[marker, 'LINUX AUTODISARM SUMMARY: checks=1560 failures=0']
			} else if name == 'altstackclone' {
				[marker, 'LINUX ALTSTACKCLONE SUMMARY: checks=1440 failures=0']
			} else if name == 'altstackrestore' {
				[marker, 'LINUX ALTSTACKRESTORE SUMMARY: checks=952 failures=0']
			} else if name == 'altstacknest' {
				[marker, 'LINUX ALTSTACKNEST SUMMARY: checks=592 failures=0']
			} else if name == 'altstackframe' {
				[marker, 'LINUX ALTSTACKFRAME SUMMARY: checks=272 failures=0']
			} else if name == 'altstacksp' {
				[marker, 'LINUX ALTSTACKSP SUMMARY: checks=388 failures=0']
			} else if name == 'altstackhandler' {
				[marker, 'LINUX ALTSTACKHANDLER SUMMARY: checks=19444 failures=0']
			} else if name == 'altstackabi' {
				[marker, 'LINUX ALTSTACKABI SUMMARY: checks=38880 failures=0']
			} else if name == 'sigactionabi' {
				[marker, 'LINUX SIGACTIONABI SUMMARY: checks=56000 failures=0']
			} else if name == 'sigactioncopy' {
				[marker, 'LINUX SIGACTIONCOPY SUMMARY: checks=4440 failures=0']
			} else if name == 'sigmaskcopy' {
				[marker, 'LINUX SIGMASKCOPY SUMMARY: checks=3984 failures=0']
			} else if name == 'altstackcopy' {
				[marker, 'LINUX ALTSTACKCOPY SUMMARY: checks=560 failures=0']
			} else if name == 'sigwaitorder' {
				[marker, 'LINUX SIGWAITORDER SUMMARY: checks=27968 failures=0']
			} else if name == 'sigwaitcopy' {
				[marker, 'LINUX SIGWAITCOPY SUMMARY: checks=1488 failures=0']
			} else if name == 'sigpending' {
				[marker, 'LINUX SIGPENDING SUMMARY: checks=428 failures=0']
			} else if name == 'shmimport' {
				[marker, 'LINUX SHMIMPORT SUMMARY: checks=218 failures=0']
			} else if name == 'shmremove' {
				[marker, 'LINUX SHMREMOVE SUMMARY: checks=301 failures=0']
			} else if name == 'shmtime' {
				[marker, 'LINUX SHMTIME SUMMARY: checks=175 failures=0']
			} else if name == 'shmset' {
				[marker, 'LINUX SHMSET SUMMARY: checks=398 failures=0']
			} else if name == 'shmabi' {
				[marker, 'LINUX SHMABI SUMMARY: checks=243 failures=0']
			} else if name == 'shmflags' {
				[marker, 'LINUX SHMFLAGS SUMMARY: checks=1763 failures=0']
			} else if name == 'shmremap' {
				[marker, 'LINUX SHMREMAP SUMMARY: checks=1101 failures=0']
			} else if name == 'semundo' {
				[marker, 'LINUX SEMUNDO SUMMARY: checks=1643 failures=0']
			} else if name == 'semns' {
				[marker, 'LINUX SEMNS SUMMARY: checks=446 failures=0', 'LINUX SEMNS STORAGE: arrays=200 semaphores=6400 big_pages=']
			} else if name == 'seminfo' {
				[marker, 'LINUX SEMINFO SUMMARY: checks=11965 failures=0']
			} else if name == 'semmeta' {
				[marker, 'LINUX SEMMETA SUMMARY: checks=28713 failures=0']
			} else if name == 'semperm' {
				[marker, 'LINUX SEMPERM SUMMARY: checks=256552 failures=0']
			} else if name == 'sysrq' {
				[marker, 'sysrq: pid=1 ppid=0 tid=1']
			} else {
				[marker]
			},
			['LINUX ' + name.to_upper() + ' FAIL'], false, true, case_timeout) or {
			detail = err.msg()
			1
		}
		results << CaseResult{
			name: name
			source_sha256: source_inputs[source_dir + '/core.v']
			source_inputs: source_inputs
			init_sha256: digest(work + '/' + name + '/init')
			iso_sha256: digest(work + '/' + name + '/test.iso')
			exit_code: code
			detail: detail
		}
		os.write_file(work + '/receipt.json', json2.encode(Receipt{ architecture: arch, kernel_sha256: sha256.sum(header).hex(), results: results },
			prettify: true
		) + '\n') or {
			eprintln(err.msg())
			exit(1)
		}
	}
	if results.any(it.exit_code != 0) {
		eprintln('Linux compatibility qualification failed; see ' + work + '/receipt.json')
		exit(1)
	}
	println('Linux compatibility guest suite: PASS')
}

// The summary lines of the cases added since the chain above grew past what
// one if expression can hold.
fn added_markers(name string, arch string, marker string) ?[]string {
	return match name {
		'kcmp' { [marker, 'LINUX KCMP SUMMARY: checks=66 failures=0', 'LINUX KCMP CHILD: checks=8 failures=0'] }
		'ioprio' { [marker, 'LINUX IOPRIO SUMMARY: checks=45 failures=0', 'LINUX IOPRIO VALIDATION: checks=63 failures=0', 'LINUX IOPRIO CHILD: checks=13 failures=0'] }
		'personality' { [marker, 'LINUX PERSONALITY SUMMARY: checks=' + (if arch == 'aarch64' { '39' } else { '40' }) + ' failures=0'] }
		'pidfdgetfd' { [marker, 'LINUX PIDFDGETFD SUMMARY: checks=20 failures=0', 'LINUX PIDFDGETFD CHILD: checks=3 failures=0'] }
		'fchmodat2' { [marker, 'LINUX FCHMODAT2 SUMMARY: checks=33 failures=0', 'LINUX FCHMODAT2 CHILD: checks=3 failures=0'] }
		'readahead' { [marker, 'LINUX READAHEAD SUMMARY: checks=22 failures=0'] }
		'syslog' { [marker, 'LINUX SYSLOG SUMMARY: checks=35 failures=0', 'LINUX SYSLOG CHILD: checks=10 failures=0'] }
		'sigqueue' { [marker, 'LINUX SIGQUEUE SUMMARY: checks=44 failures=0'] }
		'fsuid' { [marker, 'LINUX FSUID SUMMARY: checks=20 failures=0', 'LINUX FSUID CHILD: checks=22 failures=0'] }
		'mqueue' { [marker, 'LINUX MQUEUE SUMMARY: checks=257 failures=0', 'LINUX MQUEUE CHILD: checks=16 failures=0'] }
		'futex2' { [marker, 'LINUX FUTEX2 SUMMARY: checks=86 failures=0'] }
		'mseal' { [marker, 'LINUX MSEAL SUMMARY: checks=' + (if arch == 'aarch64' { '168' } else { '167' }) + ' failures=0'] }
		'textbusy' { [marker, 'LINUX TEXTBUSY SUMMARY: writer and image lifetime controls passed'] }
		'userns' { [marker, 'LINUX USERNS SUMMARY: checks=16 failures=0', 'LINUX USERNS CHILD: checks=6 failures=0', 'LINUX USERNS SANDBOX: checks=56 failures=0', 'LINUX USERNS JAIL: checks=2 failures=0', 'LINUX USERNS MASK: checks=3 failures=0', 'LINUX USERNS THREAD FS: checks=7 failures=0'] }
		else { none }
	}
}
