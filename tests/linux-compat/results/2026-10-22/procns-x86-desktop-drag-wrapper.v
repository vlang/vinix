@[has_globals]
module main

import json2
import os
import perfconsole
import perfrunner
import policyhost

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	root := '/Users/alex/code/vinix'
	prior := area + '/dt'
	work := area + '/du'
	if os.exists(work) { panic('fresh desktop state required') }
	os.mkdir_all(work + '/vm')!
	guard := perfconsole.own_commands()
	defer { guard.close() }
	for item in ['kernel', 'overlay'] {
		perfrunner.command(['cp', '-cR', prior + '/' + item, work + '/' + item]) or { panic(err) }
	}
	for item in ['initramfs.tar', 'vm/test.iso'] {
		perfrunner.command(['cp', '-c', prior + '/' + item, work + '/' + item]) or { panic(err) }
	}
	mut receipt := json2.decode[map[string]string](os.read_file(prior + '/receipt.json')!)!
	prior_command := receipt['command'].replace(prior, work)
	assert prior_command.ends_with(' -usb -device usb-tablet')
	command_text := prior_command.all_before_last(' -usb -device usb-tablet') + ' -device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0'
	receipt['command'] = command_text
	receipt['reused_frozen_input_receipt'] = prior + '/receipt.json'
	receipt['qualification_correction'] = 'Use cf642 x86 xHCI input driver; default UHCI does not deliver /dev/pointer events.'
	os.write_file(work + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	plan := perfrunner.parse(['new=' + work + '/overlay/opt/vinix-perf/vinix-desktop-new', '--scenarios=drag', '--rounds=1', '--settle=5', '--seconds=10', '--mem=4096', '--timeout=2400', '--desktop-args=--stats', '--json=' + work + '/results.json', '--shots=' + work + '/shots'], root, root + '/tests/desktop-perf', '') or { panic(err) }
	status := perfrunner.drive(plan, perfrunner.Launch{command_text.split(' '), policyhost.environment(), work + '/vm/qmp.sock'}, work, 10, true) or {
		eprintln(err)
		1
	}
	os.write_file(work + '/status', status.str() + '\n')!
	exit(status)
}
