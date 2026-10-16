// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Main/Main10, single-layer 4:2:0 descriptions. The RBSP reader is shared with
// AVC; it never copies the bitstream or allocates on a parameter query.
struct HEVCInfo {
mut:
	video H264Info
	profile u8
	compatibility u32
	constraints u64
	level u8
	layers u8
	nested bool
	depth u8
}
fn hevc_ptl(mut reader H264Bits, layers u32, mut info HEVCInfo) {
	info.profile=u8(h264_bits(mut reader,8))
	info.compatibility=h264_bits(mut reader,32)
	info.constraints=(u64(h264_bits(mut reader,16))<<32)|h264_bits(mut reader,32)
	info.level=u8(h264_bits(mut reader,8))
	mut profiles:=[7]bool{};mut levels:=[7]bool{}
	for i in u32(0)..layers { profiles[i]=h264_bits(mut reader,1)!=0;levels[i]=h264_bits(mut reader,1)!=0 }
	if layers>0 { for _ in layers..8 { h264_bits(mut reader,2) } }
	for i in u32(0)..layers {
		if profiles[i] { h264_bits(mut reader,32);h264_bits(mut reader,32);h264_bits(mut reader,24) }
		if levels[i] { h264_bits(mut reader,8) }
	}
}
fn hevc_scaling(mut reader H264Bits) {
	for size in 0..4 { for matrix:=0;matrix<6;matrix+=if size==3{3}else{1} {
		if h264_bits(mut reader,1)==0 { if h264_ue(mut reader)>u32(matrix) { reader.failed=true;return } }
		else { if size>1 { h264_se(mut reader) };for _ in 0..if size==0{16}else{64} { h264_se(mut reader) } }
	} }
}
fn hevc_rps(mut reader H264Bits, count u32) {
	mut deltas:=[64]u32{}
	for i in u32(0)..count {
		if i>0 && h264_bits(mut reader,1)!=0 {
			h264_bits(mut reader,1);h264_ue(mut reader)
			for _ in u32(0)..deltas[i-1]+1 {
				used:=h264_bits(mut reader,1)!=0
				if used || h264_bits(mut reader,1)!=0 { deltas[i]++ }
			}
		} else {
			negative:=h264_ue(mut reader);positive:=h264_ue(mut reader)
			if negative>16 || positive>16 || negative+positive>16 { reader.failed=true;return }
			deltas[i]=negative+positive
			for _ in u32(0)..deltas[i] { h264_ue(mut reader);h264_bits(mut reader,1) }
		}
		if deltas[i]>16 { reader.failed=true;return }
	}
}
fn hevc_sps(data u64, length u64) ?HEVCInfo {
	mut reader:=H264Bits{data:data+2,length:length-2}
	mut info:=HEVCInfo{}
	h264_bits(mut reader,4)
	layers:=h264_bits(mut reader,3);if layers>6 { return none }
	info.layers=u8(layers+1);info.nested=h264_bits(mut reader,1)!=0
	hevc_ptl(mut reader,layers,mut info)
	if info.profile !in [u8(1),2]! || h264_ue(mut reader)>15 { return none }
	if h264_ue(mut reader)!=1 { return none }
	width:=h264_ue(mut reader);height:=h264_ue(mut reader)
	if width==0 || height==0 || width>131072 || height>131072 { return none }
	mut crop_x:=u64(0);mut crop_y:=u64(0)
	if h264_bits(mut reader,1)!=0 {
		left:=h264_ue(mut reader);right:=h264_ue(mut reader);top:=h264_ue(mut reader);bottom:=h264_ue(mut reader)
		crop_x=(u64(left)+right)*2;crop_y=(u64(top)+bottom)*2
	}
	if crop_x>=width || crop_y>=height { return none }
	info.video.width=i32(u64(width)-crop_x);info.video.height=i32(u64(height)-crop_y)
	luma:=h264_ue(mut reader);chroma:=h264_ue(mut reader)
	if luma!=chroma || luma !in [u32(0),2]! { return none };info.depth=u8(luma)
	poc:=h264_ue(mut reader);if poc>12 { return none }
	ordering:=h264_bits(mut reader,1)!=0
	for _ in if ordering{u32(0)}else{layers}..layers+1 {
		if h264_ue(mut reader)>16 || h264_ue(mut reader)>16 { return none };h264_ue(mut reader)
	}
	for _ in 0..6 { if h264_ue(mut reader)>6 { return none } }
	if h264_bits(mut reader,1)!=0 && h264_bits(mut reader,1)!=0 { hevc_scaling(mut reader) }
	h264_bits(mut reader,1);h264_bits(mut reader,1)
	if h264_bits(mut reader,1)!=0 { h264_bits(mut reader,8);h264_ue(mut reader);h264_ue(mut reader);h264_bits(mut reader,1) }
	rps:=h264_ue(mut reader);if rps>64 { return none };hevc_rps(mut reader,rps)
	if h264_bits(mut reader,1)!=0 {
		count:=h264_ue(mut reader);if count>32 { return none }
		for _ in u32(0)..count { h264_bits(mut reader,poc+4);h264_bits(mut reader,1) }
	}
	h264_bits(mut reader,1);h264_bits(mut reader,1)
	info.video.progressive=true
	if h264_bits(mut reader,1)!=0 {
		if h264_bits(mut reader,1)!=0 {
			aspect:=h264_bits(mut reader,8)
			if aspect==255 { info.video.sar_width=h264_bits(mut reader,16);info.video.sar_height=h264_bits(mut reader,16) }
			else if aspect>0 && aspect<=16 {
				widths:=[u32(1),12,10,16,40,24,20,32,80,18,15,64,160,4,3,2]!
				heights:=[u32(1),11,11,11,33,11,11,11,33,11,11,33,99,3,2,1]!
				info.video.sar_width=widths[aspect-1];info.video.sar_height=heights[aspect-1]
			} else if aspect!=0 { return none }
		}
		if h264_bits(mut reader,1)!=0 { h264_bits(mut reader,1) }
		if h264_bits(mut reader,1)!=0 {
			h264_bits(mut reader,3);info.video.full_range=h264_bits(mut reader,1)!=0
			if h264_bits(mut reader,1)!=0 { info.video.primaries=h264_bits(mut reader,8);info.video.transfer=h264_bits(mut reader,8);info.video.matrix=h264_bits(mut reader,8) }
		}
		if h264_bits(mut reader,1)!=0 { info.video.chroma_top=h264_ue(mut reader);info.video.chroma_bottom=h264_ue(mut reader) }
		h264_bits(mut reader,1);info.video.progressive=h264_bits(mut reader,1)==0;h264_bits(mut reader,1)
		if !info.video.progressive { return none }
		// Display windows, HRD and spatial segmentation need additional metadata.
		if h264_bits(mut reader,1)!=0 { return none }
		if h264_bits(mut reader,1)!=0 {
			h264_bits(mut reader,32);h264_bits(mut reader,32)
			if h264_bits(mut reader,1)!=0 { h264_ue(mut reader) }
			if h264_bits(mut reader,1)!=0 { return none }
		}
		if h264_bits(mut reader,1)!=0 { return none }
	}
	if h264_bits(mut reader,1)!=0 { return none }
	if h264_bits(mut reader,1)!=1 { return none }
	for reader.bits!=0 { if h264_bits(mut reader,1)!=0 { return none } }
	if reader.failed || reader.offset!=reader.length || info.video.chroma_top>5 || info.video.chroma_bottom>5 || info.video.primaries !in [u32(1),2]! || info.video.transfer !in [u32(1),2]! || info.video.matrix !in [u32(1),2]! { return none }
	return info
}
fn hevc_metadata(info HEVCInfo, data u64) u64 {
	metadata:=h264_metadata(info.video,data)
	mut atoms:=obj_header(h264_named(metadata,'SampleDescriptionExtensionAtoms'))
	objc_release(atoms.keys[0]);atoms.keys[0]=owned_string('hvcC')
	h264_put(metadata,'BitsPerComponent',h264_number(i64(info.depth)+8))
	return metadata
}
fn hevc_duplicate(pointers &u64, sizes &u64, index u64) bool {
	pointer:=h264_word(u64(pointers)+index*8);size:=h264_word(u64(sizes)+index*8)
	for i in u64(0)..index {
		if h264_word(u64(sizes)+i*8)==size && C.memcmp(unsafe{voidptr(pointer)},unsafe{voidptr(h264_word(u64(pointers)+i*8))},usize(size))==0 { return true }
	}
	return false
}
fn hevc_vps(data u64, length u64) ?HEVCInfo {
	mut reader:=H264Bits{data:data+2,length:length-2}
	h264_bits(mut reader,6)
	if h264_bits(mut reader,6)!=0 { return none }
	layers:=h264_bits(mut reader,3);if layers>6 { return none }
	mut info:=HEVCInfo{layers:u8(layers+1),nested:h264_bits(mut reader,1)!=0}
	if h264_bits(mut reader,16)!=65535 { return none }
	hevc_ptl(mut reader,layers,mut info)
	if reader.failed { return none };return info
}
fn cm_hevc_create(allocator u64, count u64, pointers &u64, sizes &u64, length_size i32, extra u64, output &u64) i32 {
	if output==unsafe{nil} || pointers==unsafe{nil} || sizes==unsafe{nil} { return -12712 }
	if count<2 { return -12710 }
	if count>64 || length_size !in [i32(1),2,4]! { return -12712 }
	cf_allocator_check(allocator)
	// The extension snapshot is bounded and privately owned before merging.
	mut snapshot:=u64(0)
	defer { objc_release(snapshot) }
	if extra!=0 {
		if !objc_is_kind(extra,ios_runtime.names['NSDictionary']) { return -12710 }
		mut budget:=CMPropertyBudget{};snapshot=cm_property_snapshot(extra,0,mut budget) or { return -12710 }
		if h264_named(snapshot,'SampleDescriptionExtensionAtoms')!=0 { return -12718 }
	}
	mut counts:=[3]u32{};mut total:=u64(23);mut info:=HEVCInfo{};mut vps:=HEVCInfo{}
	for i in u64(0)..count {
		pointer:=h264_word(u64(pointers)+i*8);size:=h264_word(u64(sizes)+i*8)
		if pointer==0 || size==0 || size>65535 || total+size+2>1048576 { return -12712 }
		if size<2 { return -12714 }
		a:=unsafe{*(&u8(pointer))};b:=unsafe{*(&u8(pointer+1))};kind:=(a>>1)&63
		if a&128!=0 || b&7==0 { return -12714 }
		if a&1!=0 || b&0xf8!=0 { return -12718 }
		if kind<32 || kind>34 { return -12718 }
		if hevc_duplicate(pointers,sizes,i) { continue }
		// Replacing sets with equal IDs needs cross-set validation. Keep the
		// supported profile to one distinct record of each kind.
		if counts[kind-32]!=0 { return -12718 }
		if kind==32 { vps=hevc_vps(pointer,size) or { return -12714 } }
		if kind==33 {
			parsed:=hevc_sps(pointer,size) or { return -12714 }
			if counts[1]==0 { info=parsed } else if info!=parsed { return -12718 }
		}
		if kind==34 {
			mut reader:=H264Bits{data:pointer+2,length:size-2}
			if h264_ue(mut reader)>63 || h264_ue(mut reader)>15 || reader.failed { return -12714 }
		}
		if counts[kind-32]==0 { total+=3 };counts[kind-32]++;total+=size+2
	}
	if counts[0]==0 || counts[1]==0 { return -12710 }
	if vps.profile!=info.profile || vps.compatibility!=info.compatibility || vps.constraints!=info.constraints || vps.level!=info.level || vps.layers!=info.layers || vps.nested!=info.nested { return -12718 }
	mut hvcc:=[]u8{len:int(total)}
	defer { unsafe { hvcc.free() } }
	hvcc[0]=1;hvcc[1]=info.profile
	for i in 0..4 { hvcc[2+i]=u8(info.compatibility>>u32((3-i)*8)) }
	for i in 0..6 { hvcc[6+i]=u8(info.constraints>>u32((5-i)*8)) }
	hvcc[12]=info.level;hvcc[13]=0xf0;hvcc[15]=0xfc;hvcc[16]=0xfd;hvcc[17]=0xf8|info.depth;hvcc[18]=0xf8|info.depth
	hvcc[21]=(info.layers<<3)|if info.nested{u8(4)}else{u8(0)}|u8(length_size-1)
	mut cursor:=23
	for group in 0..3 {
		if counts[group]==0 { continue };hvcc[22]++
		hvcc[cursor]=u8(0xa0+group);hvcc[cursor+1]=u8(counts[group]>>8);hvcc[cursor+2]=u8(counts[group]);cursor+=3
		for i in u64(0)..count {
			pointer:=h264_word(u64(pointers)+i*8);size:=h264_word(u64(sizes)+i*8)
			if (unsafe{*(&u8(pointer))}>>1)&63!=u8(32+group) { continue }
			if hevc_duplicate(pointers,sizes,i) { continue }
			hvcc[cursor]=u8(size>>8);hvcc[cursor+1]=u8(size);cursor+=2
			C.memcpy(unsafe{voidptr(u64(hvcc.data)+u64(cursor))},unsafe{voidptr(pointer)},usize(size));cursor+=int(size)
		}
	}
	metadata:=hevc_metadata(info,cf_data_create(0,u64(hvcc.data),i64(total)))
	if snapshot!=0 {
		source:=obj_header(snapshot);mut target:=obj_header(metadata)
		for i,key in source.keys {
			mut found:=false
			for j,existing in target.keys { if string_text(existing)==string_text(key) { objc_release(target.items[j]);target.items[j]=objc_retain(source.items[i]);found=true;break } }
			if !found { target.keys<<objc_retain(key);target.items<<objc_retain(source.items[i]) }
		}
	}
	mut object:=u64(0)
	status:=cm_format_new(allocator,CMFormatState{media:0x76696465,subtype:0x68766331,dimensions:CMVideoDimensions{info.video.width,info.video.height}},0,&object)
	if status!=0 { objc_release(metadata);return status }
	mut header:=obj_header(object);header.fields[0]=metadata
	C.memcpy(unsafe{voidptr(output)},unsafe{voidptr(&object)},8)
	return 0
}
fn cm_hevc_parameter(object u64, index u64, pointer_out &u64, size_out &u64, count_out &u64, header_out &i32) i32 {
	if object==0 { return -12710 }
	state:=cm_format_state(object)
	if state.media!=0x76696465 || state.subtype !in [u32(0x68766331),0x68657631]! { return -12710 }
	data:=h264_named(h264_named(cm_format_extensions(object),'SampleDescriptionExtensionAtoms'),'hvcC')
	if data==0 || !objc_is_kind(data,ios_runtime.names['NSData']) || data_length(data)<23 { return -12710 }
	base:=data_pointer(data);length:=data_length(data)
	if unsafe{*(&u8(base))}!=1 { return -12710 }
	mut cursor:=u64(23);mut total:=u64(0);mut selected:=u64(0);mut selected_size:=u64(0)
	groups:=u32(unsafe{*(&u8(base+22))})
	for _ in u32(0)..groups {
		if cursor+3>length { return -12710 }
		entries:=(u32(unsafe{*(&u8(base+cursor+1))})<<8)|u32(unsafe{*(&u8(base+cursor+2))});cursor+=3
		for _ in u32(0)..entries {
			if cursor+2>length { return -12710 }
			size:=(u64(unsafe{*(&u8(base+cursor))})<<8)|u64(unsafe{*(&u8(base+cursor+1))});cursor+=2
			if size==0 || size>length-cursor { return -12710 }
			if total==index { selected=base+cursor;selected_size=size };total++;cursor+=size
		}
	}
	if cursor!=length { return -12710 }
	if pointer_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(pointer_out)},unsafe{voidptr(&selected)},8) }
	if size_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(size_out)},unsafe{voidptr(&selected_size)},8) }
	if count_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(count_out)},unsafe{voidptr(&total)},8) }
	header_size:=i32((unsafe{*(&u8(base+21))}&3)+1)
	if header_out!=unsafe{nil} { C.memcpy(unsafe{voidptr(header_out)},unsafe{voidptr(&header_size)},4) }
	return if selected==0 && (pointer_out!=unsafe{nil} || size_out!=unsafe{nil}) { -12712 } else { 0 }
}
fn coremedia_hevc_symbol(symbol string) ?u64 {
	return match symbol {
		'_CMVideoFormatDescriptionCreateFromHEVCParameterSets' { u64(unsafe{voidptr(cm_hevc_create)}) }
		'_CMVideoFormatDescriptionGetHEVCParameterSetAtIndex' { u64(unsafe{voidptr(cm_hevc_parameter)}) }
		else { none }
	}
}
