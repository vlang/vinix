// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Metadata descriptors only. No player, asset or output storage is implemented.
fn av_player_name(name string) bool {
	return name in ['AVAsset', 'AVURLAsset', 'AVPlayer', 'AVPlayerItem', 'AVPlayerItemOutput',
		'AVPlayerItemLegibleOutput', 'AVPlayerItemVideoOutput']!
}

fn av_player_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if av_player_name(info.name) { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic AVFoundation playback superclass chain')
}

fn av_player_unsupported(selector string) bool {
	return selector !in ['class', 'superclass', 'self', 'isKindOfClass:',
		'respondsToSelector:', 'conformsToProtocol:']!
}

fn av_player_require_playback(cls u64) {
	if av_player_family(cls) {
		panic('iOS: AVFoundation player, asset and output construction or playback is not implemented')
	}
}

fn av_player_symbol(symbol string) ?u64 {
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
		if !symbol.starts_with(prefix) { continue }
		name := symbol[prefix.len..]
		if !av_player_name(name) { return none }
		cls := ios_runtime.names[name] or { return none }
		return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
	}
	return none
}
