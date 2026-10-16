// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt {
	format int = 1
	sdk int = 1
	architecture string
	completed_at i64
	kind string = 'deployment-audit'
	scenario string = 'packages-deployment-audit'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-deployment-audit', guest: 'tests/packages/deployment-audit-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_audit_test.v', path: 'usr/share/package-fixtures/audit-core' },
			hwhost.Program{ source: 'tools/packages/pkgprotocol/deployment_audit_test.v', path: 'usr/share/package-fixtures/audit-protocol' },
			hwhost.Program{ source: 'tests/packages/deployment-snapshot-check.v', path: 'usr/share/package-fixtures/audit-probe' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_observation_test.v', path: 'usr/share/package-fixtures/observation-core' },
		], scenarios: [hwhost.Scenario{ name: 'packages-deployment-audit', arches: ['aarch64', 'x86_64'],
			about: 'read-only installed deployment drift, exact pins, sequence floors, ordinary readers and strict bounded reports',
			required: ['HWTEST START packages-deployment-audit',
				'DEPLOYMENT AUDIT exact installed metadata, sorted runtime/all-data closure, captured digest, minimum sequence floors and offline revoked policy on both architectures PASS',
				'DEPLOYMENT AUDIT missing/unexpected packages, versions, architecture, digests, publisher/repository, floor and requested-root differences PASS',
				'DEPLOYMENT AUDIT writer exclusion, malformed/roots-only/mismatched/aliased inputs and corrupt state refusal; empty read without initialization PASS',
				'DEPLOYMENT AUDIT PROTOCOL complete typed fields, duplicate/unknown keys, bounded sorted union rows and coherent drift result PASS',
				'DEPLOYMENT AUDIT ordinary UID 1000 reads exact root-owned comparison without administrator authorization PASS',
				'DEPLOYMENT AUDIT CLI exact offline metadata and sequence-floor matches, missing/changed drift exit 3, no fresh-state initialization and authenticated reproduction PASS',
				'Deployment observation: exact SDK JSON and optional LF; inclusive metadata bound and overflow refusal release growth buffers PASS',
				'Deployment observation: complete 4096-root/record snapshots and 8192-row disjoint audit union PASS',
				'Deployment observation: public owned snapshots, durable saved receipts, exact offline audits and existing-file refusals preserve store PASS',
				'AUDIT PROCESS observation-core PASS',
				'AUDIT PROCESS audit-core PASS', 'AUDIT PROCESS audit-protocol PASS', 'AUDIT PROCESS audit-probe PASS',
				'HWTEST PASS packages-deployment-audit'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-deployment-audit-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('package-cli', base + '/guest/root/usr/bin/vinix-package')!, artifact('audit-core', root + 'audit-core')!,
			artifact('audit-protocol', root + 'audit-protocol')!, artifact('audit-probe', root + 'audit-probe')!,
			artifact('observation-core', root + 'observation-core')!,
			artifact('serial-log', base + '/packages-deployment-audit/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
