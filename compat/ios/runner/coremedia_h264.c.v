// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A bounded RBSP reader skips emulation-prevention bytes without copying a NAL.
struct H264Bits {
	data u64
	length u64
mut:
	offset u64
	byte u8
	bits u32
	zeros u32
	failed bool
}
struct H264Info {
mut:
	profile u8
	compatibility u8
	level u8
	width i32
	height i32
	progressive bool
	sar_width u32
	sar_height u32
	full_range bool
	primaries u32 = 2
	transfer u32 = 2
	matrix u32 = 2
	chroma_top u32
	chroma_bottom u32
}
fn h264_bits(mut reader H264Bits, count u32) u32 {
	if count > 32 || reader.failed { reader.failed = true; return 0 }
	mut value := u32(0)
	for _ in u32(0)..count {
		if reader.bits == 0 {
			if reader.offset >= reader.length { reader.failed = true; return 0 }
			mut byte := unsafe { *(&u8(reader.data + reader.offset)) }; reader.offset++
			if reader.zeros >= 2 && byte == 3 {
				if reader.offset >= reader.length { reader.failed = true; return 0 }
				byte = unsafe { *(&u8(reader.data + reader.offset)) }; reader.offset++
				if byte > 3 { reader.failed = true; return 0 }
				reader.zeros = 0
			}
			reader.zeros = if byte == 0 { reader.zeros + 1 } else { u32(0) }
			reader.byte = byte; reader.bits = 8
		}
		reader.bits--; value = (value << 1) | ((u32(reader.byte) >> reader.bits) & 1)
	}
	return value
}
fn h264_ue(mut reader H264Bits) u32 {
	mut zeros := u32(0)
	for h264_bits(mut reader, 1) == 0 {
		if reader.failed || zeros == 31 { reader.failed = true; return 0 }
		zeros++
	}
	return (u32(1) << zeros) - 1 + h264_bits(mut reader, zeros)
}
fn h264_se(mut reader H264Bits) i64 {
	value := h264_ue(mut reader)
	return if value & 1 == 0 { -i64(value / 2) } else { (i64(value) + 1) / 2 }
}
fn h264_hrd(mut reader H264Bits) {
	count := h264_ue(mut reader)
	if count > 31 { reader.failed = true; return }
	h264_bits(mut reader, 8)
	for _ in u32(0)..count+1 { h264_ue(mut reader); h264_ue(mut reader); h264_bits(mut reader,1) }
	h264_bits(mut reader,20)
}
fn h264_sps(data u64, length u64) ?H264Info {
	if length < 5 { return none }
	mut reader := H264Bits{data:data+1,length:length-1}
	mut info := H264Info{}
	info.profile = u8(h264_bits(mut reader,8)); info.compatibility = u8(h264_bits(mut reader,8)); info.level = u8(h264_bits(mut reader,8))
	if h264_ue(mut reader) > 31 || info.profile !in [u8(66),77,88,100]! { return none }
	if info.profile == 100 {
		// This profile supports eight-bit 4:2:0; other chroma/bit depths stay explicit.
		if h264_ue(mut reader) != 1 || h264_ue(mut reader) != 0 || h264_ue(mut reader) != 0 { return none }
		h264_bits(mut reader,1)
		if h264_bits(mut reader,1) != 0 {
			for i in 0..8 {
				if h264_bits(mut reader,1) == 0 { continue }
				mut last := i64(8); mut next := i64(8)
				for _ in 0..if i<6 {16}else{64} { if next != 0 { next = (last+h264_se(mut reader)) & 255 }; if next != 0 { last=next } }
			}
		}
	}
	if h264_ue(mut reader) > 12 { return none }
	poc := h264_ue(mut reader)
	if poc == 0 { if h264_ue(mut reader) > 12 { return none } }
	else if poc == 1 {
		h264_bits(mut reader,1); h264_se(mut reader); h264_se(mut reader)
		count := h264_ue(mut reader); if count > 255 { return none }
		for _ in u32(0)..count { h264_se(mut reader) }
	} else if poc != 2 { return none }
	if h264_ue(mut reader) > 16 { return none }
	h264_bits(mut reader,1)
	width := h264_ue(mut reader); height := h264_ue(mut reader)
	if width > 8191 || height > 8191 { return none }
	info.progressive = h264_bits(mut reader,1) != 0
	if !info.progressive { h264_bits(mut reader,1) }
	h264_bits(mut reader,1)
	mut crop_x := u64(0); mut crop_y := u64(0)
	if h264_bits(mut reader,1) != 0 {
		left:=h264_ue(mut reader); right:=h264_ue(mut reader); top:=h264_ue(mut reader); bottom:=h264_ue(mut reader)
		crop_x=(u64(left)+right)*2; crop_y=(u64(top)+bottom)*if info.progressive {u64(2)}else{u64(4)}
	}
	full_width := u64(width+1)*16; full_height := u64(height+1)*if info.progressive {u64(16)}else{u64(32)}
	if crop_x >= full_width || crop_y >= full_height { return none }
	info.width=i32(full_width-crop_x); info.height=i32(full_height-crop_y)
	if h264_bits(mut reader,1) != 0 {
		if h264_bits(mut reader,1) != 0 {
			aspect := h264_bits(mut reader,8)
			if aspect == 255 { info.sar_width=h264_bits(mut reader,16); info.sar_height=h264_bits(mut reader,16) }
			else if aspect > 0 && aspect <= 16 {
				widths := [u32(1),12,10,16,40,24,20,32,80,18,15,64,160,4,3,2]!
				heights := [u32(1),11,11,11,33,11,11,11,33,11,11,33,99,3,2,1]!
				info.sar_width=widths[aspect-1]; info.sar_height=heights[aspect-1]
			} else if aspect != 0 { return none }
		}
		if h264_bits(mut reader,1) != 0 { h264_bits(mut reader,1) }
		if h264_bits(mut reader,1) != 0 {
			h264_bits(mut reader,3); info.full_range=h264_bits(mut reader,1)!=0
			if h264_bits(mut reader,1) != 0 { info.primaries=h264_bits(mut reader,8); info.transfer=h264_bits(mut reader,8); info.matrix=h264_bits(mut reader,8) }
		}
		if h264_bits(mut reader,1) != 0 { info.chroma_top=h264_ue(mut reader); info.chroma_bottom=h264_ue(mut reader) }
		if h264_bits(mut reader,1) != 0 { h264_bits(mut reader,32); h264_bits(mut reader,32); h264_bits(mut reader,1) }
		nal_hrd := h264_bits(mut reader,1)!=0; if nal_hrd { h264_hrd(mut reader) }
		vcl_hrd := h264_bits(mut reader,1)!=0; if vcl_hrd { h264_hrd(mut reader) }
		if nal_hrd || vcl_hrd { h264_bits(mut reader,1) }
		h264_bits(mut reader,1)
		if h264_bits(mut reader,1)!=0 { h264_bits(mut reader,1); for _ in 0..6 { h264_ue(mut reader) } }
	}
	if reader.failed || info.chroma_top>5 || info.chroma_bottom>5 || info.primaries !in [u32(1),2]! || info.transfer !in [u32(1),2]! || info.matrix !in [u32(1),2]! { return none }
	return info
}

