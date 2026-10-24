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
	return if name == 'semwait' { 7200 } else if name == 'procns' { 1200 } else { requested }
}

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--cases', value: true },
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: tests/linux-compat/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--cases bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd,iovstream,iovpacket,opathseek,scalarabi,seekerror,seekextent,truncateaccess,truncateabi,truncatepath,readlinkabi,readlinkempty,procself,execnames,statx,statabi,dupabi,duppublish,fcntlabi,fcntlpath,fcntlquery,fcntlcreated,fcntlsync,ofdlocks,lockrange,lockaccess,flocksame,fcntlsig,fcntlowner,ownerquery,proctask,procpid,accessflags,pipeabi,pipepair,pipenull,pipecmd,pipesize,schedabi,schext,rrabi,attrquery,attrimport,affabi,attrnice,rtadmit,idleexit,attrclass,niceabi,niceadmit,threadnice,prioquery,priochange,priozombie,randomflags,randomcopy,randomrange,randomsignal,groupabi,grouptid,grouporder,groupzombie,waitabi,waitempty,waituid,waitevent,waitusage,waitconsume,waitstatus,robustquery,robustwake,robustcreds,tidwake,tidfault,tidlast,clonesignal,clonecgroup,clonestack,cloneflags,cloneclear,cloneextend,clonetidpair,clonetidcopy,cloneparent,clonefsns,clonethreadns,clonecgshare,clonecgparent,clonecgperm,clonefuture,clonepidguard,cloneipc,procns,semwait,semabi,semword,sempid,semarray,semrange,semperm,semmeta,seminfo,semns,semundo,shmremap] [--timeout SECONDS]') or {
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
	cases := options.value('--cases', 'bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd,iovstream,iovpacket,opathseek,scalarabi,seekerror,seekextent,truncateaccess,truncateabi,truncatepath,readlinkabi,readlinkempty,procself,execnames,statx,statabi,dupabi,duppublish,fcntlabi,fcntlpath,fcntlquery,fcntlcreated,fcntlsync,ofdlocks,lockrange,lockaccess,flocksame,fcntlsig,fcntlowner,ownerquery,proctask,procpid,accessflags,pipeabi,pipepair,pipenull,pipecmd,pipesize,schedabi,schext,rrabi,attrquery,attrimport,affabi,attrnice,rtadmit,idleexit,attrclass,niceabi,niceadmit,threadnice,prioquery,priochange,priozombie,randomflags,randomcopy,randomrange,randomsignal,groupabi,grouptid,grouporder,groupzombie,waitabi,waitempty,waituid,waitevent,waitusage,waitconsume,waitstatus,robustquery,robustwake,robustcreds,tidwake,tidfault,tidlast,clonesignal,clonecgroup,clonestack,cloneflags,cloneclear,cloneextend,clonetidpair,clonetidcopy,cloneparent,clonefsns,clonethreadns,clonecgshare,clonecgparent,clonecgperm,clonefuture,clonepidguard,cloneipc,procns,semwait,semabi,semword,sempid,semarray,semrange,semperm,semmeta,seminfo,semns,semundo,shmremap').split(',')
	mut seen := map[string]bool{}
	for name in cases {
		if name !in ['bpf', 'access', 'open', 'mmap', 'runtime', 'namespace', 'sharedmem', 'seccomp', 'futex', 'futexkeys', 'futexbits', 'futexop', 'futexerror', 'futexqueue', 'sparsefork', 'seccompquery', 'budget', 'mapstorage', 'sysrq', 'jit', 'nnp', 'nnpthread', 'keepcaps', 'securebits', 'ambient', 'capbset', 'capset', 'cappid', 'capabi', 'seccompthread', 'seccompkill', 'seccompinstall', 'seccompalloc', 'sysnr', 'pipezero', 'readerror', 'pathio', 'iovpin', 'iovimport', 'iovrange', 'iovoffset', 'iovposition', 'iovflags', 'iovfd', 'iovstream', 'iovpacket', 'opathseek', 'scalarabi', 'seekerror', 'seekextent', 'truncateaccess', 'truncateabi', 'truncatepath', 'readlinkabi', 'readlinkempty', 'procself', 'execnames', 'statx', 'statabi', 'dupabi', 'duppublish', 'fcntlabi', 'fcntlpath', 'fcntlquery', 'fcntlcreated', 'fcntlsync', 'ofdlocks', 'lockrange', 'lockaccess', 'flocksame', 'fcntlsig', 'fcntlowner', 'ownerquery', 'proctask', 'procpid', 'accessflags', 'pipeabi', 'pipepair', 'pipenull', 'pipecmd', 'pipesize', 'schedabi', 'schext', 'rrabi', 'attrquery', 'attrimport', 'affabi', 'attrnice', 'rtadmit', 'idleexit', 'attrclass', 'niceabi', 'niceadmit', 'threadnice', 'prioquery', 'priochange', 'priozombie', 'randomflags', 'randomcopy', 'randomrange', 'randomsignal', 'groupabi', 'grouptid', 'grouporder', 'groupzombie', 'waitabi', 'waitempty', 'waituid', 'waitevent', 'waitusage', 'waitconsume', 'waitstatus', 'robustquery', 'robustwake', 'robustcreds', 'tidwake', 'tidfault', 'tidlast', 'clonesignal', 'clonecgroup', 'clonestack', 'cloneflags', 'cloneclear', 'cloneextend', 'clonetidpair', 'clonetidcopy', 'cloneparent', 'clonefsns', 'clonethreadns', 'clonecgshare', 'clonecgparent', 'clonecgperm', 'clonefuture', 'clonepidguard', 'cloneipc', 'procns', 'semwait', 'semabi', 'semword', 'sempid', 'semarray', 'semrange', 'semperm', 'semmeta', 'seminfo', 'semns', 'semundo', 'shmremap'] || name in seen {
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
			if name == 'runtime' {
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
