// SPDX-License-Identifier: GPL-2.0-or-later
// Administrator-provisioned launch identities for a separate account broker.
// This does not verify APK signatures or grant Android permissions.
module nativeaccountauth

import crypto.sha256
import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, int, ...voidptr) int
fn C.openat(int, &char, int, ...voidptr) int
fn C.close(int) int
fn C.fstat(int, &C.stat) int
fn C.read(int, voidptr, usize) isize
fn C.getuid() u32
fn C.geteuid() u32

const registry_header = 'vinix-android-account-authority-v1'
const max_registry_bytes = 64 * 1024

pub struct Entry {
pub:
	package_name       string
	uid                u32
	gid                u32
	apk                string
	apk_sha256         string
	certificate_sha256 string // administrator's signer attestation for this APK hash
	services           []Service
}

pub struct Service {
pub:
	class_name string
	action     string
	account_type string // optional administrator attestation for this pinned APK
}

// The loaded snapshot is immutable to callers. A registry never reloads itself
// after accepting a peer; administrative updates require a new broker process.
pub struct Registry {
	entries []Entry
}

// Optional request claims are checked, never used as the source of authority.
// -1 denotes an omitted UID/PID; other negative values are invalid.
pub struct Claims {
pub:
	package_name string
	uid          int = -1
	pid          int = -1
}

pub struct Caller {
pub:
	package_name       string
	uid                u32
	gid                u32
	pid                int
	apk_sha256         string
	certificate_sha256 string
}

fn absolute_clean_path(path string) bool {
	return path.len > 1 && path.len <= 4096 && path.starts_with('/')
		&& !path.ends_with('/') && !path.contains('\\') && !path.contains('\x00')
		&& path.bytes().all(it >= 32 && it != 127)
		&& path.split('/')[1..].all(it != '' && it != '.' && it != '..')
}

fn package_name_valid(name string) bool {
	parts := name.split('.')
	if name.len > 255 || parts.len < 2 { return false }
	for part in parts {
		if part.len == 0 || !(part[0].is_letter() || part[0] == `_`)
			|| !part.bytes().all(it.is_alnum() || it == `_`) { return false }
	}
	return true
}

