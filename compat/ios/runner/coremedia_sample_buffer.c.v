// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct CMTime {
	value i64
	scale i32
	flags u32
	epoch i64
}
struct CMSampleTiming {
	duration CMTime
	pts CMTime
	dts CMTime
}
struct CMSampleSummary {
mut:
	duration CMTime = CMTime{0,1,1,0}
	pts CMTime
	dts CMTime
}
struct CMSampleState {
mut:
	timing &CMSampleTiming = unsafe { nil }
	sizes &u64 = unsafe { nil }
	count i64
	timing_count i64
	size_count i64
	total u64
	summary CMSampleSummary
	callback u64
	context u64
	ready bool
	valid bool
	making bool
}
type CMSampleReadyCallback = fn (u64,u64) i32
fn cm_sample_id() u64 { return ios_runtime.names['VinixCMSampleBuffer'] }
fn cm_sample_state(object u64) &CMSampleState {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: expected a live CMSampleBuffer') }
	if header.cls != cm_sample_id() || header.cm_sample == unsafe { nil } { panic('iOS: expected a live CMSampleBuffer') }
	return header.cm_sample
}
fn cm_sample_read_timing(source &CMSampleTiming, index i64) CMSampleTiming {
	// CoreMedia records have four-byte alignment, including their 64-bit words.
	mut value := CMSampleTiming{}
	C.memcpy(unsafe { &value }, unsafe { voidptr(u64(source)+u64(index)*72) }, 72)
	return value
}
fn cm_sample_read_size(source &u64, index i64) u64 {
	mut value := u64(0)
	C.memcpy(unsafe { &value }, unsafe { voidptr(u64(source)+u64(index)*8) }, 8)
	return value
}
fn cm_sample_time_supported(t CMTime) bool {
	if t.flags == 0 { return true }
	if t.flags in [u32(5),9,17]! { return t.value==0 && t.scale==0 && t.epoch==0 }
	return t.flags in [u32(1),3]! && t.scale>0
}
fn cm_sample_time_scale(t CMTime, count i64) ?CMTime {
	if t.flags==0 { return CMTime{} }
	if t.flags&28!=0 { return t }
	if count<=0 || t.value>i64(9223372036854775807)/count || t.value<(-i64(9223372036854775807)-1)/count { return none }
	return CMTime{t.value*count,t.scale,t.flags,t.epoch}
}
fn cm_sample_time_advance(t CMTime, duration CMTime, index i64) ?CMTime {
	if index==0 { return t }
	if t.flags==0 || duration.flags==0 { return CMTime{} }
	if t.flags&28!=0 { return t }
	if duration.flags&28!=0 || duration.epoch!=0 || t.scale!=duration.scale { return none }
	delta := cm_sample_time_scale(duration,index) or { return none }
	if (delta.value>0 && t.value>i64(9223372036854775807)-delta.value) || (delta.value<0 && t.value<(-i64(9223372036854775807)-1)-delta.value) { return none }
	return CMTime{t.value+delta.value,t.scale,t.flags|duration.flags,t.epoch}
}
fn cm_sample_time_min(a CMTime, b CMTime) ?CMTime {
	if a.flags==0 { return if b.flags==0 { CMTime{} } else { b } }
	if b.flags==0 { return a }
	if a.flags&28!=0 || b.flags&28!=0 || a.scale!=b.scale { return none }
	return if b.epoch<a.epoch || (b.epoch==a.epoch && b.value<a.value) { b } else { a }
}
fn cm_sample_summarize(count i64, entries i64, timing &CMSampleTiming) ?CMSampleSummary {
	mut summary := CMSampleSummary{}
	if entries==0 { return summary }
	for i in i64(0)..entries {
		row := cm_sample_read_timing(timing,i)
		if !cm_sample_time_supported(row.duration) || !cm_sample_time_supported(row.pts) || !cm_sample_time_supported(row.dts) { return none }
		if i==0 {
			summary.duration = if row.duration.flags==0 { CMTime{} } else { row.duration }
			summary.pts = if row.pts.flags==0 { CMTime{} } else { row.pts }
			summary.dts = if row.dts.flags==0 { CMTime{} } else { row.dts }
		} else {
			a := summary.duration; b := row.duration
			if a.flags==0 || b.flags==0 { summary.duration=CMTime{} }
			else {
				if a.flags&28!=0 || b.flags&28!=0 || a.scale!=b.scale || a.epoch!=0 || b.epoch!=0 { return none }
				if (b.value>0 && a.value>i64(9223372036854775807)-b.value) || (b.value<0 && a.value<(-i64(9223372036854775807)-1)-b.value) { return none }
				summary.duration=CMTime{a.value+b.value,a.scale,a.flags|b.flags,0}
			}
			summary.pts=cm_sample_time_min(summary.pts,row.pts) or { return none }
			summary.dts=cm_sample_time_min(summary.dts,row.dts) or { return none }
		}
	}
	if entries==1 {
		row := cm_sample_read_timing(timing,0)
		summary.duration=cm_sample_time_scale(row.duration,count) or { return none }
		cm_sample_time_advance(row.pts,row.duration,count-1) or { return none }
		cm_sample_time_advance(row.dts,row.duration,count-1) or { return none }
	}
	return summary
}
fn cm_sample_clear(mut header ObjHeader) {
	mut state := header.cm_sample
	if state==unsafe { nil } { return }
	state.valid=false; state.ready=false; state.callback=0; state.context=0
	state.count=0; state.timing_count=0; state.size_count=0; state.total=0
	C.free(state.timing); C.free(state.sizes)
	state.timing=unsafe { nil }; state.sizes=unsafe { nil }
	data:=header.fields[0]; format:=header.fields[1]
	header.fields[0]=0; header.fields[1]=0
	// Release outside the registry lock; a block's final release can call client code.
	objc_release(data); objc_release(format)
}
fn cm_sample_dispose(mut header ObjHeader) {
	if header.cm_sample==unsafe { nil } { return }
	cm_sample_clear(mut header)
	C.free(header.cm_sample)
	header.cm_sample=unsafe { nil }
}
fn cm_sample_create(allocator u64, data u64, ready u8, callback u64, context u64, format u64, count i64, timing_count i64, timing &CMSampleTiming, size_count i64, sizes &u64, output &u64) i32 {
	if output==unsafe { nil } { return -12731 }
	unsafe { *output=0 }
	if timing_count<0 || size_count<0 || (count==0 && (timing_count!=0 || size_count!=0)) || (timing_count!=0 && timing_count!=1 && timing_count!=count) || (size_count!=0 && size_count!=1 && size_count!=count) { return -12738 }
	if count<0 || count>65536 || (timing_count!=0 && timing==unsafe { nil }) || (size_count!=0 && sizes==unsafe { nil }) { return -12731 }
	cf_allocator_check(allocator)
	if data!=0 { cm_block_state(data) }
	if format!=0 { cm_format_state(format) }
	summary := cm_sample_summarize(count,timing_count,timing) or { return -12740 }
	mut total:=u64(0)
	for i in i64(0)..size_count {
		size:=cm_sample_read_size(sizes,i)
		multiplier:=if size_count==1 { u64(count) } else { u64(1) }
		if size>0x7fffffff || size*multiplier>0x7fffffff-total { return -12742 }
		total+=size*multiplier
	}
	mut state:=unsafe { &CMSampleState(C.calloc(1,sizeof(CMSampleState))) }
	if state==unsafe { nil } { return -12730 }
	if timing_count!=0 {
		state.timing=unsafe { &CMSampleTiming(C.malloc(usize(timing_count)*72)) }
		if state.timing==unsafe { nil } { C.free(state); return -12730 }
		C.memcpy(unsafe { voidptr(state.timing) },unsafe { voidptr(timing) },usize(timing_count)*72)
	}
	if size_count!=0 {
		state.sizes=unsafe { &u64(C.malloc(usize(size_count)*8)) }
		if state.sizes==unsafe { nil } { C.free(state.timing); C.free(state); return -12730 }
		C.memcpy(unsafe { voidptr(state.sizes) },unsafe { voidptr(sizes) },usize(size_count)*8)
	}
	state.count=count; state.timing_count=timing_count; state.size_count=size_count; state.total=total
	state.summary=summary; state.callback=callback; state.context=context; state.ready=ready!=0; state.valid=true
	object:=objc_allocate(cm_sample_id())
	mut header:=obj_header(object); header.cm_sample=state
	header.fields[0]=objc_retain(data); header.fields[1]=objc_retain(format)
	unsafe { *output=object }
	return 0
}
fn cm_sample_valid(object u64) u8 { return if object==0 { u8(0) } else { u8(cm_sample_state(object).valid) } }
fn cm_sample_ready(object u64) u8 { if object==0 { return 0 }; state:=cm_sample_state(object); return u8(state.valid && state.ready) }
fn cm_sample_count(object u64) i64 { if object==0 { return 0 }; state:=cm_sample_state(object); return if state.valid { state.count } else { i64(0) } }
fn cm_sample_data(object u64) u64 { return if cm_sample_valid(object)==0 { u64(0) } else { obj_header(object).fields[0] } }
fn cm_sample_format(object u64) u64 { return if cm_sample_valid(object)==0 { u64(0) } else { obj_header(object).fields[1] } }
fn cm_sample_image(object u64) u64 { cm_sample_valid(object); return 0 } // This constructor carries block data, not image buffers.
fn cm_sample_duration(object u64) CMTime { return if cm_sample_valid(object)==0 { CMTime{} } else { cm_sample_state(object).summary.duration } }
fn cm_sample_pts(object u64) CMTime { return if cm_sample_valid(object)==0 { CMTime{} } else { cm_sample_state(object).summary.pts } }
fn cm_sample_dts(object u64) CMTime { return if cm_sample_valid(object)==0 { CMTime{} } else { cm_sample_state(object).summary.dts } }
fn cm_sample_total(object u64) u64 { return if cm_sample_valid(object)==0 { u64(0) } else { cm_sample_state(object).total } }
fn cm_sample_size(object u64, index i64) u64 {
	if cm_sample_valid(object)==0 { return 0 }
	state:=cm_sample_state(object)
	if index<0 || index>=state.count || state.size_count==0 { return 0 }
	return cm_sample_read_size(state.sizes,if state.size_count==1 { i64(0) } else { index })
}
fn cm_sample_timing_array(object u64, capacity i64, output &CMSampleTiming, needed &i64) i32 {
	if object==0 { return -12731 }
	state:=cm_sample_state(object); if !state.valid { return -12744 }
	unsafe { if needed!=nil { *needed=state.timing_count } }
	if state.timing_count==0 { return -12736 }
	if output==unsafe { nil } { return 0 }
	if capacity<state.timing_count { return -12737 }
	C.memcpy(unsafe { voidptr(output) },unsafe { voidptr(state.timing) },usize(state.timing_count)*72)
	return 0
}
fn cm_sample_size_array(object u64, capacity i64, output &u64, needed &i64) i32 {
	if object==0 { return -12731 }
	state:=cm_sample_state(object); if !state.valid { return -12744 }
	unsafe { if needed!=nil { *needed=state.size_count } }
	if state.size_count==0 { return -12735 }
	if output==unsafe { nil } { return 0 }
	if capacity<state.size_count { return -12737 }
	C.memcpy(unsafe { voidptr(output) },unsafe { voidptr(state.sizes) },usize(state.size_count)*8)
	return 0
}
fn cm_sample_timing_at(object u64, index i64, output &CMSampleTiming) i32 {
	if object==0 || output==unsafe { nil } { return -12731 }
	state:=cm_sample_state(object); if !state.valid { return -12744 }
	if state.timing_count==0 { return -12736 }
	if index<0 || index>=state.count { return -12734 }
	mut row:=cm_sample_read_timing(state.timing,if state.timing_count==1 { i64(0) } else { index })
	if state.timing_count==1 && index!=0 {
		row=CMSampleTiming{row.duration,cm_sample_time_advance(row.pts,row.duration,index) or { return -12740 },cm_sample_time_advance(row.dts,row.duration,index) or { return -12740 }}
	}
	C.memcpy(unsafe { voidptr(output) },unsafe { &row },72)
	return 0
}
fn cm_sample_set_data(object u64, data u64) i32 {
	if object==0 || data==0 { return -12731 }
	if cm_sample_valid(object)==0 { return -12744 }
	cm_block_state(data)
	mut header:=obj_header(object)
	if header.fields[0]!=0 { return -12732 }
	header.fields[0]=objc_retain(data)
	return 0
}
fn cm_sample_set_ready(object u64) i32 {
	if object==0 { return -12731 }
	mut state:=cm_sample_state(object)
	if !state.valid { return -12744 }
	state.ready=true
	return 0
}
fn cm_sample_make_ready(object u64) i32 {
	if object==0 { return -12731 }
	mut state:=cm_sample_state(object)
	if !state.valid { return -12744 }
	if state.ready { return 0 }
	if state.making || state.callback==0 { return -12733 }
	state.making=true
	// No registry lock is held while invoking client code.
	status:=unsafe { CMSampleReadyCallback(voidptr(state.callback))(object,state.context) }
	state.making=false
	if status==0 && state.valid { state.ready=true }
	return status
}
fn cm_sample_invalidate(object u64) i32 {
	if object==0 { return -12731 }
	mut state:=cm_sample_state(object)
	if !state.valid { return -12744 }
	// Native hides metadata immediately, but retains the backing owners until
	// final release. Invalidation does not revoke separately retained owners.
	state.valid=false; state.ready=false
	return 0
}
fn coremedia_sample_symbol(symbol string) ?u64 {
	return match symbol {
		'_CMSampleBufferCreate' { u64(unsafe { voidptr(cm_sample_create) }) }
		'_CMSampleBufferGetTypeID' { u64(unsafe { voidptr(cm_sample_id) }) }
		'_CMSampleBufferGetDataBuffer' { u64(unsafe { voidptr(cm_sample_data) }) }
		'_CMSampleBufferGetFormatDescription' { u64(unsafe { voidptr(cm_sample_format) }) }
		'_CMSampleBufferGetImageBuffer' { u64(unsafe { voidptr(cm_sample_image) }) }
		'_CMSampleBufferGetNumSamples' { u64(unsafe { voidptr(cm_sample_count) }) }
		'_CMSampleBufferGetDuration' { u64(unsafe { voidptr(cm_sample_duration) }) }
		'_CMSampleBufferGetPresentationTimeStamp' { u64(unsafe { voidptr(cm_sample_pts) }) }
		'_CMSampleBufferGetDecodeTimeStamp' { u64(unsafe { voidptr(cm_sample_dts) }) }
		'_CMSampleBufferGetTotalSampleSize' { u64(unsafe { voidptr(cm_sample_total) }) }
		'_CMSampleBufferGetSampleSize' { u64(unsafe { voidptr(cm_sample_size) }) }
		'_CMSampleBufferGetSampleSizeArray' { u64(unsafe { voidptr(cm_sample_size_array) }) }
		'_CMSampleBufferGetSampleTimingInfo' { u64(unsafe { voidptr(cm_sample_timing_at) }) }
		'_CMSampleBufferGetSampleTimingInfoArray' { u64(unsafe { voidptr(cm_sample_timing_array) }) }
		'_CMSampleBufferIsValid' { u64(unsafe { voidptr(cm_sample_valid) }) }
		'_CMSampleBufferDataIsReady' { u64(unsafe { voidptr(cm_sample_ready) }) }
		'_CMSampleBufferSetDataBuffer' { u64(unsafe { voidptr(cm_sample_set_data) }) }
		'_CMSampleBufferSetDataReady' { u64(unsafe { voidptr(cm_sample_set_ready) }) }
		'_CMSampleBufferMakeDataReady' { u64(unsafe { voidptr(cm_sample_make_ready) }) }
		'_CMSampleBufferInvalidate' { u64(unsafe { voidptr(cm_sample_invalidate) }) }
		else { none }
	}
}
