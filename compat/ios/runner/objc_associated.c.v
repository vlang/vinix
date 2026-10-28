// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjAssociation {
	value u64
	policy u64
}

struct ObjAssociations {
mut:
	entries map[u64]ObjAssociation
}

type ObjCopyWithZone = fn (u64, &char, u64) u64

fn objc_association_copy(value u64) u64 {
	return objc_copy_value(value, false)
}

fn objc_copy_value(value u64, with_zone bool) u64 {
	if is_block(value) { return block_copy(value) }
	cls := read64(value)
	if gk_player_family(cls) { return gk_player_copy(value) }
	if turn_participant_family(cls) { return turn_participant_copy(value) }
	if turn_match_family(cls) { panic('iOS: unsupported GKTurnBasedMatch method: copy') }
	if leaderboard_family(cls) { panic('iOS: unsupported GKLeaderboard method: copy') }
	if snapshot_configuration_family(cls) { return snapshot_configuration_copy(value) }
	if match_request_family(cls) { panic('iOS: unsupported GKMatchRequest method: copy') }
	if achievement_family(cls) { panic('iOS: unsupported GKAchievement method: copy') }
	if achievement_description_family(cls) { panic('iOS: unsupported GKAchievementDescription method: copy') }
	app_attest_require_factory(cls)
	capture_discovery_require_factory(cls)
	if capture_audio_family(cls) { panic('iOS: unsupported capture audio output method: copy') }
	if gc_event_controller_family(cls) { panic('iOS: unsupported GCEventViewController method: copy') }
	if text_field_family(cls) { panic('iOS: unsupported UITextField method: copy') }
	if haptic_dynamic_parameter_family(cls) { panic('iOS: unsupported CHHapticDynamicParameter method: copy') }
	if haptic_pattern_family(cls) { panic('iOS: unsupported CHHapticPattern method: copy') }
	if !with_zone {
		copy_imp := native_method(cls, 'copy')
		if copy_imp != 0 {
			return unsafe { ObjInit(voidptr(copy_imp))(value, &char(objc_selector(c'copy'))) }
		}
	}
	zone_imp := native_method(cls, 'copyWithZone:')
	if zone_imp != 0 {
		return unsafe { ObjCopyWithZone(voidptr(zone_imp))(value, &char(objc_selector(c'copyWithZone:')), 0) }
	}
	C.ios_objc_initialize_lock()
	formatter := value in ios_runtime.objects && obj_header(value).date_formatter != unsafe { nil }
	number_formatter := value in ios_runtime.objects && obj_header(value).number_formatter != unsafe { nil }
	calendar := value in ios_runtime.objects && obj_header(value).calendar != unsafe { nil }
	predicate := value in ios_runtime.objects && obj_header(value).predicate != unsafe { nil }
	index_set := value in ios_runtime.objects && obj_header(value).index_set != unsafe { nil }
	character_set := value in ios_runtime.objects && obj_header(value).character_set != unsafe { nil }
	scanner := value in ios_runtime.objects && obj_header(value).scanner != unsafe { nil }
	user_activity := value in ios_runtime.objects && obj_header(value).user_activity != unsafe { nil }
	cache := value in ios_runtime.objects && obj_header(value).cache != unsafe { nil }
	map_table := value in ios_runtime.objects && obj_header(value).map_table != unsafe { nil }
	foundation_lock := value in ios_runtime.objects && obj_header(value).foundation_lock_owned
	telephony := value in ios_runtime.objects && obj_header(value).telephony_owned
	adsupport := value in ios_runtime.objects && obj_header(value).adsupport_owned
	credential := value in ios_runtime.objects && obj_header(value).credential_owned
	bundle_resource := value in ios_runtime.objects && obj_header(value).bundle_resource_owned
	notification_queue := value in ios_runtime.objects && obj_header(value).notification_queue != unsafe { nil }
	un_trigger := value in ios_runtime.objects && obj_header(value).un_trigger_owned
	un_request := value in ios_runtime.objects && obj_header(value).un_request_owned
	un_sound := value in ios_runtime.objects && obj_header(value).un_sound_owned
	un_attachment := value in ios_runtime.objects && obj_header(value).un_attachment_owned
	un_center := value in ios_runtime.objects && obj_header(value).un_center_owned
	un_content := value in ios_runtime.objects && obj_header(value).un_content != unsafe { nil }
	query_item := value in ios_runtime.objects && obj_header(value).url_query_item_owned
	mutable_string := value in ios_runtime.objects && obj_header(value).mutable_string_owned
	C.ios_objc_initialize_unlock()
	if formatter { return ns_date_formatter_copy(value) }
	if number_formatter { return ns_number_formatter_copy(value) }
	if calendar || ns_calendar_name(cls) != '' { return ns_calendar_copy(value) }
	if predicate || ns_predicate_family(cls) { return ns_predicate_copy(value) }
	if index_set || ns_index_set_family(cls) { return ns_index_set_copy(value, false) }
	if character_set || ns_character_set_family(cls) { return ns_character_set_copy(value, false, false) }
	if scanner || ns_scanner_family(cls) { return ns_scanner_copy(value) }
	if user_activity || ns_user_activity_family(cls) { panic('iOS: user activity copying is not implemented') }
	if cache || ns_cache_family(cls) { panic('iOS: cache copying is not implemented') }
	if map_table || ns_map_table_family(cls) { panic('iOS: map table copying is not implemented') }
	if foundation_lock || ns_lock_family(cls) { panic('iOS: NSLock copying, coding and this selector are not implemented') }
	if telephony || telephony_family(cls) { panic('iOS: telephony copying is not implemented') }
	if adsupport || adsupport_family(cls) { panic('iOS: advertising manager copying is not implemented') }
	if credential || ns_credential_family(cls) { return ns_credential_copy(value) }
	if bundle_resource || ns_bundle_resource_family(cls) { panic('iOS: resource request copying is not implemented') }
	if notification_queue || ns_notification_queue_family(cls) { panic('iOS: notification queue copying is not implemented') }
	if un_trigger || un_trigger_family(cls) { return un_trigger_copy(value) }
	if un_request || un_request_family(cls) { return un_request_copy(value) }
	if un_sound || un_sound_family(cls) { return un_sound_copy(value) }
	if un_attachment || un_attachment_family(cls) { return un_attachment_copy(value) }
	if un_center || un_center_family(cls) { panic('iOS: user notification center copying is not implemented') }
	if un_content || un_content_family(cls) { return un_content_copy(value, false) }
	if query_item || ns_url_query_item_family(cls) { return ns_url_query_item_copy(value) }
	if objc_is_kind(value, ios_runtime.names['NSMutableData']) {
		return cf_data_create(0, data_pointer(value), i64(data_length(value)))
	}
	if objc_is_kind(value, ios_runtime.names['NSURLRequest']) { return request_copy(value, false) }
	if objc_is_kind(value, ios_runtime.names['NSURLSession']) { url_session_state(value); return objc_retain(value) }
	if objc_is_kind(value, ios_runtime.names['NSURLSessionConfiguration']) { return url_session_configuration_copy(value) }
	if url_session_task_family(cls) { url_session_task_state(value); return objc_retain(value) }
	if mutable_string { return mutable_string_snapshot(value, false) }
	if objc_is_kind(value, ios_runtime.names['NSSortDescriptor']) { sort_descriptor_state(value); return objc_retain(value) }
	if objc_is_kind(value, ios_runtime.names['NSRegularExpression']) { regular_expression_state(value); return objc_retain(value) }
	if objc_is_kind(value, ios_runtime.names['NSTextCheckingResult']) { regex_result_state(value); return objc_retain(value) }
	if ns_date_formatter_family(cls) { return ns_date_formatter_copy(value) }
	if ns_number_formatter_family(cls) { return ns_number_formatter_copy(value) }
	if objc_is_kind(value, ios_runtime.names['NSTimeZone']) {
		C.ios_objc_initialize_lock()
		ns_timezone_snapshot(value)
		retained := objc_retain(value)
		C.ios_objc_initialize_unlock()
		return retained
	}
	if objc_is_kind(value, ios_runtime.names['NSSet']) { return ns_set_copy(value, false) }
	if objc_is_kind(value, ios_runtime.names['UIAlertAction']) { return alert_copy_action(value) }
	if objc_is_kind(value, ios_runtime.names['NSURLResponse']) {
		if obj_header(value).response == unsafe { nil } { panic('iOS: response is not initialized') }
		return objc_retain(value)
	}
	if objc_is_kind(value, ios_runtime.names['NSValue']) && !objc_is_kind(value, ios_runtime.names['NSNumber']) {
		if !obj_header(value).value_initialized { panic('iOS: value is not initialized') }
		return objc_retain(value)
	}
	for pair in [['NSMutableArray', 'NSArray']!, ['NSMutableDictionary', 'NSDictionary']!]! {
		if !objc_is_kind(value, ios_runtime.names[pair[0]]) { continue }
		source := obj_header(value)
		copy := objc_allocate(ios_runtime.names[pair[1]])
		mut target := obj_header(copy)
		target.cf_raw_values = source.cf_raw_values
		target.cf_raw_keys = source.cf_raw_keys
		for item in source.items { target.items << if source.cf_raw_values { item } else { objc_retain(item) } }
		for key in source.keys { target.keys << if source.cf_raw_keys { key } else { objc_retain(key) } }
		return copy
	}
	for name in ['NSString', 'NSNumber', 'NSData', 'NSArray', 'NSDictionary', 'NSAttributedString', 'NSURL', 'NSLocale']! {
		if objc_is_kind(value, ios_runtime.names[name]) { return objc_retain(value) }
	}
	panic('iOS: associated value does not implement copying')
}

