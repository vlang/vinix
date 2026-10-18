// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// A public preview outlives its authenticated catalog, configuration, installed
// state and caller's root strings. Copy every nested manifest field explicitly;
// the resolver's Plan continues to borrow those fields on internal paths.
fn owned_plan_package(p Package) Package {
	mut dependencies := []Dependency{cap: p.dependencies.len}
	for dependency in p.dependencies {
		value := Dependency{id: dependency.id.clone(), minimum: dependency.minimum.clone(), before: dependency.before.clone()}
		pointer := unsafe { &value }; unsafe { dependencies.push_many(pointer, 1) }
	}
	mut files := []Payload{cap: p.files.len}
	for payload in p.files {
		value := Payload{...payload, path: payload.path.clone(), sha256: payload.sha256.clone()}
		pointer := unsafe { &value }; unsafe { files.push_many(pointer, 1) }
	}
	return Package{...p, id: p.id.clone(), version: p.version.clone(), architecture: p.architecture.clone(),
		name: p.name.clone(), description: p.description.clone(), homepage: p.homepage.clone(), license: p.license.clone(),
		kind: p.kind.clone(), runtime: p.runtime.clone(), entrypoint: p.entrypoint.clone(),
		arguments: review_strings(p.arguments), permissions: review_strings(p.permissions), associations: review_strings(p.associations),
		dependencies: dependencies, files: files}
}

fn owned_plan(plan Plan) Plan {
	mut packages := []Installed{cap: plan.packages.len}
	for installed in plan.packages {
		value := Installed{...installed, package: owned_plan_package(installed.package),
			repository: installed.repository.clone(), public_key: installed.public_key.clone()}
		pointer := unsafe { &value }; unsafe { packages.push_many(pointer, 1) }
	}
	return Plan{requested: review_strings(plan.requested), packages: packages}
}

// Only independently owned previews from Service.plan()/preview_plan().
// resolve(), transaction plans and caller-built values borrow fields and must
// retain their existing lifetime. Repeated close of one preview is harmless.
pub fn (mut plan Plan) close() {
	unsafe {
		for id in plan.requested { id.free() }
		(&array(&plan.requested)).free()
		for installed in plan.packages {
			installed.repository.free(); installed.public_key.free()
			close_decoded_package(installed.package)
		}
		(&array(&plan.packages)).free()
	}
	plan = Plan{}
}
