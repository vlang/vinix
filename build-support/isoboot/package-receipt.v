// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import strconv
import tarstream
import time
import tools.packages.imageinputs
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const config_path = '/etc/vinix-packages/config.json'
const repository_path = pkgcore.image_repositories_path
const declaration_path = pkgprotocol.image_applications_path

fn C.mkdtemp(&char) &char

struct IndexSummary {
	id string
	sequence u64
	index_sha256 string
	payload_bytes u64
	reviewed_origin string
}

struct Preflight {
	configuration_sha256 string
	configuration pkgcore.Config
	image_application_deployment_sha256 string
	application_deployment pkgprotocol.DeploymentDocument
	bundled_repositories []IndexSummary
}

struct Selection {
	architecture string
	configuration_sha256 string
	deployment_sha256 string
	applications []string
	publishers []pkgcore.IsoOfflinePublisher
}

type Receipt = pkgcore.IsoPackageReceipt

struct ArchiveAudit {
	release_time i64
	receipt Receipt
}

struct InstalledVerification {
	format int = 1
	release_time i64 @[omitempty]
	receipt Receipt
	snapshot_sha256 string
	coverage pkgprotocol.DeploymentAudit
}

struct DeploymentExport {
	format int = 1
	iso_sha256 string
	architecture string
	destination string
	sha256 string
	release_time i64 @[omitempty]
}

struct OfflineMediaExport {
	format int = 1
	destination string
	receipt Receipt
}

struct OfflineMediaVerification {
	format int = 1
	directory string
	iso_sha256 string
	architecture string
	deployment_sha256 string
	applications []string
	repositories []string
	release_time i64 @[omitempty]
}

fn check_inputs(configuration &pkgcore.ImageConfiguration, repositories &pkgcore.ImageRepositories, declaration string) !Preflight {
	report := if declaration == '' {
		configuration.check_repositories(repositories)!
	} else {
		configuration.check_application_file(repositories, declaration)!
	}
	defer { unsafe { report.free() } }
	return json2.decode[Preflight](report)
}

fn preflight(root string, arch string, config string, bundle string, declaration string, indexes string) !Preflight {
	mut configuration := pkgcore.prepare_image_configuration(root, arch, config)!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories_for_index_file(bundle, indexes, root)!
	defer { repositories.close() }
	report := check_inputs(unsafe { &configuration }, unsafe { &repositories }, declaration)!
	repositories.retire()!
	return report
}

