// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.utf8
import tools.packages.pkgprotocol

// Filesystem names can contain arbitrary bytes. Preserve readable UTF-8, escape
// controls/invalid bytes and disclose truncation within the protocol's bound.
fn health_diagnostic(text string) string {
	mut bytes := []u8{cap: pkgprotocol.health_diagnostic_limit}
	defer { unsafe { bytes.free() } }
	mut at := 0
	for at < text.len {
		lead := text[at]
		length := if lead < 0x80 { 1 } else if lead >= 0xc2 && lead <= 0xdf { 2 }
			else if lead >= 0xe0 && lead <= 0xef { 3 } else if lead >= 0xf0 && lead <= 0xf4 { 4 } else { 0 }
		valid := length > 0 && at + length <= text.len && utf8.validate_str(unsafe { tos(text.str + at, length) })
		escaped := !valid || lead < 32 || lead == 127 || (lead == 0xc2 && text[at + 1] <= 0x9f)
		amount := if escaped { 4 } else { length }
		if bytes.len + amount > pkgprotocol.health_diagnostic_limit - 12 {
			for byte in ' [truncated]' { bytes << byte }
			break
		}
		if escaped {
			bytes << `\\`; bytes << `x`; bytes << '0123456789abcdef'[lead >> 4]; bytes << '0123456789abcdef'[lead & 15]
			at++
		} else {
			for index in 0 .. length { bytes << text[at + index] }
			at += length
		}
	}
	return bytes.bytestr()
}

struct InstalledHealthFinding { issue string diagnostic string }

// A rejected namespace must never reach payload reads through that path.
fn installed_namespace_problem(directory string, generation u64, p Package) string {
	verify_installed_namespace(directory, generation, p) or {
		// Clone before returning any text derived from the error. This keeps
		// the compiler from extending the error receiver's lifetime.
		owned := err.msg()
		message := owned.clone()
		diagnostic := health_diagnostic(message)
		unsafe { message.free(); owned.free(); err.free() }
		return diagnostic
	}
	return ''
}

fn inspect_installed_package(directory string, generation u64, p Package) InstalledHealthFinding {
	problem := installed_namespace_problem(directory, generation, p)
	if problem != '' { return InstalledHealthFinding{ issue: 'namespace', diagnostic: problem } }
	number := generation.str()
	root := '${directory}/generations/${number}'
	defer { unsafe { root.free(); number.free() } }
	for file in p.files {
		path := '${root}/apps/${p.id}/${file.path}'
		valid := verified_installed_file(path, file)
		unsafe { path.free() }
		if !valid {
			message := 'Installed payload failed verification: ${file.path}'
			diagnostic := health_diagnostic(message)
			unsafe { message.free() }
			return InstalledHealthFinding{ issue: 'payload', diagnostic: diagnostic }
		}
	}
	if !verified_registration(root, p) {
		return InstalledHealthFinding{ issue: 'registration', diagnostic: 'Installed launcher or file associations failed verification.'.clone() }
	}
	return InstalledHealthFinding{}
}

fn installed_health_report(directory string, state State, report fn (pkgprotocol.Progress)) !pkgprotocol.HealthReport {
	report(pkgprotocol.Progress{ phase: 'verify' })
	mut rows := []pkgprotocol.PackageHealth{cap: state.packages.len}
	unsafe { rows.flags |= .noslices }
	for installed in state.packages {
		p := installed.package
		report(pkgprotocol.Progress{ phase: 'verify', package: p.id, repository: installed.repository })
		finding := inspect_installed_package(directory, state.generation, p)
		row := pkgprotocol.PackageHealth{ id: p.id.clone(), name: p.name.clone(), version: p.version.clone(),
			kind: p.kind.clone(), repository: installed.repository.clone(), public_key: installed.public_key.clone(),
			issue: finding.issue.clone(), diagnostic: finding.diagnostic }
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	rows.sort(a.id < b.id)
	mut result := pkgprotocol.HealthReport{ generation: state.generation, architecture: state.architecture.clone(), rows: rows }
	result.validate() or { result.close(); return err }
	// Complete means every package was inspected, including when issues exist.
	report(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	return result
}
