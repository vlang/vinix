// SPDX-License-Identifier: GPL-2.0-or-later
// Parallel format-2 contract. Format-1 readers and receipts are unchanged.
module audiocontinue

pub const format2_profile = 'native-audio-readonly-donor-v2'
pub const aggregate_cap2 = u64(2048) << 20
pub const reviewed_legacy_plan2 = 'd939f4091b42d556db5739845e9f099c0f2cd877a0be4332b91beeb665e90290'
pub const reviewed_source_contract2 = 'reviewed-content-with-base-provenance'

// No executable argument vector or environment is accepted from this Plan.
// The legacy Plan supplies only the already reviewed original tool identities.
pub struct Plan2 {
pub:
	format int = 2
	profile string = format2_profile
	architecture string = 'aarch64'
	state_root string
	donor_manifest_path string
	donor_manifest_sha256 string
	legacy_plan_path string
	legacy_plan_sha256 string
	source_manifest_path string
	source_manifest_sha256 string
	source_root string
	source_base_revision string
	controller_sha256 string
	preparation_reserve_bytes u64
	receipt_reserve_bytes u64
	rootfs_archive_bytes_per_scenario u64
	wave_bytes_per_scenario u64
	logs_bytes_per_scenario u64
	wall_ms int
}

// Paths in a role are relative leaves below one canonical immutable root.
// The fixed role table is checked by load_donor2, not trusted from JSON.
pub struct Borrow2 {
pub:
	root string
	path string
	kind string
	sha256 string
}

pub struct DonorEntry2 {
pub:
	root string
	path string
	kind string
	mode u32
	uid u32
	gid u32
	dev u64
	inode u64
	nlink u64
	size u64
	mtime i64
	ctime i64
	sha256 string
}

pub struct Donor2 {
pub:
	format int = 2
	profile string = format2_profile
	// Exactly capture + store, both complete, including every historical alias.
	roots map[string]string
	entries []DonorEntry2
	roles map[string]Borrow2
}

pub struct Source2 {
pub:
	format int = 2
	profile string = format2_profile
	content_contract string = reviewed_source_contract2
	root string
	// HEAD names a base only. Reviewed complete entries are authoritative;
	// this format deliberately makes no clean-working-tree claim.
	base_revision string
	entries []DonorEntry2
}

pub struct Fresh2 {
pub:
	path string
	kind string
	sha256 string
}

// Publishing the sole excluded regular receipt changes the state root's
// directory nlink/size/times (APFS counts regular children in nlink). Other
// represented root metadata and all nonroot metadata remain exact.
pub struct OwnedEntry2 {
pub:
	path string
	kind string
	mode u32
	uid u32
	gid u32
	dev u64
	inode u64
	nlink u64
	size u64
	mtime i64
	ctime i64
	sha256 string
}

pub struct Preparation2 {
pub:
	format int = 2
	profile string = format2_profile
	architecture string = 'aarch64'
	completed_at i64
	state_root string
	plan_path string
	plan_sha256 string
	donor_manifest_path string
	donor_manifest_sha256 string
	legacy_plan_path string
	legacy_plan_sha256 string
	source_manifest_path string
	source_manifest_sha256 string
	source_root string
	source_base_revision string
	controller_sha256 string
	borrowed map[string]Borrow2
	fresh map[string]Fresh2
	scenarios []string
	extras_path string
	tree []OwnedEntry2
}

pub struct RunClaim2 {
pub:
	format int = 2
	profile string = format2_profile
	state_root string
	preparation_sha256 string
	controller_sha256 string
	// A claim is never native acceptance, even if the owner is interrupted.
	native_qualification bool
}

pub struct LegacyPlan2 {
pub:
	format int
	profile string
	source_revision string
	state_root string
	audit_root string
	kernel_seal_sha256 string
	kernel_sha256 string
	roots map[string]string
	files map[string]string
	inputs map[string]map[string]string
	charged_roots []string
	cap_bytes u64
	prepare_wall_ms int
}