fn package_selection(input Preflight, arch string, reviewed_origins map[string]string) !Selection {
	mut publishers := []pkgcore.IsoOfflinePublisher{cap: input.bundled_repositories.len}
	for index in input.bundled_repositories {
		configured := input.configuration.repositories.filter(it.id == index.id)
		if configured.len != 1 { return error('preflight omitted publisher ' + index.id) }
		reviewed_origin := reviewed_origins[index.id] or { index.reviewed_origin }
		if reviewed_origin != '' && (!reviewed_origin.starts_with('https://') || configured[0].url != reviewed_origin) {
			return error('ISO package URL differs from the reviewed HTTPS origin: ' + index.id)
		}
		publishers << pkgcore.IsoOfflinePublisher{id: index.id, public_key: configured[0].public_key, sequence: index.sequence,
			index_sha256: index.index_sha256, payload_bytes: index.payload_bytes, reviewed_origin: reviewed_origin}
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

enum PackageMemberKind {
	unrelated
	directory
	file
}

fn package_member_kind(path string) !PackageMemberKind {
	if path in ['/', '/etc', '/etc/vinix-packages', '/usr', '/usr/share',
		'/usr/share/vinix-packages', repository_path]! {
		return .directory
	}
	if path in [config_path, declaration_path]! { return .file }
	if !path.starts_with(repository_path + '/') { return .unrelated }
	// Check the archive spelling before creating anything on the host. The
	// scratch filesystem can fold names that Vinix stores as distinct entries.
	parts := path[repository_path.len + 1..].split('/')
	if pkgcore.identifier(parts[0]) {
		match parts.len {
			1 { return .directory }
			2 {
				if parts[1] == 'objects' { return .directory }
				if parts[1] in ['index.json', 'index.sig']! { return .file }
			}
			3 {
				if parts[1] == 'objects' && pkgcore.digest_valid(parts[2]) { return .file }
			}
			else {}
		}
	}
	return error('invalid ISO repository member: ' + path)
}

fn check_archive_parents(path string, entries map[string]u8) ! {
	for index in 1 .. path.len {
		if path[index] == `/` && entries[path[..index]] == `2` {
			return error('ISO initramfs member traverses a symbolic link: ' + path)
		}
	}
}

fn record_archive_member(path string, kind u8, link_name string, mut entries map[string]u8) ! {
	mut recorded := kind
	if kind == `1` {
		// USTAR hard link targets are names relative to the archive root.
		target := archive_path(link_name.trim_left('/'))!
		if package_member_kind(target)! != .unrelated {
			return error('ISO hard link targets a package member: ' + target)
		}
		check_archive_parents(target, entries)!
		if entries[target] != `0` {
			return error('ISO hard link requires an earlier regular file: ' + target)
		}
		recorded = `0`
	}
	// Boot keeps an earlier existing entry's type when a later create fails.
	if path !in entries && recorded in [u8(`0`), `2`, `5`]! { entries[path] = recorded }
}

fn capture_package_members(archive string, root string, expected Selection) ! {
	mut reader := tarstream.open_boot_ustar(archive)!
	defer { reader.close() }
	mut entries := map[string]u8{}
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
		check_archive_parents(path, entries)!
		kind := package_member_kind(path)!
		if kind == .unrelated {
			record_archive_member(path, member.kind, member.linkname, mut entries)!
			continue
		}
		if path in entries { return error('duplicate ISO package member: ' + path) }
		directory := os.dir(path)
		if directory != '/' && entries[directory] != `5` {
			return error('ISO package directory must precede its members: ' + directory)
		}
		if kind == .directory {
			if member.kind != `5` || member.mode & 0o022 != 0 || (path != '/' && member.mode & 0o555 != 0o555) {
				return error('invalid ISO package directory: ' + path)
			}
			if path != '/' { os.mkdir(root + path, mode: 0o755)! }
			entries[path] = `5`
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
		entries[path] = `0`
	}
}

fn check_iso(iso string, work string, expected Selection, expected_sha256 string, release_time i64, offline_media ?&pkgcore.IsoOfflineMedia) !Receipt {
	before := pkgcore.hash_file(iso)!
	if expected_sha256 != '' && before != expected_sha256 {
		return error('ISO SHA-256 differs from the package receipt')
	}
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
	repositories := root + repository_path
	bundle := if os.is_dir(repositories) && os.ls(repositories)!.len > 0 { repositories } else { '' }
	declaration := if os.is_file(root + declaration_path) { root + declaration_path } else { '' }
	mut configuration := pkgcore.prepare_image_configuration(root, expected.architecture, '')!
	defer { configuration.close() }
	if release_time != 0 {
		report := unsafe { &configuration }.audit_archived_image(bundle, declaration, root, release_time)!
		defer { unsafe { report.free() } }
		return validate_image_receipt(iso, before, expected, json2.decode[Preflight](report)!)
	}
	mut captured := unsafe { &configuration }.prepare_repositories_in(bundle, root)!
	defer { captured.close() }
	input := check_inputs(unsafe { &configuration }, unsafe { &captured }, declaration)!
	verified := validate_image_receipt(iso, before, expected, input)!
	if media := offline_media {
		deployment := pkgcore.read_release_lock_matching_digest(declaration, verified.deployment_sha256)!
		defer { unsafe { deployment.free() } }
		media.write(unsafe { &captured }, deployment)!
	}
	captured.retire()!
	return verified
}

fn validate_image_receipt(iso string, before string, expected Selection, input Preflight) !Receipt {
	if input.configuration_sha256 != expected.configuration_sha256 {
		return error('ISO package configuration differs from the preflight selection')
	}
	mut reviewed_origins := map[string]string{}
	for publisher in expected.publishers {
		if publisher.reviewed_origin != '' { reviewed_origins[publisher.id] = publisher.reviewed_origin }
	}
	actual := package_selection(input, expected.architecture, reviewed_origins)!
	if actual.publishers != expected.publishers { return error('ISO signed repositories differ from the preflight selection') }
	if actual.deployment_sha256 != expected.deployment_sha256 || actual.applications != expected.applications {
		return error('ISO application declaration differs from the preflight selection')
	}
	if pkgcore.hash_file(iso)! != before { return error('ISO changed during package verification') }
	return Receipt{iso_sha256: before, configuration_sha256: actual.configuration_sha256,
		deployment_sha256: actual.deployment_sha256, architecture: actual.architecture,
		applications: actual.applications, publishers: actual.publishers}
}

fn receipt_architecture(receipt Receipt) !string {
	if receipt.format != 1 || !pkgcore.digest_valid(receipt.iso_sha256) {
		return error('invalid ISO package receipt')
	}
	arch := match receipt.architecture {
		'x86_64' { 'amd64' }
		'aarch64' { 'arm64' }
		else { return error('unsupported receipt architecture: ' + receipt.architecture) }
	}
	return arch
}

fn print_checksums(path string) ! {
	raw := os.read_file(path)!
	receipt := json2.decode[Receipt](raw)!
	arch := receipt_architecture(receipt)!
	println('${receipt.iso_sha256}  vinix-${arch}.iso')
	println('${sha256.hexhash(raw)}  vinix-packages-${arch}.json')
}

fn origin_code_span(origin string) string {
	// CommonMark treats a shorter backtick run inside a code span literally.
	mut longest := 0
	mut run := 0
	for byte in origin {
		if byte == 0x60 {
			run++
			if run > longest { longest = run }
		} else { run = 0 }
	}
	marker := '`'.repeat(longest + 1)
	return if longest == 0 { marker + origin + marker } else { marker + ' ' + origin + ' ' + marker }
}

fn print_reviewed_origins(path string, digest string) ! {
	raw := os.read_file(path)!
	if !pkgcore.digest_valid(digest) || sha256.hexhash(raw) != digest {
		return error('package receipt changed before release notes were generated')
	}
	receipt := json2.decode[Receipt](raw)!
	arch := receipt_architecture(receipt)!
	publishers := receipt.publishers.filter(it.reviewed_origin != '')
	for publisher in publishers {
		if !pkgcore.identifier(publisher.id) || !publisher.reviewed_origin.starts_with('https://')
			|| !pkgprotocol.valid_repository_url(publisher.reviewed_origin) {
			return error('invalid reviewed HTTPS origin in ISO package receipt')
		}
	}
	for publisher in publishers {
		println('- `${publisher.id}` on ${arch} uses ${origin_code_span(publisher.reviewed_origin)}')
	}
}

fn workspace() !string {
	selected := os.getenv('TMPDIR')
	temp := if selected != '' { selected } else { os.temp_dir() }
	pattern := os.join_path(temp, 'vinix-iso-packages-XXXXXX')
	defer { unsafe { pattern.free() } }
	mut path := pattern.bytes()
	path << u8(0)
	defer { unsafe { path.free() } }
	created := C.mkdtemp(unsafe { &char(path.data) })
	if created == unsafe { nil } { return error('cannot create a private ISO verification workspace in ' + temp) }
	return unsafe { cstring_to_vstring(created).clone() }
}

// Only the release driver lends an existing capture. Other readers get an
// isolated copy whose pathname stays under the verifier's control.
fn receipt_image(source string, work string, staged bool) !string {
	if staged {
		parent := os.lstat(os.dir(source))!
		image := os.lstat(source)!
		uid := u32(os.geteuid())
		if parent.mode & 0o177777 != 0o040700 || parent.uid != uid
			|| image.mode & 0o177777 != 0o100400 || image.uid != uid || image.nlink != 1 {
			return error('expected a private read-only release ISO')
		}
		return source
	}
	image := work + '/image.iso'
	pkgcore.copy_file(source, image, 0, ~u64(0))!
	os.chmod(image, 0o400)!
	return image
}

fn plan_selection(env map[string]string, arch string) !Selection {
	config := imageinputs.environment_path(env, imageinputs.configuration, arch)
	bundle := imageinputs.environment_path(env, imageinputs.repositories, arch)
	declaration := imageinputs.environment_path(env, imageinputs.applications, arch)
	indexes := imageinputs.environment_path(env, imageinputs.indexes, arch)
	if config == '' && bundle == '' && declaration == '' && indexes == '' {
		return Selection{}
	}
	work := workspace()!
	defer { os.rmdir_all(work) or {} }
	input := preflight(work, arch, config, bundle, declaration, indexes)!
	return package_selection(input, arch, map[string]string{})
}

fn required_application_plan(env map[string]string, arch string) !Selection {
	selection := plan_selection(env, arch) or { return error('${arch} package preflight: ${err}') }
	if selection.applications.len == 0 {
		return error('${arch} requires an advertised application set for paired review')
	}
	return selection
}

fn archived_release_time(value string) !i64 {
	if value == '' || !value.bytes().all(it >= `0` && it <= `9`) {
		return error('archive verification requires a valid past Unix release time')
	}
	release_time := strconv.parse_int(value, 10, 64) or {
		return error('archive verification requires a valid past Unix release time')
	}
	if release_time <= 0 || release_time > time.now().unix() {
		return error('archive verification requires a valid past Unix release time')
	}
	return release_time
}

fn verify_published_image(source string, receipt Receipt, work string, release_time i64, offline_media ?&pkgcore.IsoOfflineMedia) !Receipt {
	receipt_architecture(receipt)!
	expected := Selection{
		architecture: receipt.architecture
		configuration_sha256: receipt.configuration_sha256
		deployment_sha256: receipt.deployment_sha256
		applications: receipt.applications
		publishers: receipt.publishers
	}
	iso := receipt_image(source, work, false)!
	return check_iso(iso, work, expected, receipt.iso_sha256, release_time, offline_media)
}

fn read_application_receipt(path string) !Receipt {
	receipt_text := pkgcore.read_metadata(path)!
	defer { unsafe { receipt_text.free() } }
	receipt := json2.decode[Receipt](receipt_text)!
	receipt_architecture(receipt)!
	if receipt.applications.len == 0 || !pkgcore.digest_valid(receipt.deployment_sha256) {
		return error('an ISO package receipt with an application declaration is required')
	}
	return receipt
}

fn export_deployment(arguments []string) ! {
	if arguments.len !in [3, 4]! {
		return error('usage: package-receipt export-deployment ISO RECEIPT.json NEW_FILE [RELEASE_UNIX_TIME]')
	}
	release_time := if arguments.len == 4 { archived_release_time(arguments[3])! } else { i64(0) }
	source := arguments[0]
	receipt := read_application_receipt(arguments[1])!
	destination := arguments[2]
	pkgcore.atomic_write_new_after(destination, fn [source, receipt, release_time] () !string {
		work := workspace()!
		defer { os.rmdir_all(work) or {} }
		verified := verify_published_image(source, receipt, work, release_time, none)!
		return pkgcore.read_release_lock_matching_digest(work + '/root' + declaration_path,
			verified.deployment_sha256)
	})!
	println(json2.encode(DeploymentExport{ iso_sha256: receipt.iso_sha256, architecture: receipt.architecture,
		destination: destination, sha256: receipt.deployment_sha256, release_time: release_time }))
}

fn export_offline(arguments []string) ! {
	if arguments.len != 3 {
		return error('usage: package-receipt export-offline ISO RECEIPT.json NEW_DIRECTORY')
	}
	source := arguments[0]
	receipt := read_application_receipt(arguments[1])!
	destination := arguments[2]
	pkgcore.write_iso_offline_media(destination, fn [source, receipt] (media &pkgcore.IsoOfflineMedia) ! {
		work := workspace()!
		defer { os.rmdir_all(work) or {} }
		verify_published_image(source, receipt, work, 0, media)!
	})!
	println(json2.encode(OfflineMediaExport{ destination: destination, receipt: receipt }))
}

fn verify_offline(arguments []string) ! {
	if arguments.len !in [2, 3]! {
		return error('usage: package-receipt verify-offline MEDIA_DIRECTORY RECEIPT.json [RELEASE_UNIX_TIME]')
	}
	release_time := if arguments.len == 3 { archived_release_time(arguments[2])! } else { i64(0) }
	directory := arguments[0]
	receipt := read_application_receipt(arguments[1])!
	if release_time == 0 {
		pkgcore.verify_iso_offline_media(directory, receipt.architecture, receipt.applications,
			receipt.deployment_sha256, receipt.publishers)!
	} else {
		pkgcore.verify_archived_iso_offline_media(directory, receipt.architecture, receipt.applications,
			receipt.deployment_sha256, receipt.publishers, release_time)!
	}
	println(json2.encode(OfflineMediaVerification{ directory: directory, iso_sha256: receipt.iso_sha256,
		architecture: receipt.architecture, deployment_sha256: receipt.deployment_sha256,
		applications: receipt.applications, repositories: receipt.publishers.map(it.id), release_time: release_time }))
}

fn verify_installed(arguments []string) !int {
	if arguments.len !in [4, 5]! {
		return error('usage: package-receipt verify-installed ISO RECEIPT.json SNAPSHOT.json SNAPSHOT_RECEIPT.json [RELEASE_UNIX_TIME]')
	}
	release_time := if arguments.len == 5 { archived_release_time(arguments[4])! } else { i64(0) }
	receipt := read_application_receipt(arguments[1])!
	saved_text := pkgcore.read_metadata(arguments[3])!
	defer { unsafe { saved_text.free() } }
	mut saved := pkgprotocol.decode_deployment_saved(saved_text)!
	defer { saved.close() }
	if saved.architecture != receipt.architecture { return error('installed snapshot architecture differs from the ISO receipt') }
	work := workspace()!
	defer { os.rmdir_all(work) or {} }
	verified := verify_published_image(arguments[0], receipt, work, release_time, none)!
	mut coverage := pkgcore.audit_saved_deployment_coverage(work + '/root' + declaration_path,
		verified.deployment_sha256, arguments[2], saved)!
	defer { coverage.close() }
	println(json2.encode(InstalledVerification{ release_time: release_time, receipt: verified,
		snapshot_sha256: saved.sha256, coverage: coverage }))
	return if coverage.matches { 0 } else { 3 }
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'checksums' {
		return print_checksums(os.args[2])
	}
	if os.args.len == 4 && os.args[1] == 'origins' {
		return print_reviewed_origins(os.args[2], os.args[3])
	}
	if os.args.len == 3 && os.args[1] == 'plan' {
		arch := os.args[2]
		if arch !in ['aarch64', 'x86_64']! { return error('unsupported package architecture: ' + arch) }
		selection := plan_selection(os.environ(), arch)!
		if selection.architecture != '' { println(json2.encode(selection)) }
		return
	}
	if os.args.len == 3 && os.args[1] == 'plan-pair' {
		env := os.environ()
		amd64 := required_application_plan(env, 'x86_64')!
		arm64 := required_application_plan(env, 'aarch64')!
		if amd64.applications != arm64.applications {
			return error('paired review requires the same advertised application IDs on x86_64 and aarch64')
		}
		return pkgcore.write_iso_package_review_pair(os.args[2], json2.encode(amd64) + '\n',
			json2.encode(arm64) + '\n')
	}
	if os.args.len >= 2 && os.args[1] == 'verify-installed' {
		exit(verify_installed(os.args[2..])!)
	}
	if os.args.len >= 2 && os.args[1] == 'export-deployment' {
		return export_deployment(os.args[2..])
	}
	if os.args.len >= 2 && os.args[1] == 'export-offline' {
		return export_offline(os.args[2..])
	}
	if os.args.len >= 2 && os.args[1] == 'verify-offline' {
		return verify_offline(os.args[2..])
	}
	archive := os.args.len == 5 && os.args[1] == 'verify-archive'
	if !archive && (os.args.len != 4 || os.args[1] !in ['verify', 'verify-staged', 'verify-receipt']!) {
		return error('usage: package-receipt plan ARCH | plan-pair NEW_DIRECTORY | verify ISO PLAN.json | verify-staged PRIVATE_ISO PLAN.json | verify-receipt ISO RECEIPT.json | verify-archive ISO RECEIPT.json RELEASE_UNIX_TIME | verify-installed ISO RECEIPT.json SNAPSHOT.json SNAPSHOT_RECEIPT.json [RELEASE_UNIX_TIME] | export-deployment ISO RECEIPT.json NEW_FILE [RELEASE_UNIX_TIME] | export-offline ISO RECEIPT.json NEW_DIRECTORY | verify-offline MEDIA_DIRECTORY RECEIPT.json [RELEASE_UNIX_TIME] | checksums RECEIPT.json | origins RECEIPT.json SHA256')
	}
	work := workspace()!
	defer { os.rmdir_all(work) or {} }
	if archive || os.args[1] == 'verify-receipt' {
		release_time := if archive { archived_release_time(os.args[4])! } else { i64(0) }
		receipt := json2.decode[Receipt](os.read_file(os.args[3])!)!
		verified := verify_published_image(os.args[2], receipt, work, release_time, none)!
		if archive { println(json2.encode(ArchiveAudit{release_time: release_time, receipt: verified})) }
		else { println(json2.encode(verified)) }
		return
	}
	expected := json2.decode[Selection](os.read_file(os.args[3])!)!
	iso := receipt_image(os.args[2], work, os.args[1] == 'verify-staged')!
	println(json2.encode(check_iso(iso, work, expected, '', 0, none)!))
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
