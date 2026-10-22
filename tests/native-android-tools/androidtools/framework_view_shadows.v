// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep each requested elevation-shadow color, including its alpha channel.
// Native WS uses a software Canvas; RenderNode elevation shadows are absent.
fn framework_view_shadow_colors(smali string) ! {
	path := smali + '/android/view/View.smali'
	mut text := os.read_file(path)!
	constructor := '<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
	start := text.index(' ' + constructor + '\n') or { return error('missing View constructor') }
	end := start + (text[start..].index('.end method') or { return error('unterminated View constructor') })
	init := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V'
	assert text[start..end].count(init) == 1
	mut defaults := '\nconst/high16 v0, -0x1000000\n'
	for kind in ['Ambient', 'Spot'] {
		name := 'vinixOutline${kind}ShadowColor'
		text += '\n.field private ${name}:I\n'
		defaults += 'iput v0, p0, Landroid/view/View;->${name}:I\n'
		text = framework_replace_method(text, 'getOutline${kind}ShadowColor()I',
			touch_method('public getOutline${kind}ShadowColor()I', 'iget v0, p0, Landroid/view/View;->${name}:I\nreturn v0'))!
		text = framework_replace_method(text, 'setOutline${kind}ShadowColor(I)V',
			touch_method('public setOutline${kind}ShadowColor(I)V', '
iget v0, p0, Landroid/view/View;->${name}:I
if-eq v0, p1, :done
iput p1, p0, Landroid/view/View;->${name}:I
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void'))!
	}
	// All public constructors delegate to this one. Initialize before any
	// subclass can query the colors during inflation or native view setup.
	text = text[..start] + text[start..end].replace(init, init + defaults) + text[end..]
	os.write_file(path, text)!
}
