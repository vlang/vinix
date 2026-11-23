// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import rand
import tarstream
import tools.packages.imageinputs
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const config_path = '/etc/vinix-packages/config.json'
const repository_path = pkgcore.image_repositories_path
const declaration_path = pkgprotocol.image_applications_path

struct IndexSummary {
	id string
	sequence u64
	index_sha256 string
	payload_bytes u64
}

struct Preflight {
	configuration_sha256 string
	configuration pkgcore.Config
	image_application_deployment_sha256 string
	application_deployment pkgprotocol.DeploymentDocument
	bundled_repositories []IndexSummary
}

struct Publisher {
	id string
	public_key string
	sequence u64
	index_sha256 string
	payload_bytes u64
}

struct Selection {
	architecture string
	configuration_sha256 string
	deployment_sha256 string
	applications []string
	publishers []Publisher
}

struct Receipt {
	format int = 1
	iso_sha256 string
	configuration_sha256 string
	deployment_sha256 string
	architecture string
	applications []string
	publishers []Publisher
}

fn preflight(root string, arch string, config string, bundle string, declaration string) !Selection {
	mut configuration := pkgcore.prepare_image_configuration(root, arch, config)!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories_in(bundle, root)!
	defer { repositories.close() }
	report := if declaration == '' {
		unsafe { &configuration }.check_repositories(unsafe { &repositories })!
	} else {
		unsafe { &configuration }.check_application_file(unsafe { &repositories }, declaration)!
	}
	repositories.retire()!
	input := json2.decode[Preflight](report)!
	mut publishers := []Publisher{cap: input.bundled_repositories.len}
	for index in input.bundled_repositories {
		configured := input.configuration.repositories.filter(it.id == index.id)
		if configured.len != 1 { return error('preflight omitted publisher ' + index.id) }
		publishers << Publisher{id: index.id, public_key: configured[0].public_key, sequence: index.sequence,
			index_sha256: index.index_sha256, payload_bytes: index.payload_bytes}
	}
	return Selection{architecture: arch, configuration_sha256: input.configuration_sha256,
		deployment_sha256: input.image_application_deployment_sha256,
		applications: input.application_deployment.packages, publishers: publishers}
}

fn archive_path(name string) !string {
	path := if name.starts_with('./') { name[2..] } else { name }
	if path == '' || path == '.' { return '/' }
	if path.split('/').any(it in ['', '.', '..']!) || path.contains('\x00') {
		return error('noncanonical ISO initramfs member: ' + name)
	}
	return '/' + path
}

fn capture_package_members(archive string, root string, expected Selection) ! {
	mut reader := tarstream.open_boot_ustar(archive)!
	defer { reader.close() }
	mut seen := map[string]bool{}
	mut allowance := u64(16 * 1024 * 1024)
	for publisher in expected.publishers {
		allowance += publisher.payload_bytes + 16 * 1024 * 1024
	}
	mut buffer := []u8{len: 64 * 1024}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		path := archive_path(member.name)!
		parent := path in ['/', '/etc', '/etc/vinix-packages', '/usr', '/usr/share',
			'/usr/share/vinix-packages', repository_path]!
		if !parent && path !in [config_path, declaration_path]! && !path.starts_with(repository_path + '/') { continue }
		if path in seen { return error('duplicate ISO package member: ' + path) }
		directory := os.dir(path)
		if directory != '/' && !seen[directory] {
			return error('ISO package directory must precede its members: ' + directory)
		}
		is_directory := member.kind == `5`
		seen[path] = is_directory
		if parent || (path.starts_with(repository_path + '/') && is_directory) {
			if !is_directory || member.mode & 0o022 != 0 || (path != '/' && member.mode & 0o555 != 0o555) {
				return error('invalid ISO package directory: ' + path)
			}
			if path != '/' { os.mkdir(root + path, mode: 0o755)! }
			continue
		}
		if member.kind != `0` || member.mode != 0o644 || u64(member.size) > allowance {
			return error('invalid ISO package file: ' + path)
		}
		allowance -= u64(member.size)
		mut file := os.create(root + path)!
		defer { file.close() }
		for {
			count := reader.read(mut buffer)!
			if count == 0 { break }
			if file.write(buffer[..count])! != count { return error('short ISO package capture: ' + path) }
		}
		os.chmod(root + path, 0o644)!
	}
}

