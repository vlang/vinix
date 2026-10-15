// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// Wire representation of deployment formats 1 and 2. Decoding checks the JSON
// schema and allocation limits; the service checks identities, versions, target
// architecture, catalog provenance and policy before planning any operation.
pub struct DeploymentPin {
pub:
	id               string
	version          string
	architecture     string
	repository       string
	public_key       string
	minimum_sequence u64
	metadata_sha256  string
}

pub struct DeploymentDocument {
pub:
	format       int
	architecture string
	packages     []string
	locked       []DeploymentPin
}

fn close_deployment_pin(pin DeploymentPin) {
	unsafe {
		pin.id.free(); pin.version.free(); pin.architecture.free(); pin.repository.free()
		pin.public_key.free(); pin.metadata_sha256.free()
	}
}

// Only independently decoded documents own their fields. close is repeatable.
pub fn (mut document DeploymentDocument) close() {
	unsafe {
		document.architecture.free()
		for id in document.packages { id.free() }
		(&array(&document.packages)).free()
		for pin in document.locked { close_deployment_pin(pin) }
		(&array(&document.locked)).free()
	}
	document = DeploymentDocument{}
}
