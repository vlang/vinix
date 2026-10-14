// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

// The service holds its reader lock throughout this read-only scan. Existing
// format-1 verify frames identify work; completion follows every successful
// payload and launcher check. Status never calls this helper.
fn verify_installed(directory string, state State, report fn (pkgprotocol.Progress)) ! {
	report(pkgprotocol.Progress{ phase: 'verify' })
	number := state.generation.str()
	generation := '${directory}/generations/${number}'
	defer { unsafe { generation.free(); number.free() } }
	for installed in state.packages {
		p := installed.package
		for file in p.files {
			report(pkgprotocol.Progress{ phase: 'verify', package: p.id, repository: installed.repository, path: file.path })
			path := '${generation}/apps/${p.id}/${file.path}'
			valid := verified_installed_file(path, file)
			unsafe { path.free() }
			if !valid { return error('${p.id}: installed payload verification failed: ${file.path}; use Repair / install') }
		}
		if p.kind !in ['runtime', 'data'] {
			path := 'share/applications/vinix-${p.id}.desktop'
			report(pkgprotocol.Progress{ phase: 'verify', package: p.id, repository: installed.repository, path: path })
			unsafe { path.free() }
			if !verified_registration(generation, p) { return error('${p.id}: installed application registration verification failed; use Repair / install') }
		}
	}
	report(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
}
