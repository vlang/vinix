// SPDX-License-Identifier: GPL-2.0-or-later
// SFNT table access is V; native CoreGraphics is only a behavioral reference.
module main

struct CGFontTable { offset u64 length u64 }
fn cg_font_be(bytes u64, offset u64, size u32) u32 {
	mut value:=u32(0)
	for i in u32(0)..size { value=(value<<8)|u32(unsafe{*(&u8(bytes+offset+i))}) }
	return value
}
fn cg_font_find(bytes u64, face u64, count u32, tag u32) ?CGFontTable {
	for i in u32(0)..count {
		record:=face+12+u64(i)*16
		if cg_font_be(bytes,record,4)==tag { return CGFontTable{u64(cg_font_be(bytes,record+8,4)),u64(cg_font_be(bytes,record+12,4))} }
	}
	return none
}
fn cg_font_bytes(source u64, length u64, index u32, provider u64) u64 {
	if source==0 || length<12 || length>16777216 { return 0 }
	// Parse the owned copy so later provider mutations cannot change offsets
	// between validation and a query. Failed construction releases this copy.
	font:=objc_allocate(ios_runtime.names['VinixCGFont']);mut header:=obj_header(font)
	header.data=[]u8{len:int(length)};header.data.flags|=.noslices
	C.memcpy(header.data.data,unsafe{voidptr(source)},usize(length))
	bytes:=u64(header.data.data)
	mut ready:=false
	defer { if !ready { objc_release(font) } }
	mut face:=u64(0)
	if cg_font_be(bytes,0,4)==0x74746366 {
		version:=cg_font_be(bytes,4,4);count:=cg_font_be(bytes,8,4)
		if version !in [u32(0x10000),0x20000]! || count==0 || count>64 || index>=count || 12+u64(count)*4>length { return 0 }
		face=u64(cg_font_be(bytes,12+u64(index)*4,4))
	} else if index!=0 { return 0 }
	if face>length || length-face<12 { return 0 }
	version:=cg_font_be(bytes,face,4);count:=cg_font_be(bytes,face+4,2)
	if version!=0x10000 || count==0 || count>4096 || u64(count)*16>length-face-12 { return 0 }
	for i in u32(0)..count {
		record:=face+12+u64(i)*16;tag:=cg_font_be(bytes,record,4)
		if tag==0 { return 0 }
		offset:=u64(cg_font_be(bytes,record+8,4));size:=u64(cg_font_be(bytes,record+12,4))
		if offset>length || size>length-offset { return 0 }
		for j in u32(0)..i { if cg_font_be(bytes,face+12+u64(j)*16,4)==tag { return 0 } }
	}
	head:=cg_font_find(bytes,face,count,0x68656164) or { return 0 }
	maxp:=cg_font_find(bytes,face,count,0x6d617870) or { return 0 }
	hhea:=cg_font_find(bytes,face,count,0x68686561) or { return 0 }
	if head.length<54 || maxp.length<6 || hhea.length<36 || cg_font_be(bytes,head.offset+12,4)!=0x5f0f3cf5 { return 0 }
	units:=cg_font_be(bytes,head.offset+18,2);glyphs:=cg_font_be(bytes,maxp.offset+4,2)
	if units<16 || units>16384 || glyphs==0 { return 0 }
	cg_font_find(bytes,face,count,0x676c7966) or { return 0 }
	loca:=cg_font_find(bytes,face,count,0x6c6f6361) or { return 0 }
	format:=cg_font_be(bytes,head.offset+50,2)
	if format>1 || loca.length<u64(glyphs+1)*if format==0{u64(2)}else{u64(4)} { return 0 }
	header.number=i64(face);header.section=i64(count)
	// Provider lifetime is independent of table copies, just as on CoreGraphics.
	header.fields[0]=objc_retain(provider)
	ready=true
	return font
}
fn cg_font_provider(provider u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if provider==0 || provider !in ios_runtime.objects || obj_header(provider).cls!=ios_runtime.names['VinixCGDataProvider'] { return 0 }
	return cg_font_bytes(data_pointer(provider),data_length(provider),0,provider)
}
fn cg_font_header(font u64) ?&ObjHeader {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if font==0 || font !in ios_runtime.objects { return none }
	header:=obj_header(font)
	if header.cls!=ios_runtime.names['VinixCGFont'] { return none }
	return header
}
fn cg_font_tags(font u64) u64 {
	header:=cg_font_header(font) or { return 0 }
	array:=objc_allocate(ios_runtime.names['NSArray']);mut result:=obj_header(array)
	// The public CFArray contains unboxed, non-owning four-byte tag values.
	result.cf_raw_values=true;result.items=[]u64{cap:int(header.section)};result.items.flags|=.noslices
	for i in i64(0)..header.section { result.items<<u64(cg_font_be(u64(header.data.data),u64(header.number)+12+u64(i)*16,4)) }
	return array
}
fn cg_font_table(font u64, tag u32) u64 {
	header:=cg_font_header(font) or { return 0 }
	table:=cg_font_find(u64(header.data.data),u64(header.number),u32(header.section),tag) or { return 0 }
	if table.length==0 { return 0 }
	return cf_data_create(0,u64(header.data.data)+table.offset,i64(table.length))
}
fn cg_font_glyph_count(font u64) u64 {
	header:=cg_font_header(font) or { return 0 }
	table:=cg_font_find(u64(header.data.data),u64(header.number),u32(header.section),0x6d617870) or { return 0 }
	return u64(cg_font_be(u64(header.data.data),table.offset+4,2))
}
fn cg_font_units(font u64) i32 {
	header:=cg_font_header(font) or { return 0 }
	table:=cg_font_find(u64(header.data.data),u64(header.number),u32(header.section),0x68656164) or { return 0 }
	return i32(cg_font_be(u64(header.data.data),table.offset+18,2))
}
fn cg_font_name(font u64, wanted u32) u64 {
	header:=cg_font_header(font) or { return 0 }
	base:=u64(header.data.data)
	table:=cg_font_find(base,u64(header.number),u32(header.section),0x6e616d65) or { return 0 }
	if table.length<6 || cg_font_be(base,table.offset,2)!=0 { return 0 }
	count:=cg_font_be(base,table.offset+2,2);strings:=u64(cg_font_be(base,table.offset+4,2))
	if u64(count)*12>table.length-6 || strings>table.length { return 0 }
	mut best:=u32(0);mut start:=u64(0);mut length:=u64(0);mut wide:=false
	for i in u32(0)..count {
		record:=table.offset+6+u64(i)*12
		if cg_font_be(base,record+6,2)!=wanted { continue }
		platform:=cg_font_be(base,record,2);encoding:=cg_font_be(base,record+2,2);language:=cg_font_be(base,record+4,2)
		score:=if platform==3 && encoding in [u32(1),10]! {if language==0x409{u32(4)}else{u32(2)}}else if platform==0{u32(3)}else if platform==1 && encoding==0 && language==0{u32(1)}else{u32(0)}
		size:=u64(cg_font_be(base,record+8,2));offset:=u64(cg_font_be(base,record+10,2))
		if score<=best || offset>table.length-strings || size>table.length-strings-offset { continue }
		best=score;start=table.offset+strings+offset;length=size;wide=platform!=1
	}
	if best==0 || length==0 || (wide && length&1!=0) { return 0 }
	mut text:=[]u8{cap:int(length)*2};text.flags|=.noslices
	defer { unsafe { text.free() } }
	mut cursor:=u64(0)
	for cursor<length {
		mut code:=cg_font_be(base,start+cursor,if wide{u32(2)}else{u32(1)});cursor+=if wide{u64(2)}else{u64(1)}
		if !wide && code>127 { return 0 }
		if code>=0xd800 && code<=0xdbff {
			if cursor+2>length { return 0 };low:=cg_font_be(base,start+cursor,2);cursor+=2
			if low<0xdc00 || low>0xdfff { return 0 };code=0x10000+((code-0xd800)<<10)+(low-0xdc00)
		} else if code>=0xdc00 && code<=0xdfff { return 0 }
		if code<128 { text<<u8(code) }
		else if code<0x800 { text<<u8(0xc0|(code>>6));text<<u8(0x80|(code&63)) }
		else if code<0x10000 { text<<u8(0xe0|(code>>12));text<<u8(0x80|((code>>6)&63));text<<u8(0x80|(code&63)) }
		else { text<<u8(0xf0|(code>>18));text<<u8(0x80|((code>>12)&63));text<<u8(0x80|((code>>6)&63));text<<u8(0x80|(code&63)) }
	}
	return owned_string(unsafe{tos(text.data,text.len)})
}
fn cg_font_postscript(font u64) u64 { return cg_font_name(font,6) }
fn cg_font_full_name(font u64) u64 { return cg_font_name(font,4) }
fn cg_font_id() u64 { return ios_runtime.names['VinixCGFont'] }
fn cg_font_symbol(symbol string) ?u64 {
	$if ios_text ? {
		if symbol=='_CGFontCreateWithFontName' { return u64(unsafe{voidptr(text_cg_font)}) }
	}
	return match symbol {
		'_CGFontCreateWithDataProvider' { u64(unsafe{voidptr(cg_font_provider)}) }
		'_CGFontCopyTableTags' { u64(unsafe{voidptr(cg_font_tags)}) }
		'_CGFontCopyTableForTag' { u64(unsafe{voidptr(cg_font_table)}) }
		'_CGFontCopyPostScriptName' { u64(unsafe{voidptr(cg_font_postscript)}) }
		'_CGFontCopyFullName' { u64(unsafe{voidptr(cg_font_full_name)}) }
		'_CGFontGetNumberOfGlyphs' { u64(unsafe{voidptr(cg_font_glyph_count)}) }
		'_CGFontGetUnitsPerEm' { u64(unsafe{voidptr(cg_font_units)}) }
		'_CGFontGetTypeID' { u64(unsafe{voidptr(cg_font_id)}) }
		'_CGFontRetain' { u64(unsafe{voidptr(objc_retain)}) }
		'_CGFontRelease' { u64(unsafe{voidptr(objc_release)}) }
		else { none }
	}
}
