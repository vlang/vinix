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

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--cases', value: true },
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: tests/linux-compat/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--cases bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd,iovstream,iovpacket,opathseek,scalarabi,seekerror,seekextent,truncateaccess,truncateabi,truncatepath,readlinkabi,readlinkempty,procself,execnames,statx,statabi,dupabi,duppublish,fcntlabi,fcntlpath,fcntlquery,fcntlcreated,fcntlsync,ofdlocks,lockrange,lockaccess,flocksame,fcntlsig,fcntlowner,ownerquery,proctask,procpid,accessflags,pipeabi,pipepair,pipenull,pipecmd,pipesize,schedabi,schext,rrabi,attrquery,attrimport,affabi,attrnice,rtadmit,idleexit] [--timeout SECONDS]') or {
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
	cases := options.value('--cases', 'bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd,iovstream,iovpacket,opathseek,scalarabi,seekerror,seekextent,truncateaccess,truncateabi,truncatepath,readlinkabi,readlinkempty,procself,execnames,statx,statabi,dupabi,duppublish,fcntlabi,fcntlpath,fcntlquery,fcntlcreated,fcntlsync,ofdlocks,lockrange,lockaccess,flocksame,fcntlsig,fcntlowner,ownerquery,proctask,procpid,accessflags,pipeabi,pipepair,pipenull,pipecmd,pipesize,schedabi,schext,rrabi,attrquery,attrimport,affabi,attrnice,rtadmit,idleexit').split(',')
	mut seen := map[string]bool{}
	for name in cases {
		if name !in ['bpf', 'access', 'open', 'mmap', 'runtime', 'namespace', 'sharedmem', 'seccomp', 'futex', 'futexkeys', 'futexbits', 'futexop', 'futexerror', 'futexqueue', 'sparsefork', 'seccompquery', 'budget', 'mapstorage', 'sysrq', 'jit', 'nnp', 'nnpthread', 'keepcaps', 'securebits', 'ambient', 'capbset', 'capset', 'cappid', 'capabi', 'seccompthread', 'seccompkill', 'seccompinstall', 'seccompalloc', 'sysnr', 'pipezero', 'readerror', 'pathio', 'iovpin', 'iovimport', 'iovrange', 'iovoffset', 'iovposition', 'iovflags', 'iovfd', 'iovstream', 'iovpacket', 'opathseek', 'scalarabi', 'seekerror', 'seekextent', 'truncateaccess', 'truncateabi', 'truncatepath', 'readlinkabi', 'readlinkempty', 'procself', 'execnames', 'statx', 'statabi', 'dupabi', 'duppublish', 'fcntlabi', 'fcntlpath', 'fcntlquery', 'fcntlcreated', 'fcntlsync', 'ofdlocks', 'lockrange', 'lockaccess', 'flocksame', 'fcntlsig', 'fcntlowner', 'ownerquery', 'proctask', 'procpid', 'accessflags', 'pipeabi', 'pipepair', 'pipenull', 'pipecmd', 'pipesize', 'schedabi', 'schext', 'rrabi', 'attrquery', 'attrimport', 'affabi', 'attrnice', 'rtadmit', 'idleexit'] || name in seen {
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
		source := root + '/tests/linux-compat/' + name + 'fixture/core.v'
		source_text := os.read_file(source) or {
			eprintln(err.msg())
			exit(1)
		}
		frozen_source := work + '/sources/' + name + 'fixture'
		os.mkdir_all(frozen_source) or {
			eprintln(err.msg())
			exit(1)
		}
		os.write_file(frozen_source + '/core.v', source_text) or {
			eprintln(err.msg())
			exit(1)
		}
		marker := 'LINUX ' + name.to_upper() + ': PASS'
		mut detail := ''
		code := guesthost.guest(frozen_source + '/core.v', '', work + '/' + name, work + '/kernel', arch,
			if name == 'runtime' {
				[marker, 'LINUX RUNTIME PASS: atomics SIMD TLS', 'LINUX RUNTIME PASS: JIT page sizes']
			} else if name == 'sysrq' {
				[marker, 'sysrq: pid=1 ppid=0 tid=1']
			} else {
				[marker]
			},
			['LINUX ' + name.to_upper() + ' FAIL'], false, true, timeout) or {
			detail = err.msg()
			1
		}
		results << CaseResult{name, sha256.sum(source_text.bytes()).hex(), digest(work + '/' + name + '/init'), digest(work + '/' + name + '/test.iso'), code, detail}
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
