// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// ATL logs every inflated tag, formatting the parent and result and resolving
// the result's resource name. Test the cached opt-in before doing that work.
fn framework_inflater_trace(smali string) ! {
	path := smali + '/android/view/LayoutInflater.smali'
	mut text := os.read_file(path)!
	declaration := '.method createViewFromTag(Landroid/view/View;Ljava/lang/String;Landroid/util/AttributeSet;)Landroid/view/View;\n'
	if text.count(declaration) != 1 { return error('unexpected LayoutInflater tag declaration') }
	start := text.index(declaration) or { return error('missing inflater declaration') }
	end := start + (text[start..].index('.end method') or {
		return error('unterminated LayoutInflater tag method')
	})
	mut method := text[start..end]
	mut cursor := 0
	for index, anchors in [
		['    const-string v0, "LayoutInflater"', '    iget-object v0, p0, Landroid/view/LayoutInflater;->factories:Ljava/util/LinkedList;'],
		['    const-string v1, "LayoutInflater"', '    return-object v0'],
	] {
		first := cursor + (method[cursor..].index(anchors[0]) or {
			return error('missing inflater trace start')
		})
		last := first + (method[first..].index(anchors[1]) or {
			return error('missing inflater trace end')
		})
		block := method[first..last]
		if block.count('Landroid/util/Slog;->v(') != 1 || block.contains('Landroid/util/Slog;->w(')
			|| block.contains('Landroid/util/Slog;->e(') || block.contains('    :') {
			return error('unexpected inflater trace block')
		}
		register := if index == 0 { 'v0' } else { 'v1' }
		label := ':vinix_inflater_trace_skip_' + index.str()
		gated := '    sget-boolean ${register}, Landroid/atl/VinixInflaterTrace;->enabled:Z\n' +
			'    if-eqz ${register}, ${label}\n' + block + '    ${label}\n\n'
		method = method[..first] + gated + method[last..]
		cursor = first + gated.len
	}
	if method.count('Landroid/util/Slog;->v(') != 2 {
		return error('unexpected inflater verbose log count')
	}
	text = text[..start] + method + text[end..]
	os.write_file(path, text)!
	os.write_file(smali + '/android/atl/VinixInflaterTrace.smali',
		'.class public final Landroid/atl/VinixInflaterTrace;\n.super Ljava/lang/Object;\n' +
			'.field public static final enabled:Z\n' +
			'.method static constructor <clinit>()V\n.locals 2\n' +
			'const-string v0, "VINIX_ANDROID_TRACE_INFLATER"\n' +
			'invoke-static {v0}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\n' +
			'const-string v1, "1"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\n' +
			'sput-boolean v0, Landroid/atl/VinixInflaterTrace;->enabled:Z\nreturn-void\n.end method\n')!
}
