// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Authenticated manifests already own every nested field. Transfer them into
// the public reply and copy only publisher identities borrowed from Config.
fn owned_refresh_catalog(catalog Catalog) Catalog {
	mut packages := []Installed{cap: catalog.packages.len}
	for installed in catalog.packages {
		value := Installed{...installed, repository: installed.repository.clone(), public_key: installed.public_key.clone()}
		pointer := unsafe { &value }; unsafe { packages.push_many(pointer, 1) }
	}
	unsafe { (&array(&catalog.packages)).free() }
	return Catalog{packages: packages}
}

// Only independently owned replies from refresh()/Service.refresh(). Low-level
// load_catalog()/snapshots_catalog() and synthetic catalogs borrow identities.
pub fn (mut catalog Catalog) close() {
	for installed in catalog.packages {
		unsafe { installed.repository.free(); installed.public_key.free() }
		close_decoded_package(installed.package)
	}
	unsafe { (&array(&catalog.packages)).free() }
	catalog = Catalog{}
}
