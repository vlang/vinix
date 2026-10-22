// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_layout_exception_probe(dir string) ! {
	mut source := '.class public Lorg/vinix/bootstrap/LayoutExceptionProbe;\n.super Landroid/view/View;\n.field private failure:Ljava/lang/RuntimeException;\n.field private mode:I\n'
	source += method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void')
	for index, signature in ['onMeasure(II)V', 'onSizeChanged(IIII)V', 'onLayout(ZIIII)V'] {
		source += method('protected ' + signature, 'iget v0, p0, Lorg/vinix/bootstrap/LayoutExceptionProbe;->mode:I\nconst/4 v1, ${index + 1}\nif-ne v0, v1, :done\niget-object v0, p0, Lorg/vinix/bootstrap/LayoutExceptionProbe;->failure:Ljava/lang/RuntimeException;\nthrow v0\n:done\n' +
			if index == 0 { 'invoke-super {p0, p1, p2}, Landroid/view/View;->onMeasure(II)V\nreturn-void' } else { 'return-void' })
	}
	mut check := ''
	for mode in 1 .. 4 {
		check += '
new-instance v0, Lorg/vinix/bootstrap/LayoutExceptionProbe;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/LayoutExceptionProbe;-><init>(Landroid/content/Context;)V
new-instance v1, Ljava/lang/IllegalStateException;
const-string v2, "expected layout callback failure"
invoke-direct {v1, v2}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
iput-object v1, v0, Lorg/vinix/bootstrap/LayoutExceptionProbe;->failure:Ljava/lang/RuntimeException;
const/4 v2, ${mode}
iput v2, v0, Lorg/vinix/bootstrap/LayoutExceptionProbe;->mode:I
const/4 v2, 0
const/16 v3, 71
const/16 v4, 39
:start${mode}
invoke-virtual {v0, v2, v2, v3, v4}, Landroid/view/View;->layout(IIII)V
:end${mode}
.catch Ljava/lang/RuntimeException; {:start${mode} .. :end${mode}} :caught${mode}
goto :bad
:caught${mode}
move-exception v5
if-ne v1, v5, :bad
# Recover using the same native View after catching the original object.
iput v2, v0, Lorg/vinix/bootstrap/LayoutExceptionProbe;->mode:I
invoke-virtual {v0, v2, v2, v3, v4}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v0}, Landroid/view/View;->getWidth()I
move-result v5
if-ne v3, v5, :bad
invoke-virtual {v0}, Landroid/view/View;->getHeight()I
move-result v5
if-ne v4, v5, :bad
'
	}
	check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-LAYOUT-EXCEPTIONS-PASS measure size layout original-throwable recover"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Layout callback exception identity or recovery"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	source += method('public static check(Landroid/content/Context;)V', check)
	os.write_file(dir + '/LayoutExceptionProbe.smali', source)!
}
