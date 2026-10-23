// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Upstream ATL formats resource names for every ViewGroup visited by a lookup.
// Keep its search untouched, and opt in before doing any diagnostic formatting.
fn framework_lookup_trace(smali string) ! {
	path := smali + '/android/view/ViewGroup.smali'
	mut text := os.read_file(path)!
	start := text.index('.method public findViewById(I)Landroid/view/View;\n') or {
		return error('missing ViewGroup lookup')
	}
	end := start + (text[start..].index('.end method') or {
		return error('unterminated ViewGroup lookup')
	})
	mut method := text[start..end]
	mut cursor := 0
	for index, anchors in [
		['    const-string v0, "View"', '    iget v0, p0, Landroid/view/ViewGroup;->id:I'],
		['    const-string v0, "View"', '    :goto_b8'],
	] {
		first := cursor + (method[cursor..].index(anchors[0]) or {
			return error('missing lookup trace start')
		})
		last := first + (method[first..].index(anchors[1]) or {
			return error('missing lookup trace end')
		})
		block := method[first..last]
		if block.count('Landroid/util/Slog;->v(') != 1 {
			return error('unexpected lookup trace block')
		}
		label := ':vinix_lookup_trace_skip_' + index.str()
		gated := '    sget-boolean v0, Landroid/atl/VinixViewLookupTrace;->enabled:Z\n' +
			'    if-eqz v0, ' + label + '\n' + block + '    ' + label + '\n\n'
		method = method[..first] + gated + method[last..]
		cursor = first + gated.len
	}
	text = text[..start] + method + text[end..]
	os.write_file(path, text)!
	os.write_file(smali + '/android/atl/VinixViewLookupTrace.smali',
		'.class public final Landroid/atl/VinixViewLookupTrace;\n.super Ljava/lang/Object;\n' +
			'.field public static final enabled:Z\n' +
			'.method static constructor <clinit>()V\n.locals 2\n' +
			'const-string v0, "VINIX_ANDROID_TRACE_VIEW_LOOKUP"\n' +
			'invoke-static {v0}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\n' +
			'const-string v1, "1"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\n' +
			'sput-boolean v0, Landroid/atl/VinixViewLookupTrace;->enabled:Z\nreturn-void\n.end method\n')!
}
