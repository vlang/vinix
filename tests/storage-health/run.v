// SPDX-License-Identifier: GPL-2.0-or-later
// Native V host controller for unchanged production SMART/ioctl code.
module main

import os

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('Command failed: ${args[0]}\n${result.output}') }
	return result.output
}

fn put(work string, name string, content string) ! {
	path := work + '/' + name
	os.mkdir_all(os.dir(path))!
	os.write_file(path, content)!
}

fn function(source string, name string) !string {
	mut position := 0
	for line in source.split_into_lines() {
		if line.starts_with('fn ') && (line.contains(' ${name}(') || line.starts_with('fn ${name}(')) {
			mut end := position + (line.index('{') or { return error('Missing brace') }) + 1
			mut depth := 1
			for end < source.len && depth != 0 {
				if source[end] == `{` { depth++ }
				if source[end] == `}` { depth-- }
				end++
			}
			if depth != 0 { return error('Unterminated production function') }
			return source[position..end] + '\n'
		}
		position += line.len + 1
	}
	return error('Missing production function ${name}')
}

fn host(root string, work string) ! {
	put(work, 'v.mod', "Module { name: 'storage_health_host' }\n")!
	put(work, 'pci/pci.v', 'module pci\npub struct PCIBar {}\n')!
	put(work, 'devcore/core.v', 'module devcore\npub struct Device {}\n')!
	put(work, 'stat/stat.v', 'module stat\npub struct Stat { pub mut: rdev u64 }\n')!
	put(work, 'event/eventstruct/event.v', 'module eventstruct\npub struct Event {}\n')!
	put(work, 'klock/lock.v', '@[has_globals]\nmodule klock\n__global pub depth int\npub struct Lock {}\npub fn (mut l Lock) acquire() { depth++ }\npub fn (mut l Lock) release() { depth-- }\n')!
	put(work, 'errno/error.v', '@[has_globals]\nmodule errno\n__global pub code int\npub const eio=5\npub const ebadf=9\npub const enodev=19\npub const enotty=25\npub const efault=14\npub const eperm=1\npub fn set(value int) { code=value }\npub fn get() int { return code }\n')!
	put(work, 'resource/base.v', 'module resource\nimport stat\n#define vinix_stack_alloc __builtin_alloca\nfn C.vinix_stack_alloc(usize) voidptr\npub interface Resource { mut: stat stat.Stat }\npub struct BlockMetrics { pub mut: failures int }\npub fn (mut m BlockMetrics) failed() { m.failures++ }\npub const o_rdonly=0\npub const o_rdwr=2\npub const o_accmode=3|0o10000000\n')!
	os.cp(root + '/kernel/resource/block_health.v', work + '/resource/health.v')!
	// Select the production AHCI dispatcher explicitly so the same simulated
	// AMD64 backend is exercised on ARM and AMD64 development hosts.
	os.cp(root + '/kernel/resource/block_health_amd64.v', work + '/resource/dispatch.v')!
	put(work, 'proc/proc.v', 'module proc\npub const mac_read=u64(1)\n')!
	put(work, 'file/file.v', '@[has_globals]\nmodule file\nimport resource\nimport errno\n__global pub deny bool\npub struct Handle { pub mut: resource &resource.Resource flags int }\npub fn (mut h Handle) mac_check(_ u64) ? { if deny { errno.set(errno.eperm); return none } }\npub struct FD { pub mut: handle &Handle }\n')!
	put(work, 'usercopy/copy.v', 'module usercopy\nimport klock\npub fn copy_to_user(to u64, from voidptr, count u64) bool { assert klock.depth==0; if to==0 { return false }; unsafe { C.memcpy(voidptr(to),from,count) }; return true }\n')!
	put(work, 'fs/health.v', os.read_file(root + '/kernel/fs/storage_health.v')!)!
	os.cp(root + '/tests/storage-health/ioctl_test.v', work + '/fs/ioctl_test.v')!
	source := os.read_file(root + '/kernel/dev/ahci/ahci.v')!
	prefix := source[..source.index('// Zeroed pages') or { return error('Missing driver declarations') }]
	declarations := prefix.split_into_lines().filter(!it.starts_with('import ')).join('\n')
	put(work, 'ahci/ahci.v', declarations.replace('module ahci', 'module ahci\nimport pci\nimport devcore\nimport stat\nimport klock\nimport event.eventstruct\nimport resource\n')
		+ '\nconst higher_half=u64(0)\nfn C.memset(voidptr,i32,usize) voidptr\nfn C.memcpy(voidptr,voidptr,usize) voidptr\n'
		+ function(source, 'find_cmd_slot')! + function(source, 'set_prdt')!)!
	put(work, 'ahci/health.v', os.read_file(root + '/kernel/dev/ahci/health.v')!)!
	put(work, 'ahci/model.v', os.read_file(root + '/tests/storage-health/model.v')!)!
	os.cp(root + '/tests/storage-health/health_test.v', work + '/ahci/health_test.v')!
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	print(command([v, '-nocache', '-enable-globals', '-cc', 'clang', '-cflags', '-fsanitize=address,undefined',
		'-ldflags', '-fsanitize=address,undefined', 'test', work + '/ahci', work + '/fs'])!)
	cli := work + '/health-cli-host'
	command([v, '-nocache', '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', cli, root + '/tools/volumes/volumecli/health_test.v'])!
	print(command([cli])!)
	println('PASS: production AHCI SMART protocol, fault propagation, descriptor policy and copying under sanitizers')
}

fn audit_generated(path string) ! {
	text := os.read_file(path)!
	mut checked := 0
	for name in ['fs__storage_health', 'resource__block_health', 'ahci__AHCIDevice__block_health',
		'ahci__AHCIDevice__health_command', 'ahci__ata_word', 'ahci__smart_checksum', 'ahci__smart_status'] {
		mut start := 0
		mut body := ''
		for line in text.split_into_lines() {
			if line.contains(' ${name}(') && line.ends_with('{') {
				mut end := start + (line.index('{') or { return error('Missing function body') }) + 1
				mut depth := 1
				for depth != 0 && end < text.len {
					if text[end]==`{` { depth++ }
					if text[end]==`}` { depth-- }
					end++
				}
				if depth != 0 { return error('Unterminated generated function') }
				body=text[start..end]
				break
			}
			start+=line.len+1
		}
		if body=='' {
			if name.starts_with('ahci__') && !text.contains('ahci__AHCIDevice') { continue }
			return error('Missing generated ${name}')
		}
		for allocation in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'memdup_uncollectable('] {
			if body.contains(allocation) { return error('Unexpected allocation in ${name}: ${allocation}') }
		}
		checked++
	}
	if checked < 2 { return error('Missing generated health functions') }
	println('PASS: ${checked} generated kernel health functions use no heap allocation')
}

fn main() {
	if (os.args.len != 3 && os.args.len != 5) || os.args[1] != '--work' || os.exists(os.args[2])
		|| (os.args.len==5 && os.args[3]!='--generated') {
		eprintln('Usage: run.v --work NEW_DIRECTORY [--generated KERNEL_BLOB_C]'); exit(2)
	}
	work := os.abs_path(os.args[2])
	os.mkdir(work) or { eprintln(err); exit(1) }
	host(os.dir(os.dir(os.dir(@FILE))), work) or { eprintln(err); exit(1) }
	if os.args.len==5 { audit_generated(os.args[4]) or { eprintln(err); exit(1) } }
}