fn objc_set_associated(object u64, key u64, value u64, policy u64) {
	if object == 0 {
		if value != 0 { panic('iOS: objc_setAssociatedObject requires a nonnil object') }
		return
	}
	if policy !in [u64(0), 1, 3, 0x301, 0x303] { panic('iOS: unsupported Objective-C association policy') }
	// Copy/retain may call app code. Acquire the new value before locking the
	// table; retire the old value after unlocking, once readers see the change.
	owned := if value == 0 || policy == 0 { value }
		else if policy & 3 == 3 { objc_association_copy(value) }
		else { objc_retain(value) }
	C.ios_objc_initialize_lock()
	mut old := ObjAssociation{}
	mut retired := unsafe { &ObjAssociations(nil) }
	if mut set := ios_runtime.associations[object] {
		old = set.entries[key]
		if owned == 0 {
			set.entries.delete(key)
			if set.entries.len == 0 { ios_runtime.associations.delete(object); retired = set }
		} else { set.entries[key] = ObjAssociation{owned, policy} }
	} else if owned != 0 {
		if object !in ios_runtime.objects && object !in ios_runtime.classes && object !in ios_runtime.constants && !is_block(object) {
			panic('iOS: associations require a known Objective-C object')
		}
		mut set := &ObjAssociations{}
		set.entries[key] = ObjAssociation{owned, policy}
		ios_runtime.associations[object] = set
	}
	C.ios_objc_initialize_unlock()
	if retired != unsafe { nil } { unsafe { retired.entries.free() }; C.free(retired) }
	if old.policy & 1 != 0 { objc_release(old.value) }
}

