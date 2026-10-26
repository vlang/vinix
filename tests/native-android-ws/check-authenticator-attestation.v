// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production public registry chain against changing fixture bytes.
// Only protected file I/O is replaced: root ownership/open protection is outside
// this host check and remains covered by the registry's metadata tests.
module main

import crypto.sha256
import json2
import os

fn attestation_block(source string, declaration string) !string {
	start := source.index(declaration) or { return error('missing ' + declaration) }
	end := source[start..].index('\n}') or { return error('unclosed ' + declaration) }
	return source[start..start + end + 2]
}

struct AttestationReceipt {
	argv []string
	status int
	output string
}

struct AttestationEvidence {
	scope string
	registry_sha256 string
	service_sha256 string
	source_revision string
	compiler string
	compiler_sha256 string
	compile []AttestationReceipt
	run []AttestationReceipt
}

fn main() {
	assert os.args.len in [2, 3], 'usage: check-authenticator-attestation OUTPUT_DIR [REPO]'
	repo := if os.args.len == 3 { os.real_path(os.args[2]) } else { os.getwd() }
	work := os.abs_path(os.args[1])
	assert !os.exists(work), 'output directory must be new'
	assert work != repo && !work.starts_with(repo + '/'), 'keep generated evidence outside Git'
	os.mkdir_all(work)!
	source := os.read_file(repo + '/build-support/android/nativeaccountauth/registry.v')!
	service := os.read_file(repo + '/build-support/android/nativeaccountauth/service.c.v')!
	os.write_file(work + '/input-registry.v', source)!
	os.write_file(work + '/input-service.c.v', service)!
	mut production := ''
	for declaration in ['pub struct Entry {', 'pub struct Service {', 'pub struct Registry {',
		'pub fn (registry Registry) verify_launch(', 'pub fn (registry Registry) verify_service(',
		'fn selected_authenticator_type(', 'pub fn (registry Registry) verify_authenticator_type('] {
		production += attestation_block(source, declaration)! + '\n'
	}
	production += attestation_block(service, 'pub struct ServiceLaunch {')! + '\n'
	mut variants := [production]
	variants << production.replace('registry.verify_service(apk, uid, gid, launch.service, launch.action)!',
		'registry.entries[0]')
	variants << production.replace('if protected_apk_digest(apk)! != entry.apk_sha256 {', 'if false {')
	variants << production.replace('if entry.package_name != launch.package_name || entry.apk_sha256 != launch.apk_sha256 {', 'if false {')
	variants << production.replace('if service.class_name == launch.service && service.action == launch.action {', 'if true {')
		.replace('if service.class_name == class_name && service.action == action {', 'if true {')
	variants << production.replace('if entry.apk == apk && entry.uid == uid && entry.gid == gid {', 'if true {')
	variants << production.replace('return service.account_type',
		"return if service.account_type != '' { service.account_type } else { 'forged' }")
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	mut builds := []AttestationReceipt{}
	mut runs := []AttestationReceipt{}
	for index, variant in variants {
		assert index == 0 || variant != production, 'negative mutation did not change source'
		path := work + '/case-' + index.str()
		os.mkdir(path)!
		os.write_file(path + '/main.v', attestation_model + '\n' + variant + attestation_cases)!
		compile_argv := [compiler, '-w', '-cc', 'cc', '-o', path + '/probe', path + '/main.v']
		compiled := os.exec(compile_argv)
		os.write_file(path + '/compile.log', compiled.output)!
		assert compiled.exit_code == 0, compiled.output
		builds << AttestationReceipt{compile_argv, compiled.exit_code, compiled.output}
		run_argv := [path + '/probe', path + '/fixture.apk']
		ran := os.exec(run_argv)
		os.write_file(path + '/run.log', ran.output)!
		assert (ran.exit_code == 0) == (index == 0), 'production or negative mutation behaved incorrectly: ' + index.str() + '\n' + ran.output
		runs << AttestationReceipt{run_argv, ran.exit_code, ran.output}
	}
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/build.json', json2.encode(AttestationEvidence{
		scope: 'Extracted production public registry chain; protected file I/O replaced by rootless SHA-256 reader. No root ownership/open protection or guest execution.'
		registry_sha256: sha256.sum(source.bytes()).hex()
		service_sha256: sha256.sum(service.bytes()).hex()
		source_revision: revision.output.trim_space()
		compiler: compiler
		compiler_sha256: sha256.sum(os.read_bytes(compiler)!).hex()
		compile: builds
		run: runs
	}, prettify: true))!
	println('AUTHENTICATOR-ATTESTATION-PASS production-public-chain changed-metadata unchanged-frame negative-mutations=6')
}

const attestation_model = '
module main
import crypto.sha256
import os
fn protected_apk_digest(path string) !string {
 return sha256.sum(os.read_bytes(path)!).hex()
}
fn reject_type(registry Registry, apk string, uid u32, gid u32, launch ServiceLaunch) {
 mut rejected := false
 registry.verify_authenticator_type(apk,uid,gid,launch) or { rejected = true }
 assert rejected
}
'

const attestation_cases = '
fn main() {
 path := os.args[1]
 metadata := \'<account-authenticator accountType="com.example.account" customTokens="true"/>\'
 os.write_file(path,metadata)!
 digest := sha256.sum(metadata.bytes()).hex()
 entry := Entry{package_name:"com.example.auth",uid:10001,gid:10002,apk:path,apk_sha256:digest,
  services:[Service{class_name:"com.example.auth.Service",action:"android.accounts.AccountAuthenticator",account_type:"com.example.account"}]}
 registry := Registry{entries:[entry]}
 launch := ServiceLaunch{"com.example.auth","com.example.auth.Service","android.accounts.AccountAuthenticator",digest}
 assert registry.verify_authenticator_type(path,10001,10002,launch)! == "com.example.account"
 legacy := Registry{entries:[Entry{...entry,services:[Service{class_name:launch.service,action:launch.action}]}]}
 assert legacy.verify_authenticator_type(path,10001,10002,launch)! == ""
 reject_type(registry,path,10002,10002,launch)
 reject_type(registry,path,10001,10003,launch)
 reject_type(registry,path + ".other",10001,10002,launch)
 reject_type(registry,path,10001,10002,ServiceLaunch{...launch,package_name:"com.other.auth"})
 reject_type(registry,path,10001,10002,ServiceLaunch{...launch,service:"com.example.other.Service"})
 reject_type(registry,path,10001,10002,ServiceLaunch{...launch,action:"com.example.OTHER"})
 reject_type(registry,path,10001,10002,ServiceLaunch{...launch,apk_sha256:"b".repeat(64)})
 // Preserve the original registry and service frame while changing APK bytes.
 changed := metadata.replace("com.example.account","com.other.account")
 changed_digest := sha256.sum(changed.bytes()).hex()
 assert changed_digest != digest
 os.write_file(path,changed)!
 reject_type(registry,path,10001,10002,launch)
 reject_type(registry,path,10001,10002,ServiceLaunch{...launch,apk_sha256:changed_digest})
 os.write_file(path,metadata)!
 assert registry.verify_authenticator_type(path,10001,10002,launch)! == "com.example.account"
 os.rm(path)!
 reject_type(registry,path,10001,10002,launch)
 println("AUTHENTICATOR-ATTESTATION-PUBLIC-CHAIN-PASS")
}
'
