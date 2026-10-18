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
		if (line.starts_with('fn ') || line.starts_with('pub fn '))
			&& (line.contains(' ${name}(') || line.starts_with('fn ${name}(')) {
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

fn host(root string, work string, ans_only bool) ! {
	put(work, 'v.mod', "Module { name: 'storage_health_host' }\n")!
	put(work, 'pci/pci.v', 'module pci\npub struct PCIBar {}\n')!
	put(work, 'devcore/core.v', 'module devcore\npub struct Device {}\n')!
	put(work, 'stat/stat.v', 'module stat\npub struct Stat { pub mut: rdev u64 size i64 blksize i64 blocks i64 }\n')!
	put(work, 'event/eventstruct/event.v', 'module eventstruct\npub struct Event {}\n')!
	put(work, 'klock/lock.v', '@[has_globals]\nmodule klock\n__global pub depth int\npub struct Lock {}\npub fn (mut l Lock) acquire() { assert depth==0; depth++ }\npub fn (mut l Lock) release() { assert depth==1; depth-- }\npub fn spin_hint() {}\n')!
	put(work, 'errno/error.v', '@[has_globals]\nmodule errno\n__global pub code int\npub const eio=5\npub const ebadf=9\npub const enodev=19\npub const enotty=25\npub const efault=14\npub const eperm=1\npub const enomem=12\npub const einval=22\npub const erofs=30\npub const eopnotsupp=95\npub fn set(value u64) { code=int(value) }\npub fn get() u64 { return u64(code) }\n')!
	// Keep optional-interface dispatch compilable in individual health tests
	// that do not import a status-capable backend. This stub is never published.
	put(work, 'resource/base.v', 'module resource\nimport stat\n#define vinix_stack_alloc __builtin_alloca\nfn C.vinix_stack_alloc(usize) voidptr\npub interface Resource { mut: stat stat.Stat }\nstruct StatusStub { mut: stat stat.Stat }\nfn (mut s StatusStub) block_status() BlockStatus { return BlockStatus{version:0} }\npub struct BlockMetrics { pub mut: failures int }\npub fn (mut m BlockMetrics) failed() { m.failures++ }\npub fn (mut m BlockMetrics) flushed() {}\npub const o_rdonly=0\npub const o_rdwr=2\npub const o_accmode=3|0o10000000\n'
		+ function(os.read_file(root + '/kernel/resource/block_discard.v')!, 'discard_range_valid')!)!
	os.cp(root + '/kernel/resource/block_health.v', work + '/resource/health.v')!
	status_source := os.read_file(root + '/kernel/resource/block_status.v')!
	put(work, 'resource/status.v', status_source.all_before('pub struct BlockMetrics {')
		+ status_source[status_source.index('pub interface BlockStatusResource {') or { return error('Missing status dispatcher') }..])!
	put(work, 'resource/identity.v', 'module resource\npub struct BlockIdentity { pub: is_block bool disk_id u64 start u64 length u64 }\n')!
	// Exercise the development host architecture's production dispatcher.
	dispatch := $if arm64 { 'arm64' } $else { 'amd64' }
	os.cp(root + '/kernel/resource/block_health_${dispatch}.v', work + '/resource/dispatch.v')!
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
	nvme_host(root, work)!
	ans_host(root, work)!
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	// Compile each maintained test entry directly so qualification needs no
	// separately built host test utility or its thread/GC runtime.
	names := if ans_only { ['anscore/health_test', 'anscore/namespace_test', 'ans/health_test', 'ans/status_test'] } else {
		['ahci/health_test', 'fs/ioctl_test', 'nvme/boot_test', 'nvme/completion_test',
		'nvme/health_test', 'anscore/health_test', 'anscore/namespace_test', 'ans/health_test', 'ans/status_test']
	}
	for name in names {
		binary := work + '/' + name + '-host'
		mut flags := [v, '-nocache', '-gc', 'none', '-no-closures', '-enable-globals', '-cc', 'clang',
			'-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined',
			'-o', binary]
		flags << if ans_only { ['-d', 'no_backtrace'] } else { ['-target-libc-headers'] }
		flags << work + '/' + name + '.v'
		command(flags)!
		print(command([binary])!)
		println('PASS: ${name}')
	}
	if ans_only { return }
	cli := work + '/health-cli-host'
	command([v, '-nocache', '-gc', 'none', '-no-closures', '-target-libc-headers', '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', cli, root + '/tools/volumes/volumecli/health_test.v'])!
	print(command([cli])!)
	println('PASS: production ATA/NVMe/ANS health, completion and DMA ownership, descriptor policy and copying under sanitizers')
}

fn nvme_host(root string, work string) ! {
	source := os.read_file(root + '/kernel/dev/nvme/nvme.v')!
	prefix := source[..source.index('__global (') or { return error('Missing NVMe declarations') }]
	declarations := prefix.split_into_lines().filter(!it.starts_with('import ')).join('\n')
	mut functions := ''
	for name in ['send_cmd', 'send_cmd_and_wait', 'exchange', 'fail_controller', 'ready_timeout_ns', 'rw_lba', 'transfer', 'sync', 'discard'] {
		functions += function(source, name)! + '\n'
	}
	functions += function(source[source.index('pub fn (mut pair NVMEQueuePair) initialise(') or { return error('Missing queue initializer') }..], 'initialise')!
	put(work, 'nvme/nvme.v', declarations.replace('module nvme', 'module nvme\nimport memory\nimport lib\nimport pci\nimport bitmap\nimport stat\nimport klock\nimport event.eventstruct\nimport errno\nimport katomic\nimport resource\nimport proc\nimport x86.hpet as hpet_clock\n')
		+ '\nconst page_size=u64(4096)\nconst higher_half=u64(0)\n__global kernel_pagemap=memory.Pagemap{}\n#include <stdio.h>\n#define kprintf printf\n#define vinix_stack_alloc __builtin_alloca\nfn C.kprintf(&char,...voidptr) int\nfn C.vinix_stack_alloc(usize) voidptr\nfn C.memset(voidptr,i32,usize) voidptr\nfn C.memcpy(voidptr,voidptr,usize) voidptr\n'
		// Power-transition waiting is outside this awake-controller model.
		+ 'fn (mut c NVMEController) wait_awake() { assert !c.asleep }\n' + functions)!
	os.cp(root + '/kernel/dev/nvme/health.v', work + '/nvme/health.v')!
	os.cp(root + '/kernel/dev/nvme/mmio.v', work + '/nvme/mmio.v')!
	os.cp(root + '/tests/storage-health/nvme_boot_test.v', work + '/nvme/boot_test.v')!
	os.cp(root + '/tests/storage-health/nvme_test.v', work + '/nvme/health_test.v')!
	os.cp(root + '/tests/block-storage/completion_test.v', work + '/nvme/completion_test.v')!
	put(work, 'proc/disk.v', 'module proc\npub fn account_disk_transfer(_ u64,_ bool) {}\npub fn account_disk_io(_ u64,_ u64,_ bool) {}\n')!
	put(work, 'lib/lib.v', 'module lib\npub fn div_roundup[T](a T,b T) T { return (a+b-1)/b }\n')!
	put(work, 'katomic/katomic.v', 'module katomic\npub fn sync() {}\n')!
	put(work, 'bitmap/bitmap.v', 'module bitmap\npub struct GenericBitmap { mut: slots []bool }\npub fn (mut b GenericBitmap) initialise(count u64) { b.slots=[]bool{len:int(count)} }\npub fn (b GenericBitmap) alloc() ?u64 { for i,busy in b.slots { if !busy { unsafe { b.slots[i]=true }; return u64(i) } }; return none }\npub fn (b GenericBitmap) free_entry(index u64) { unsafe { b.slots[index]=false } }\n')!
	put(work, 'x86/hpet/hpet.v', '@[has_globals]\nmodule hpet\n__global tick_hook=fn () {}\n__global ticks=u64(0)\npub fn nanoseconds() u64 { ticks+=1_000_000_000; tick_hook(); return ticks }\npub fn set_hook(hook fn ()) { tick_hook=hook; ticks=0 }\n')!
	put(work, 'memory/memory.v', '@[has_globals]\nmodule memory\n#include <stdlib.h>\nfn C.posix_memalign(&voidptr,usize,usize) int\n__global live_pages=u64(0)\n__global pub fail_alloc bool\npub fn pmm_alloc_nozero_fallible(pages u64) voidptr { if fail_alloc { return unsafe { nil } }; mut pointer:=unsafe { nil }; if C.posix_memalign(&pointer,4096,usize(pages*4096))!=0 { return unsafe { nil } }; live_pages+=pages; unsafe { C.memset(pointer,0x5a,usize(pages*4096)) }; return pointer }\npub fn pmm_alloc(pages u64) voidptr { pointer:=pmm_alloc_nozero_fallible(pages); assert pointer!=unsafe { nil }; unsafe { C.memset(pointer,0,usize(pages*4096)) }; return pointer }\npub fn pmm_free(pointer voidptr,pages u64) { assert live_pages>=pages; live_pages-=pages; unsafe { free(pointer) } }\npub fn allocated_pages() u64 { return live_pages }\npub const pte_present=u64(1)\npub const pte_writable=u64(2)\npub const pte_noexec=u64(1)<<63\npub fn get_hhdm_offset() u64 { return 0xffff800000000000 }\npub struct Pagemap { pub mut: calls int last_virt u64 last_phys u64 flags u64 fail bool }\npub fn (mut p Pagemap) map_page(virt u64,phys u64,flags u64) ? { p.calls++; if p.fail { return none }; p.last_virt=virt; p.last_phys=phys; p.flags=flags }\n')!
}

fn ans_host(root string, work string) ! {
	// Preserve the production transport and media policy. Only privileged
	// hardware callbacks and boot-only globals are omitted on the host.
	source := os.read_file(root + '/kernel/apple/ans/anscore/core.v')!
	end := source.index('fn C.vinix_mmio_read32(') or { return error('Missing ANS hardware boundary') }
	put(work, 'anscore/core.v', source[..end].replace('module anscore',
		'module anscore\nimport ext2core as _\n#flag -iquote ${root}/kernel/c\n#flag -DVINIX_V_RUNTIME\n')
		+ '\n__global ans_controller Ans\n')!
	os.cp(root + '/kernel/apple/ans/anscore/health.v', work + '/anscore/health.v')!
	os.cp(root + '/kernel/apple/ans/anscore/status.v', work + '/anscore/status.v')!
	mut api := ''
	for name in ['vinix_ans_read', 'vinix_ans_write', 'vinix_ans_flush', 'vinix_ans_partition_writable'] {
		api += "\n@[export: '${name}']\n" + function(source, name)!
	}
	put(work, 'anscore/api.v', '@[translated]\nmodule anscore\n' + api)!
	put(work, 'anscore/model.v', os.read_file(root + '/tests/storage-health/ans_model.v')!)!
	os.cp(root + '/tests/storage-health/ans_core_test.v', work + '/anscore/health_test.v')!
	os.cp(root + '/tests/storage-health/ans_namespace_test.v', work + '/anscore/namespace_test.v')!
	put(work, 'ext2core/core.v', os.read_file(root + '/kernel/apple/ans/ext2core/core.v')!)!
	put(work, 'ans/health.v', os.read_file(root + '/kernel/apple/ans/health.v')!
		.replace('import apple.ans.anscore', 'import anscore'))!
	put(work, 'ans/status.v', os.read_file(root + '/kernel/apple/ans/status.v')!
		.replace('import apple.ans.anscore', 'import anscore'))!
	ans_source := os.read_file(root + '/kernel/apple/ans/ans.v')!
	ans_start := ans_source.index('struct AnsBlock {') or { return error('Missing ANS resource') }
	ans_end := ans_source.index("// A block geometry query's answer") or { return error('Missing ANS ioctl boundary') }
	put(work, 'ans/base.v', '@[has_globals]\nmodule ans\nimport stat\nimport klock\nimport event.eventstruct\nimport errno\n__global ans_lock=klock.Lock{}\n__global ans_ready=true\n__global ans_read_error_reported=false\nfn report(_ string,_ int) {}\nfn C.vinix_ans_read(u32,voidptr,u64,usize) i32\nfn C.vinix_ans_write(u32,u32,voidptr,u64,usize) i32\nfn C.vinix_ans_partition_writable(u32,u32) i32\nfn C.vinix_ans_flush() i32\n'
		+ ans_source[ans_start..ans_end] + function(ans_source, 'flush')!)!
	os.cp(root + '/tests/storage-health/ans_test.v', work + '/ans/health_test.v')!
	os.cp(root + '/tests/storage-health/ans_status_test.v', work + '/ans/status_test.v')!
}

fn audit_generated(path string) ! {
	text := os.read_file(path)!
	mut checked := 0
	mut names := ['fs__storage_health', 'resource__block_health', 'ahci__AHCIDevice__block_health',
		'ahci__AHCIDevice__health_command', 'ahci__ata_word', 'ahci__smart_checksum', 'ahci__smart_status',
		'nvme__NVMENamespace__block_health', 'nvme__map_registers', 'nvme__map_doorbells',
		'nvme__NVMENamespace__rw_lba', 'nvme__NVMENamespace__sync',
		'ans__AnsBlock__block_health', 'ans__AnsBlock__block_status', 'ans__AnsBlock__record_failed',
		'ans__AnsBlock__read', 'ans__AnsBlock__write', 'ans__AnsBlock__sync',
		'anscore__namespace_status', 'anscore__namespace_failed', 'anscore__set_namespace_id',
		'anscore__a_count_transfer', 'anscore__a_count_flush', 'anscore__a_enumerate_namespaces',
		'anscore__a_read_bytes', 'anscore__a_write_partition', 'anscore__a_flush_ns', 'anscore__a_health',
		'anscore__health', 'anscore__a_submit', 'anscore__a_command_allowed', 'anscore__a_authorize',
		'anscore__a_pump', 'anscore__a_begin', 'anscore__a_expired', 'anscore__a_fail',
		'anscore__a_sync', 'anscore__a_copy', 'anscore__a_zero']
	if text.contains('void ans__status_fixture_run(') {
		names << ['ans__status_fixture_run', 'ans__status_fixture_cycle']
	}
	for name in names {
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
			if (name.starts_with('ans__') || name.starts_with('anscore__'))
				&& !text.contains('ans__AnsBlock') { continue }
			if name.starts_with('ahci__') && !text.contains('ahci__AHCIDevice') { continue }
			if name.starts_with('nvme__') && !text.contains('nvme__NVMENamespace') { continue }
			return error('Missing generated ${name}')
		}
		for allocation in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'memdup_uncollectable('] {
			if body.contains(allocation) { return error('Unexpected allocation in ${name}: ${allocation}') }
		}
		checked++
	}
	if checked < 2 { return error('Missing generated health functions') }
	println('PASS: ${checked} generated kernel health/status, accounting, mapping and I/O functions use no heap allocation')
}

fn main() {
	ans_only := '--ans-only' in os.args
	args := os.args.filter(it != '--ans-only')
	if (args.len != 3 && args.len != 5) || args[1] != '--work' || os.exists(args[2])
		|| (args.len==5 && args[3]!='--generated') {
		eprintln('Usage: run.v --work NEW_DIRECTORY [--ans-only] [--generated KERNEL_BLOB_C]'); exit(2)
	}
	work := os.abs_path(args[2])
	os.mkdir(work) or { eprintln(err); exit(1) }
	host(os.dir(os.dir(os.dir(@FILE))), work, ans_only) or { eprintln(err); exit(1) }
	if args.len==5 { audit_generated(args[4]) or { eprintln(err); exit(1) } }
}