fn hash_valid(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn service_identifier(value string, class_name bool) bool {
	if value.len == 0 || value.len > 255 || !value.contains('.') { return false }
	for part in value.split('.') {
		if part.len == 0 || !(part[0].is_letter() || part[0] == `_`)
			|| !part.bytes().all(it.is_alnum() || it == `_` || (class_name && it == `$`)) { return false }
	}
	return true
}

fn account_type_valid(value string) bool {
	// Registry delimiters and whitespace have no escaping. Account types are
	// opaque identifiers; they need not be Java package or class names.
	return value.len > 0 && value.len <= 255
		&& value.bytes().all(it > 32 && it < 127 && it != `@` && it != `,`)
}

fn parse_services(value string) ![]Service {
	if value == '-' { return []Service{} }
	parts := value.split(',')
	if parts.len > 16 { return error('too many account authority service selectors') }
	mut services := []Service{cap: parts.len}
	mut seen := map[string]bool{}
	for part in parts {
		pair := part.split('@')
		if pair.len !in [2, 3] || !service_identifier(pair[0], true) || !service_identifier(pair[1], false)
			|| (pair.len == 3 && !account_type_valid(pair[2])) {
			return error('invalid account authority service selector')
		}
		selector := pair[0] + '@' + pair[1]
		if selector in seen { return error('duplicate account authority service selector') }
		seen[selector] = true
		services << Service{class_name: pair[0], action: pair[1], account_type: if pair.len == 3 { pair[2] } else { '' }}
	}
	return services
}

fn application_id(value string) !u32 {
	if value.len != 5 || !value.bytes().all(it >= `0` && it <= `9`)
		|| value.int() < 10000 || value.int() > 19999 {
		return error('account authority IDs must be in 10000..19999')
	}
	return value.u32()
}

fn parse_registry(text string) !Registry {
	if text.len > max_registry_bytes || !text.ends_with('\n') || text.contains('\r')
		|| text.contains('\x00') { return error('invalid account authority registry framing') }
	lines := text[..text.len - 1].split('\n')
	if lines.len < 2 || lines.len > 65 || lines[0] != registry_header {
		return error('invalid account authority registry version or entry count')
	}
	mut entries := []Entry{cap: lines.len - 1}
	mut packages := map[string]bool{}
	mut uids := map[u32]bool{}
	mut gids := map[u32]bool{}
	mut paths := map[string]bool{}
	mut apks := map[string]bool{}
	for line in lines[1..] {
		fields := line.split('\t')
		if fields.len != 7 { return error('account authority entry must have seven fields') }
		name, apk := fields[0], fields[3]
		uid, gid := application_id(fields[1])!, application_id(fields[2])!
		if !package_name_valid(name) || !absolute_clean_path(apk)
			|| !hash_valid(fields[4]) || !hash_valid(fields[5]) {
			return error('invalid account authority package, APK path or digest')
		}
		// One process identity belongs to exactly one package. Companion code
		// loaded in that process cannot claim a separate package's authority.
		if name in packages || uid in uids || gid in gids || apk in paths || fields[4] in apks {
			return error('ambiguous account authority package, IDs or APK')
		}
		packages[name] = true
		uids[uid] = true
		gids[gid] = true
		paths[apk] = true
		apks[fields[4]] = true
		entries << Entry{name, uid, gid, apk, fields[4], fields[5], parse_services(fields[6])!}
	}
	return Registry{entries}
}

fn protected_metadata(mode u32, uid u32, links u64, size u64, directory bool, limit u64) bool {
	if uid != 0 { return false }
	if directory {
		return mode & u32(C.S_IFMT) == u32(C.S_IFDIR) && mode & 0o022 == 0
	}
	return mode & u32(C.S_IFMT) == u32(C.S_IFREG) && mode & 0o222 == 0
		&& links == 1 && size <= limit
}

fn protected_stat(fd int, directory bool, limit u64) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || !protected_metadata(u32(info.st_mode), info.st_uid,
		u64(info.st_nlink), u64(info.st_size), directory, limit) {
		return error('account authority input must be protected by Unix root ownership and modes')
	}
	return info
}

