// SPDX-License-Identifier: GPL-2.0-or-later
module storagehost

import hosttest
import policyhost
import os

pub fn function(source string, name string) !string {
	mut start := 0
	for line in source.split_into_lines() {
		if line.starts_with('fn ') || line.starts_with('pub fn ') {
			at := line.index(name + '(') or {
				start += line.len + 1
				continue
			}
			if at > 0 && (line[at - 1].is_alnum() || line[at - 1] == `_`) {
				start += line.len + 1
				continue
			}
			brace := line.index('{') or { return error('Missing production function body: ' + name) }
			mut cursor := start + brace + 1
			mut depth := 1
			for depth > 0 && cursor < source.len {
				depth += if source[cursor] == `{` {
					1
				} else if source[cursor] == `}` {
					-1
				} else {
					0
				}
				cursor++
			}
			if depth != 0 { return error('Unterminated production function: ' + name) }
			return source[start..cursor]
		}
		start += line.len + 1
	}
	return error('Missing production function: ' + name)
}

fn write(work string, path string, content string) ! {
	os.mkdir_all(os.dir(work + '/' + path))!
	os.write_file(work + '/' + path, content)!
}

fn driver(work string, source_path string, name string, imports []string, functions []string, constants string) ! {
	source := os.read_file(source_path)!
	end := source.index('__global (') or { return error('Missing production global declarations: ' + source_path) }
	declarations := source[..end].split_into_lines().filter(!it.starts_with('import ')).join('\n')
	mut bodies := []string{}
	for selected in functions { bodies << function(source, selected)! }
	write(work, name + '/' + name + '.v', declarations.replace('module ' + name, 'module ' + name + '\n' + imports.map('import ' + it).join('\n')) + '\n' + constants + '\n' + bodies.join('\n\n'))!
}

pub fn run() ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	root := hosttest.root()
	work := hosttest.work_dir('', 'vinix-storage-host-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	write(work, 'v.mod', "Module { name: 'vinix_storage_host_tests' }\n")!
	for path, contents in stubs() { write(work, path, contents)! }
	write(work, 'block/fence/fence.v', os.read_file(root + '/kernel/block/fence/fence.v')!)!
	write(work, 'resource/resource.v', 'module resource\npub struct BlockMetrics {}\npub fn (mut m BlockMetrics) failed() {}\npub fn (mut m BlockMetrics) flushed() {}\n' + function(os.read_file(root + '/kernel/resource/block_discard.v')!, 'discard_range_valid')!)!
	health := os.read_file(root + '/kernel/dev/nvme/health.v')!
	health_end := health.index('fn (') or { return error('Missing NVMe health declaration boundary') }
	health_declarations := health[..health_end].split_into_lines().filter(!it.starts_with('module ') && !it.starts_with('import ')).join('\n')
	driver(work, root + '/kernel/dev/nvme/nvme.v', 'nvme', ['memory', 'lib', 'pci', 'bitmap', 'stat',
		'klock', 'event.eventstruct', 'errno', 'katomic', 'resource', 'proc', 'devcore', 'block.fence',
		'x86.hpet as hpet_clock'], ['send_cmd', 'send_cmd_and_wait', 'exchange', 'fail_controller',
		'ready_timeout_ns', 'rw_lba', 'transfer', 'sync', 'discard'], 'const page_size = u64(4096)\nconst higher_half = u64(0)\n#include <stdio.h>\n#define kprintf printf\n#define vinix_stack_alloc __builtin_alloca\nfn C.kprintf(&char, ...voidptr) int\nfn C.vinix_stack_alloc(usize) voidptr\n' + health_declarations + '\n' + function(os.read_file(root + '/kernel/dev/nvme/power.v')!, 'wait_awake')!)!
	driver(work, root + '/kernel/aarch64/virtio_blk/virtio_blk.v', 'virtio_blk', [
		'aarch64.cpu',
		'aarch64.timer',
		'aarch64.uart',
		'errno',
		'klock',
		'event.eventstruct',
		'stat',
		'resource',
	], ['mmio_r32', 'mmio_w32', 'write_descriptor', 'collect_one', 'sync', 'discard'], 'fn C.memcpy(voidptr, voidptr, usize) voidptr')!
	power := os.read_file(root + '/kernel/dev/ahci/power.v')!
	driver(work, root + '/kernel/dev/ahci/ahci.v', 'ahci', ['pci', 'errno', 'klock', 'event.eventstruct',
		'stat', 'katomic', 'resource', 'devcore', 'dma', 'block.fence', 'x86.hpet as hpet_clock'], [
		'find_cmd_slot',
		'send_cmd',
		'sync',
		'set_prdt',
		'discard',
	], 'const higher_half = u64(0)\nconst page_size = u64(4096)\n' + function(power, 'wait_awake')! + '\n' + function(power, 'take')!)!
	for pair in [['nvme/completion_test.v', 'completion_test.v'],
		['virtio_blk/flush_test.v', 'flush_test.v'], ['ahci/flush_test.v', 'ahci_test.v']] {
		write(work, pair[0], os.read_file(root + '/tests/block-storage/' + pair[1])!)!
	}
	v := policyhost.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		root])!
	policyhost.owned_inherited_environment([v, '-enable-globals', '-gc', 'none', 'test', 'nvme',
		'virtio_blk', 'ahci'], policyhost.environment(), policyhost.caller_arch(), work)!
}
