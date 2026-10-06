// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_japanese_and_english_repeated_plural_results_release_all_storage() {
	defer { set_desktop_language(.en) }
	for language in [DesktopLanguage.ja, .en]! {
		set_desktop_language(language)
		warm := tr_count('capture.status.frames', 1)
		assert warm == if language == .ja { '1フレーム' } else { '1 frame' }
		unsafe { warm.free() }
		for key in ['capture.status.frames', 'battery.remaining.about_hours',
			'system_information.search.count', 'calendar.search.count']! {
			C.vinix_heap_begin()
			for count in 0 .. 200 {
				text := tr_count(key, i64(count))
				assert text.len > 0
				unsafe { text.free() }
			}
			assert C.vinix_heap_end() == 0
		}
	}
}

fn test_japanese_and_english_repeated_file_dates_release_all_storage() {
	defer { set_desktop_language(.en) }
	for language in [DesktopLanguage.ja, .en]! {
		set_desktop_language(language)
		warm := files_list_modified_text(0, 0)
		assert warm == if language == .ja { '1970年1月01日 00:00' } else { '01 Jan 1970 00:00' }
		unsafe { warm.free() }
		C.vinix_heap_begin()
		for day in 0 .. 200 {
			text := files_list_modified_text(i64(day) * 86400, 0)
			assert text.len > 0
			unsafe { text.free() }
		}
		assert C.vinix_heap_end() == 0
	}
}