fn objc_get_associated(object u64, key u64) u64 {
	C.ios_objc_initialize_lock()
	set := ios_runtime.associations[object] or { C.ios_objc_initialize_unlock(); return 0 }
	entry := set.entries[key]
	// The atomic policies pin the result while it is protected from replacement.
	// The caller's pool owns that temporary reference after the lock is dropped.
	if entry.policy & 0x100 != 0 { objc_retain(entry.value) }
	C.ios_objc_initialize_unlock()
	return if entry.policy & 0x200 != 0 { objc_autorelease(entry.value) } else { entry.value }
}

fn objc_remove_associated(object u64) {
	C.ios_objc_initialize_lock()
	set := ios_runtime.associations[object] or { C.ios_objc_initialize_unlock(); return }
	ios_runtime.associations.delete(object)
	C.ios_objc_initialize_unlock()
	// Detach the entire set first. Dealloc callbacks can read, replace or add
	// associations without using this retired table or holding its lock.
	for _, entry in set.entries { if entry.policy & 1 != 0 { objc_release(entry.value) } }
	unsafe { set.entries.free() }
	C.free(set)
}

fn objc_associations_stop() {
	for ios_runtime.associations.len > 0 {
		for object, _ in ios_runtime.associations { objc_remove_associated(object); break }
	}
}
