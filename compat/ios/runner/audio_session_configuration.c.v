// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Desired configuration of an inactive output session. Activation, recording,
// route changes and signal processing require an audio-session provider.
// Validate borrowed mutable arguments together before using canonical constants.
fn audio_session_configuration(category u64, mode u64, options u64) (string, u64, i64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	category_text := cf_string_compare_text(category) or { return '', 0, -50 }
	mode_text := cf_string_compare_text(mode) or { return '', 0, -50 }
	if options & ~u64(0xff) != 0 { return '', 0, -50 }
	if category_text !in ['AVAudioSessionCategoryAmbient', 'AVAudioSessionCategorySoloAmbient',
		'AVAudioSessionCategoryPlayback', 'AVAudioSessionCategoryRecord',
		'AVAudioSessionCategoryPlayAndRecord', 'AVAudioSessionCategoryMultiRoute',
		'AVAudioSessionCategoryAudioProcessing'] { return '', 0, -50 }
	if mode_text != 'AVAudioSessionModeDefault' {
		valid := match mode_text {
			'AVAudioSessionModeVoiceChat', 'AVAudioSessionModeGameChat', 'AVAudioSessionModeVideoChat' {
				category_text == 'AVAudioSessionCategoryPlayAndRecord'
			}
			'AVAudioSessionModeVideoRecording' {
				category_text in ['AVAudioSessionCategoryRecord', 'AVAudioSessionCategoryPlayAndRecord']
			}
			'AVAudioSessionModeMeasurement' {
				category_text in ['AVAudioSessionCategoryRecord', 'AVAudioSessionCategoryPlayAndRecord', 'AVAudioSessionCategoryPlayback']
			}
			'AVAudioSessionModeMoviePlayback', 'AVAudioSessionModeSpokenAudio', 'AVAudioSessionModeVoicePrompt' {
				category_text == 'AVAudioSessionCategoryPlayback'
			}
			else { false }
		}
		return '', 0, if valid { i64(561145203) } else { i64(-50) }
	}
	match category_text {
		'AVAudioSessionCategorySoloAmbient' {
			if options != 0 { return '', 0, -50 }
			return 'AVAudioSessionCategorySoloAmbient', 0, 0
		}
		'AVAudioSessionCategoryAmbient' {
			if options & ~u64(2) != 0 { return '', 0, -50 }
			return 'AVAudioSessionCategoryAmbient', options | 1, 0
		}
		'AVAudioSessionCategoryPlayback' {
			if options & ~u64(0x13) != 0 || (options & 0x10 != 0 && options & 1 == 0) {
				return '', 0, -50
			}
			return 'AVAudioSessionCategoryPlayback', if options & 2 != 0 { options | 1 } else { options }, 0
		}
		else { return '', 0, 561145203 } // !res: no input/multi-route/processing provider.
	}
}

fn audio_session_category_value(category string) u64 {
	cell := match category {
		'AVAudioSessionCategoryAmbient' { framework_string_constant('_AVAudioSessionCategoryAmbient', 'AVAudioSessionCategoryAmbient') }
		'AVAudioSessionCategoryPlayback' { framework_string_constant('_AVAudioSessionCategoryPlayback', 'AVAudioSessionCategoryPlayback') }
		else { framework_string_constant('_AVAudioSessionCategorySoloAmbient', 'AVAudioSessionCategorySoloAmbient') }
	}
	return read64(cell)
}

fn audio_session_error(output u64, code i64) {
	if output == 0 { return }
	domain := owned_string('NSOSStatusErrorDomain')
	error_object := ns_error_create(domain, code, 0)
	objc_release(domain)
	unsafe { *(&u64(output)) = objc_autorelease(error_object) }
}

fn audio_session_set_configuration(object u64, category u64, mode u64, options u64, output u64) bool {
	canonical, effective_options, code := audio_session_configuration(category, mode, options)
	if code != 0 {
		audio_session_error(output, code)
		return false
	}
	// Initialize cache constants before locking state: NSString initialization
	// may call application code. Cache ownership keeps returned values alive.
	category_value := audio_session_category_value(canonical)
	mode_value := read64(framework_string_constant('_AVAudioSessionModeDefault', 'AVAudioSessionModeDefault'))
	C.ios_objc_initialize_lock()
	store_field(object, 0, category_value)
	store_field(object, 1, mode_value)
	obj_header(object).number = i64(effective_options)
	C.ios_objc_initialize_unlock()
	return true
}

fn audio_session_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if selector == 'setActive:error:' {
		// No hardware audio-session provider is attached. The session stays
		// inactive; deactivation is idempotent, activation reports !res.
		active := u8(frame.x[2]) != 0
		if active { audio_session_error(frame.x[3], 561145203) }
		frame.x[0] = u64(!active)
		return true
	}
	if selector == 'setAllowHapticsAndSystemSoundsDuringRecording:error:' {
		// Desired inactive-session policy only. ObjHeader.valid is unused by
		// AVAudioSession otherwise; no recording or haptics provider is started.
		C.ios_objc_initialize_lock()
		obj_header(object).valid = u8(frame.x[2]) != 0
		C.ios_objc_initialize_unlock()
		frame.x[0] = 1 // Success leaves the caller's NSError ** untouched.
		return true
	}
	if selector == 'allowHapticsAndSystemSoundsDuringRecording' {
		C.ios_objc_initialize_lock()
		frame.x[0] = u64(obj_header(object).valid)
		C.ios_objc_initialize_unlock()
		return true
	}
	if selector == 'setCategory:mode:options:error:' {
		frame.x[0] = u64(audio_session_set_configuration(object, frame.x[2], frame.x[3], frame.x[4], frame.x[5]))
		return true
	}
	if selector !in ['category', 'mode', 'categoryOptions', 'isOtherAudioPlaying'] { return false }
	C.ios_objc_initialize_lock()
	header := obj_header(object)
	value := if selector == 'category' { header.fields[0] } else { header.fields[1] }
	options := header.number
	C.ios_objc_initialize_unlock()
	match selector {
		'category' { frame.x[0] = if value != 0 { value } else { audio_session_category_value('AVAudioSessionCategorySoloAmbient') } }
		'mode' { frame.x[0] = if value != 0 { value } else { read64(framework_string_constant('_AVAudioSessionModeDefault', 'AVAudioSessionModeDefault')) } }
		'categoryOptions' { frame.x[0] = u64(options) }
		else { frame.x[0] = 0 } // No cross-application activity provider is attached.
	}
	return true
}
