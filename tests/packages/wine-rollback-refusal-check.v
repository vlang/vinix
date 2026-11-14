// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os

fn refusal(command []string, log string, wanted string) ! {
	os.write_file(log + '.argv.json', json2.encode(command))!
	hwhost.run_tool(command, map[string]string{}, log, 30) or {
		if !os.read_file(log)!.contains(wanted) { return error('rollback refusal at wrong gate: ' + log) }
		return
	}
	return error('rollback input unexpectedly accepted')
}

fn run() ! {
	if os.args.len !in [3, 5] { return error('usage: REFUSALS FRESH_WORK ROLLBACK_CONTROLLER [BASELINE_ISO ISO_SHA256]') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('fresh refusal output required') }
	os.mkdir_all(work)!
	controller := os.real_path(os.args[2])
	image := work + '/image'; kernel := work + '/kernel'
	os.write_file(image, 'not an ISO')!; os.write_file(kernel, 'not a kernel')!
	image_hash := sha256.hexhash('not an ISO'); kernel_hash := sha256.hexhash('not a kernel')
	refusal([controller], work + '/usage.log', 'usage: CHECK')!
	refusal([controller, work, image, image_hash, kernel, kernel_hash, '/missing', '/missing'], work + '/existing.log', 'fresh rollback diagnostic output required')!
	for index, pins in [['short', kernel_hash], [image_hash.to_upper(), kernel_hash], [image_hash, 'short']] {
		output := work + '/bad-pin-' + index.str()
		refusal([controller, output, image, pins[0], kernel, pins[1], '/missing', '/missing'], output + '.log', 'requires explicit lowercase SHA256 pins')!
		if os.exists(output) { return error('malformed pin created workload output') }
	}
	for index, pins in [['0'.repeat(64), kernel_hash], [image_hash, '0'.repeat(64)]] {
		output := work + '/wrong-pin-' + index.str()
		refusal([controller, output, image, pins[0], kernel, pins[1], '/missing', '/missing'], output + '.log', if index == 0 { 'rollback baseline pin differs' } else { 'rollback kernel pin differs' })!
		if os.exists(output) { return error('wrong pin created workload output') }
	}
	os.symlink(image, work + '/image-link')!
	refusal([controller, work + '/linked-output', work + '/image-link', image_hash, kernel, kernel_hash, '/missing', '/missing'], work + '/linked.log', 'requires ordinary input files')!
	refusal([controller, work + '/directory-output', image, image_hash, work, kernel_hash, '/missing', '/missing'], work + '/directory.log', 'requires ordinary input files')!
	if os.exists(work + '/linked-output') || os.exists(work + '/directory-output')
		|| os.read_file(image)! != 'not an ISO' || os.read_file(kernel)! != 'not a kernel' { return error('refusal changed fixture inputs or created output') }
	if os.args.len == 5 {
		output := work + '/embedded-kernel-output'
		refusal([controller, output, os.args[3], os.args[4], kernel, kernel_hash, '/missing', '/missing'], work + '/embedded-kernel.log', 'rollback embedded kernel pin differs')!
		if os.exists(output + '/guest.c') || os.exists(output + '/boot') { return error('embedded-kernel refusal built a guest or image') }
		println('WINE ROLLBACK EMBEDDED KERNEL REFUSAL PASS before guest build or image mutation')
	}
	println('WINE ROLLBACK REFUSALS PASS nine usage/path/pin controls before build or image mutation')
}

fn main() { run() or { eprintln(err); exit(1) } }