// Walk from an opened root directory using dirfds. No component may be a
// symlink or writable by another Unix identity. The final fd pins the inode;
// hashing never reopens the pathname. Root is the trusted administrator.
fn open_protected(path string, limit u64) !int {
	if !absolute_clean_path(path) { return error('account authority input path must be absolute and canonical') }
	parts := path.split('/')[1..]
	mut directory := unsafe { C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
	if directory < 0 { return error('cannot open account authority filesystem root') }
	defer { C.close(directory) }
	protected_stat(directory, true, 0)!
	for part in parts[..parts.len - 1] {
		next := unsafe { C.openat(directory, &char(part.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
		if next < 0 { return error('cannot open protected account authority directory') }
		protected_stat(next, true, 0) or {
			C.close(next)
			return err
		}
		C.close(directory)
		directory = next
	}
	last := parts[parts.len - 1]
	fd := unsafe { C.openat(directory, &char(last.str), C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK) }
	if fd < 0 { return error('cannot open protected account authority file') }
	protected_stat(fd, false, limit) or {
		C.close(fd)
		return err
	}
	return fd
}

fn protected_registry(path string) !string {
	fd := open_protected(path, max_registry_bytes)!
	defer { C.close(fd) }
	mut bytes := []u8{len: max_registry_bytes + 1}
	mut count := 0
	for count < bytes.len {
		n := unsafe { C.read(fd, &bytes[count], usize(bytes.len - count)) }
		if n < 0 { return error('cannot read account authority registry') }
		if n == 0 { return bytes[..count].bytestr() }
		count += int(n)
	}
	return error('account authority registry exceeds size limit')
}

fn protected_apk_digest(path string) !string {
	fd := open_protected(path, u64(2) * 1024 * 1024 * 1024)!
	defer { C.close(fd) }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	mut size := u64(0)
	for {
		n := unsafe { C.read(fd, buffer.data, usize(buffer.len)) }
		if n < 0 { return error('cannot read account authority APK') }
		if n == 0 { break }
		size += u64(n)
		if size > u64(2) * 1024 * 1024 * 1024 { return error('account authority APK exceeds size limit') }
		hash.write(buffer[..int(n)])!
	}
	protected_stat(fd, false, u64(2) * 1024 * 1024 * 1024)!
	return hash.sum([]u8{}).hex()
}

// Load and verify a fixed root-provisioned registry and every pinned APK. The
// signer digest is an administrator attestation, not a signature verifier.
pub fn load(path string) !Registry {
	registry := parse_registry(protected_registry(path)!)!
	for entry in registry.entries {
		if protected_apk_digest(entry.apk)! != entry.apk_sha256 {
			return error('account authority APK digest mismatch')
		}
	}
	return registry
}

pub fn (registry Registry) verify_launch(apk string, uid u32, gid u32) !Entry {
	for entry in registry.entries {
		if entry.apk == apk && entry.uid == uid && entry.gid == gid {
			// Recheck the launch inode: the registry may have been loaded earlier.
			if protected_apk_digest(apk)! != entry.apk_sha256 {
				return error('account authority launch APK digest mismatch')
			}
			return entry
		}
	}
	return error('APK and selected Unix IDs are not registered for account authority')
}

pub fn (registry Registry) verify_service(apk string, uid u32, gid u32, class_name string, action string) !Entry {
	entry := registry.verify_launch(apk, uid, gid)!
	for service in entry.services {
		if service.class_name == class_name && service.action == action { return entry }
	}
	return error('service and action are not registered for account authority')
}

fn selected_authenticator_type(entry Entry, launch ServiceLaunch) !string {
	if entry.package_name != launch.package_name || entry.apk_sha256 != launch.apk_sha256 {
		return error('authenticator attestation does not match service package or APK pin')
	}
	for service in entry.services {
		if service.class_name == launch.service && service.action == launch.action {
			// Legacy two-part selectors authorize launch only, never account writes.
			return service.account_type
		}
	}
	return error('authenticator attestation does not match registered service selector')
}

// The administrator attests the selected service's account type for these exact
// APK bytes. Recheck the protected APK digest before publishing that authority.
pub fn (registry Registry) verify_authenticator_type(apk string, uid u32, gid u32, launch ServiceLaunch) !string {
	entry := registry.verify_service(apk, uid, gid, launch.service, launch.action)!
	return selected_authenticator_type(entry, launch)
}

fn (registry Registry) authenticate_peer(peer Peer, claims Claims) !Caller {
	if peer.pid <= 0 || claims.uid < -1 || claims.pid < -1 { return error('invalid account caller identity') }
	for entry in registry.entries {
		if entry.uid != peer.uid || entry.gid != peer.gid { continue }
		if (claims.package_name != '' && claims.package_name != entry.package_name)
			|| (claims.uid != -1 && claims.uid != int(peer.uid))
			|| (claims.pid != -1 && claims.pid != peer.pid) {
			return error('account caller claims do not match the authenticated Unix peer')
		}
		return Caller{entry.package_name, peer.uid, peer.gid, peer.pid, entry.apk_sha256, entry.certificate_sha256}
	}
	return error('Unix peer is not registered for account authority')
}

// Obtain the identity from this connected socket for each new request. Never
// use caller-supplied Bundle values as the source of UID, PID or package.
pub fn (registry Registry) authenticate(fd int, claims Claims) !Caller {
	return registry.authenticate_peer(peer_credentials(fd)!, claims)
}

// Optional launcher policy, checked before dropping credentials or starting
// ART. Presence with any invalid value fails closed; absence keeps existing
// launch behavior and provides no account-broker authority.
pub fn verify_environment_launch(apk string, uid u32, gid u32, selected bool) ! {
	path := os.getenv_opt('VINIX_ANDROID_ACCOUNT_REGISTRY') or { return }
	if !selected || C.getuid() != 0 || C.geteuid() != 0 {
		return error('account authority launch requires an administrator-selected Unix identity')
	}
	registry := load(path)!
	registry.verify_launch(apk, uid, gid)!
}
