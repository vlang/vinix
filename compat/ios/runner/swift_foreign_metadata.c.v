// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftForeignMetadataFailure {}
fn (_ &SwiftForeignMetadataFailure) msg() string { return 'iOS: unsupported or invalid Swift foreign metadata template' }
fn (_ &SwiftForeignMetadataFailure) code() int { return 1 }
__global swift_foreign_metadata_failure_value = SwiftForeignMetadataFailure{}
fn swift_foreign_metadata_failure() IError { return unsafe { &swift_foreign_metadata_failure_value } }
struct SwiftForeignMetadataEntry { metadata u64 name u64 length u64 width u64 }

fn swift_foreign_relative(field u64) !u64 {
	delta:=i64(i32(read32(field)))
	if delta==0 || (delta<0 && field<u64(-delta)) || (delta>0 && field>~u64(0)-u64(delta)) { return swift_foreign_metadata_failure() }
	return u64(i64(field)+delta)
}
fn swift_foreign_name_length(name u64) !u64 {
	if name==0 || name>~u64(0)-1024 { return swift_foreign_metadata_failure() }
	for i in u64(0)..1024 {if unsafe {*(&u8(name+i))}==0 {return i}}
	return swift_foreign_metadata_failure()
}
// Immutable readable template, descriptor, names and VWT spans are supplied
// by the caller/image and remain alive until quiescent runtime shutdown.
fn swift_foreign_template_checked(metadata u64) !SwiftForeignMetadataEntry {
	if metadata<8 || metadata&7!=0 || metadata>~u64(0)-16 || read64(metadata)!=0x201 { return swift_foreign_metadata_failure() }
	descriptor:=read64(metadata+8)
	if descriptor==0 || descriptor&3!=0 || descriptor>~u64(0)-36 || read32(descriptor)!=0x60012
		|| read32(descriptor+16)!=0 || read32(descriptor+20)!=0
		|| read32(descriptor+28)!=0 || read32(descriptor+32)!=0 { return swift_foreign_metadata_failure() }
	witness:=read64(metadata-8)
	if witness==0 || witness&7!=0 || witness>~u64(0)-88 { return swift_foreign_metadata_failure() }
	width:=read64(witness+64)
	if width !in [u64(1),2,4,8]! || read64(witness+72)!=width || read32(witness+80)!=u32(width-1)
		|| read32(witness+84)!=0 { return swift_foreign_metadata_failure() }
	mut name:=swift_foreign_relative(descriptor+8)!;mut length:=swift_foreign_name_length(name)!
	if length==0 { return swift_foreign_metadata_failure() }
	// Imported identity is the N override after the Swift name, when present.
	// Related-entity/namespace tags need fuller identity parsing and reject.
	mut cursor:=name+length+1;mut renamed:=false
	for _ in 0..2 {
		tag_length:=swift_foreign_name_length(cursor)!
		if tag_length==0 {return SwiftForeignMetadataEntry{metadata,name,length,width}}
		if renamed || tag_length<2 || unsafe {*(&u8(cursor))}!=`N` { return swift_foreign_metadata_failure() }
		name=cursor+1;length=tag_length-1;renamed=true;cursor+=tag_length+1
	}
	return swift_foreign_metadata_failure()
}
fn swift_foreign_metadata_checked(_request u64,metadata u64) !SwiftAssociatedMetadata {
	if ios_runtime==unsafe {nil} || ios_runtime.swift_concurrency_retired { return swift_foreign_metadata_failure() }
	value:=swift_foreign_template_checked(metadata)!
	C.ios_objc_initialize_lock();defer {C.ios_objc_initialize_unlock()}
	for i in u64(0)..ios_runtime.swift_foreign_metadata_count {
		entry:=ios_runtime.swift_foreign_metadata[i]
		if entry.length==value.length && C.memcmp(voidptr(entry.name),voidptr(value.name),usize(value.length))==0 {
			if entry.width!=value.width { return swift_foreign_metadata_failure() }
			return SwiftAssociatedMetadata{metadata:entry.metadata}
		}
	}
	if ios_runtime.swift_foreign_metadata_count==64 { return swift_foreign_metadata_failure() }
	ios_runtime.swift_foreign_metadata[ios_runtime.swift_foreign_metadata_count]=value
	ios_runtime.swift_foreign_metadata_count++
	return SwiftAssociatedMetadata{metadata:metadata}
}
fn swift_foreign_metadata(request u64,metadata u64) SwiftAssociatedMetadata {
	return swift_foreign_metadata_checked(request,metadata) or {panic(err)}
}
fn swift_foreign_metadata_stop() {
	// Only borrowed pointers; no template, descriptor or witness is freed here.
	for i in u64(0)..ios_runtime.swift_foreign_metadata_count {ios_runtime.swift_foreign_metadata[i]=SwiftForeignMetadataEntry{}}
	ios_runtime.swift_foreign_metadata_count=0
}
