// SPDX-License-Identifier: GPL-2.0-or-later
module graphictextprobe

import os

pub fn install(root string) ! {
	mut source := r'.class public Lorg/vinix/bootstrap/GraphicTextProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 4
'
	// Inputs are UTF-16 units so isolated surrogates and supplementary code
	// points have explicit, unambiguous DEX representations.
	for index, units in [ []int{}, [32, 9, 10], [0], [0xa0], [0x2028, 0x2029], [0x200d],
		[0x378], [0xd800], [0xdc00], [0xdbff, 0xdfff], [0xdb40, 0xdc01],
		[65], [0x301], [0xe000], [0xd83d, 0xde00], [0xd800, 65], [32, 0x200d, 65] ] {
		expected := if index < 11 { 0 } else { 1 }
		source += 'const v0, ${units.len}\nnew-array v0, v0, [C\n'
		for position, unit in units {
			source += 'const v1, ${position}\nconst v2, ${unit}\naput-char v2, v0, v1\n'
		}
		source += 'new-instance v1, Ljava/lang/String;\ninvoke-direct {v1, v0}, Ljava/lang/String;-><init>([C)V\nconst/4 v2, ${expected}\ninvoke-static {v1}, Landroid/text/TextUtils;->isGraphic(Ljava/lang/CharSequence;)Z\nmove-result v0\ninvoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
		source += 'new-instance v3, Ljava/lang/StringBuilder;\ninvoke-direct {v3, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/CharSequence;)V\ninvoke-static {v3}, Landroid/text/TextUtils;->isGraphic(Ljava/lang/CharSequence;)Z\nmove-result v0\ninvoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
	}
	for unit, expected in {0: 0, 9: 0, 32: 0, 0xa0: 0, 0x200d: 0, 0x2028: 0, 0x2029: 0,
		0xd800: 0, 0xdc00: 0, 65: 1, 0x301: 1, 0xe000: 1} {
		source += 'const v0, ${unit}\ninvoke-static {v0}, Landroid/text/TextUtils;->isGraphic(C)Z\nmove-result v0\nconst/4 v1, ${expected}\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
	}
	source += r'const/4 v0, 0
:start
invoke-static {v0}, Landroid/text/TextUtils;->isGraphic(Ljava/lang/CharSequence;)Z
:end
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.catch Ljava/lang/NullPointerException; {:start .. :end} :null
:null
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "GRAPHIC-TEXT-PASS unicode-categories supplementary isolated-surrogates mutable-charsequence null-rejection"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
'
	os.write_file(root + '/smali/GraphicTextProbe.smali', source)!
}
