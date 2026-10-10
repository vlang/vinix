// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The compatibility profile is iOS 17.0, as reported by UIDevice. Swift's
// availability query must use this profile rather than the host OS version.
const ios_system_version_text = '17.0'

// Measured from the installed Swift library: three signed, pointer-sized
// fields, returned indirectly through x8 by the ordinary ARM64 C ABI.
struct IosOperatingSystemVersion {
	major i64
	minor i64
	patch i64
}
fn ios_operating_system_version() IosOperatingSystemVersion {
	return IosOperatingSystemVersion{ major: 17, minor: 0, patch: 0 }
}
