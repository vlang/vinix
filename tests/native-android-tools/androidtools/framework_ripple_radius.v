// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Preserve the requested radius for callers that read it through a subclass.
// Ripple drawing still uses the renderer's existing LayerDrawable fallback.
fn framework_ripple_radius(smali string) ! {
	path := smali + '/android/graphics/drawable/RippleDrawable.smali'
	owner := 'Landroid/graphics/drawable/RippleDrawable;'
	mut text := os.read_file(path)!
	if text.contains(' getRadius()I') || text.contains(' RADIUS_AUTO:I') {
		return error('RippleDrawable radius API already present')
	}
	text += '\n.field public static final RADIUS_AUTO:I = -0x1\n.field private vinixRippleRadius:I\n'
	init := 'const/4 v0, -0x1\niput v0, p0, ${owner}->vinixRippleRadius:I\n'
	text = framework_replace_method(text, '<init>()V', '.method constructor <init>()V\n.locals 1\n' +
		'invoke-direct {p0}, Landroid/graphics/drawable/LayerDrawable;-><init>()V\n' + init + 'return-void\n.end method')!
	signature := ' <init>(Landroid/content/res/ColorStateList;Landroid/graphics/drawable/Drawable;Landroid/graphics/drawable/Drawable;)V\n'
	start := text.index(signature) or { return error('missing RippleDrawable public constructor') }
	end := start + (text[start..].index('.end method') or { return error('unterminated RippleDrawable constructor') })
	body := text[start..end]
	if body.count('return-void') != 1 || !body.contains('.registers 6') {
		return error('unexpected RippleDrawable constructor registers or returns')
	}
	text = text[..start] + body.replace('return-void', init + 'return-void') + text[end..]
	text = framework_replace_method(text, 'setRadius(I)V', '.method public setRadius(I)V\n.locals 0\n' +
		'iput p1, p0, ${owner}->vinixRippleRadius:I\n' +
		'invoke-virtual {p0}, Landroid/graphics/drawable/Drawable;->invalidateSelf()V\nreturn-void\n.end method')!
	text += '\n.method public getRadius()I\n.locals 1\n' +
		'iget v0, p0, ${owner}->vinixRippleRadius:I\nreturn v0\n.end method\n'
	os.write_file(path, text)!
}