// These helpers transfer each newly owned value into an immutable dictionary.
fn h264_put(dictionary u64, key string, value u64) {
	mut header:=obj_header(dictionary); header.keys<<owned_string(key); header.items<<value
}
fn h264_number(value i64) u64 { object:=objc_allocate(ios_runtime.names['NSNumber']); mut header:=obj_header(object); header.number=value; return object }
fn h264_word(pointer u64) u64 { mut value:=u64(0); C.memcpy(unsafe{&value},unsafe{voidptr(pointer)},8); return value }
fn h264_metadata(info H264Info, avcc u64) u64 {
	extensions:=objc_allocate(ios_runtime.names['NSDictionary'])
	if info.progressive { h264_put(extensions,'CVFieldCount',h264_number(1)) }
	chroma := ['Left','Center','TopLeft','Top','BottomLeft','Bottom']!
	h264_put(extensions,'CVImageBufferChromaLocationTopField',owned_string(chroma[info.chroma_top]))
	h264_put(extensions,'CVImageBufferChromaLocationBottomField',owned_string(chroma[info.chroma_bottom]))
	if info.sar_width!=0 && info.sar_height!=0 {
		aspect:=objc_allocate(ios_runtime.names['NSDictionary'])
		h264_put(aspect,'HorizontalSpacing',h264_number(i64(info.sar_width))); h264_put(aspect,'VerticalSpacing',h264_number(i64(info.sar_height)))
		h264_put(extensions,'CVPixelAspectRatio',aspect)
	}
	if info.primaries==1 { h264_put(extensions,'CVImageBufferColorPrimaries',owned_string('ITU_R_709_2')) }
	if info.transfer==1 { h264_put(extensions,'CVImageBufferTransferFunction',owned_string('ITU_R_709_2')) }
	if info.matrix==1 { h264_put(extensions,'CVImageBufferYCbCrMatrix',owned_string('ITU_R_709_2')) }
	h264_put(extensions,'FullRangeVideo',objc_retain(framework_object(if info.full_range {'_kCFBooleanTrue'}else{'_kCFBooleanFalse'})))
	atoms:=objc_allocate(ios_runtime.names['NSDictionary']); h264_put(atoms,'avcC',avcc); h264_put(extensions,'SampleDescriptionExtensionAtoms',atoms)
	return extensions
}
fn cm_h264_create(allocator u64, count u64, pointers &u64, sizes &u64, length_size i32, output &u64) i32 {
	if output==unsafe{nil} || count<2 || count>64 || pointers==unsafe{nil} || sizes==unsafe{nil} || length_size !in [i32(1),2,4]! { return -12712 }
	cf_allocator_check(allocator)
	mut sps:=u32(0); mut pps:=u32(0); mut total:=u64(7); mut info:=H264Info{}
	for i in u64(0)..count {
		pointer:=h264_word(u64(pointers)+i*8); size:=h264_word(u64(sizes)+i*8)
		if pointer==0 || size==0 || size>65535 || total+size+2>1048576 { return -12712 }
		header:=unsafe{*(&u8(pointer))}; kind:=header&31
		if header&128!=0 { return -12710 }
		if kind==7 {
			if size<5 { return -12714 }
			parsed:=h264_sps(pointer,size) or { return -12710 }
			if sps==0 { info=parsed } else if parsed!=info { return -12718 }
			sps++
		} else if kind==8 { if size<2 { return -12714 }; pps++ }
		else { return -12712 }
		total+=size+2
	}
	if sps==0 || sps>31 || pps==0 || pps>255 { return -12712 }
	if info.profile==100 { total+=4 }
	mut avcc:=[]u8{len:int(total)}
	defer { unsafe { avcc.free() } }
	avcc[0]=1; avcc[1]=info.profile; avcc[2]=info.compatibility; avcc[3]=info.level; avcc[4]=u8(0xfc|u32(length_size-1)); avcc[5]=u8(0xe0|sps)
	mut cursor:=6
	for kind in [u8(7),8]! {
		if kind==8 { avcc[cursor]=u8(pps); cursor++ }
		for i in u64(0)..count {
			pointer:=h264_word(u64(pointers)+i*8); size:=h264_word(u64(sizes)+i*8)
			if unsafe{*(&u8(pointer))}&31!=kind { continue }
			avcc[cursor]=u8(size>>8); avcc[cursor+1]=u8(size); cursor+=2
			C.memcpy(unsafe{voidptr(u64(avcc.data)+u64(cursor))},unsafe{voidptr(pointer)},usize(size)); cursor+=int(size)
		}
	}
	if info.profile==100 { avcc[cursor]=0xfd; avcc[cursor+1]=0xf8; avcc[cursor+2]=0xf8; avcc[cursor+3]=0 }
	data:=cf_data_create(0,u64(avcc.data),i64(total)); extensions:=h264_metadata(info,data)
	mut object:=u64(0)
	status:=cm_format_new(allocator,CMFormatState{media:0x76696465,subtype:0x61766331,dimensions:CMVideoDimensions{info.width,info.height}},0,&object)
	if status!=0 { objc_release(extensions); return status }
	mut header:=obj_header(object); header.fields[0]=extensions
	C.memcpy(unsafe{voidptr(output)},unsafe{voidptr(&object)},8)
	return 0
}
fn h264_named(dictionary u64, name string) u64 {
	if dictionary==0 || !objc_is_kind(dictionary,ios_runtime.names['NSDictionary']) { return 0 }
	header:=obj_header(dictionary)
	for i,key in header.keys { if objc_is_kind(key,ios_runtime.names['NSString']) && string_text(key)==name { return header.items[i] } }
	return 0
}
fn cm_h264_parameter(object u64, index u64, pointer_out &u64, size_out &u64, count_out &u64, header_out &i32) i32 {
	if object==0 { return -12710 }
	state:=cm_format_state(object)
	if state.media!=0x76696465 || state.subtype!=0x61766331 { return -12710 }
	data:=h264_named(h264_named(cm_format_extensions(object),'SampleDescriptionExtensionAtoms'),'avcC')
	if data==0 || !objc_is_kind(data,ios_runtime.names['NSData']) || data_length(data)<7 { return -12710 }
	base:=data_pointer(data); length:=data_length(data)
	if unsafe{*(&u8(base))}!=1 { return -12710 }
	mut cursor:=u64(6); mut total:=u64(0); mut selected:=u64(0); mut selected_size:=u64(0)
	for group in 0..2 {
		if cursor>=length { return -12710 }
		entries:=if group==0 { u32(unsafe{*(&u8(base+5))})&31 } else { u32(unsafe{*(&u8(base+cursor))}) }
		if group==1 { cursor++ }
		for _ in u32(0)..entries {
			if cursor+2>length { return -12710 }
			size:=(u64(unsafe{*(&u8(base+cursor))})<<8)|u64(unsafe{*(&u8(base+cursor+1))}); cursor+=2
			if size==0 || size>length-cursor { return -12710 }
			if total==index { selected=base+cursor; selected_size=size }
			total++; cursor+=size
		}
	}
	if pointer_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(pointer_out)},unsafe{voidptr(&selected)},8) }
	if size_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(size_out)},unsafe{voidptr(&selected_size)},8) }
	if count_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(count_out)},unsafe{voidptr(&total)},8) }
	header_size:=i32((unsafe{*(&u8(base+4))}&3)+1)
	if header_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(header_out)},unsafe{voidptr(&header_size)},4) }
	return if selected==0 && (pointer_out!=unsafe{nil} || size_out!=unsafe{nil}) { -12712 } else { 0 }
}
fn coremedia_h264_symbol(symbol string) ?u64 {
	return match symbol {
		'_CMVideoFormatDescriptionCreateFromH264ParameterSets' { u64(unsafe{voidptr(cm_h264_create)}) }
		'_CMVideoFormatDescriptionGetH264ParameterSetAtIndex' { u64(unsafe{voidptr(cm_h264_parameter)}) }
		else { none }
	}
}