fn check_iso(iso string, work string, expected Selection) !Receipt {
	before := pkgcore.hash_file(iso)!
	archive := work + '/initramfs.tar.gz'
	mut extract := os.new_process(os.find_abs_path_of_executable('xorriso')!)
	defer { extract.close() }
	extract.set_args(['-osirrox', 'on', '-indev', os.abs_path(iso), '-extract', '/boot/initramfs.tar.gz', archive])
	extract.set_redirect_stdio_merged()
	extract.run()
	output := extract.stdout_slurp()
	extract.wait()
	if extract.code != 0 { return error('cannot extract ISO initramfs: ' + output) }
	root := work + '/root'
	os.mkdir(root, mode: 0o700)!
	capture_package_members(archive, root, expected)!
	if !os.is_file(root + config_path) { return error('ISO is missing its selected package configuration') }
	bundle := root + repository_path
	actual := preflight(root, expected.architecture, '',
		if os.is_dir(bundle) && os.ls(bundle)!.len > 0 { bundle } else { '' },
		if os.is_file(root + declaration_path) { root + declaration_path } else { '' })!
	if actual.configuration_sha256 != expected.configuration_sha256 {
		return error('ISO package configuration differs from the preflight selection')
	}
	if actual.publishers != expected.publishers { return error('ISO signed repositories differ from the preflight selection') }
	if actual.deployment_sha256 != expected.deployment_sha256 || actual.applications != expected.applications {
		return error('ISO application declaration differs from the preflight selection')
	}
	if pkgcore.hash_file(iso)! != before { return error('ISO changed during package verification') }
	return Receipt{iso_sha256: before, configuration_sha256: actual.configuration_sha256,
		deployment_sha256: actual.deployment_sha256, architecture: actual.architecture,
		applications: actual.applications, publishers: actual.publishers}
}

fn print_checksums(path string) ! {
	raw := os.read_file(path)!
	receipt := json2.decode[Receipt](raw)!
	arch := match receipt.architecture {
		'x86_64' { 'amd64' }
		'aarch64' { 'arm64' }
		else { return error('unsupported receipt architecture: ' + receipt.architecture) }
	}
	if receipt.format != 1 || !pkgcore.digest_valid(receipt.iso_sha256) {
		return error('invalid ISO package receipt')
	}
	println('${receipt.iso_sha256}  vinix-${arch}.iso')
	println('${sha256.sum(raw.bytes()).hex()}  vinix-packages-${arch}.json')
}

fn workspace() !string {
	selected := os.getenv('TMPDIR')
	temp := if selected != '' { selected } else { os.temp_dir() }
	work := os.join_path(temp, 'vinix-iso-packages-' + rand.ulid())
	os.mkdir(work, mode: 0o700)!
	return work
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'checksums' {
		return print_checksums(os.args[2])
	}
	if os.args.len == 3 && os.args[1] == 'plan' {
		arch := os.args[2]
		if arch !in ['aarch64', 'x86_64']! { return error('unsupported package architecture: ' + arch) }
		env := os.environ()
		config := imageinputs.environment_path(env, imageinputs.configuration, arch)
		bundle := imageinputs.environment_path(env, imageinputs.repositories, arch)
		declaration := imageinputs.environment_path(env, imageinputs.applications, arch)
		if config == '' && bundle == '' && declaration == '' { return }
		work := workspace()!
		defer { os.rmdir_all(work) or {} }
		println(json2.encode(preflight(work, arch, config, bundle, declaration)!))
		return
	}
	if os.args.len != 4 || os.args[1] != 'verify' { return error('usage: package-receipt plan ARCH | verify ISO PLAN.json | checksums RECEIPT.json') }
	work := workspace()!
	defer { os.rmdir_all(work) or {} }
	expected := json2.decode[Selection](os.read_file(os.args[3])!)!
	println(json2.encode(check_iso(os.args[2], work, expected)!))
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
