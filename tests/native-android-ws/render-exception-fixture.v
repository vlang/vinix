// SPDX-License-Identifier: GPL-2.0-or-later
// Negative guest regression: queue pointer input during onDraw, then throw.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/DrawFailureView.smali', '.class public Lorg/vinix/bootstrap/DrawFailureView;
.super Landroid/view/View;
.field private armed:Z
.method public constructor <init>(Landroid/content/Context;)V
.locals 1
invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/View;->setWillNotDraw(Z)V
return-void
.end method
.method protected onDraw(Landroid/graphics/Canvas;)V
.locals 2
# Present one frame before failing so the desktop can route queued input.
iget-boolean v0, p0, Lorg/vinix/bootstrap/DrawFailureView;->armed:Z
if-nez v0, :fail
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/DrawFailureView;->armed:Z
const v0, 0xff336699
invoke-virtual {p1, v0}, Landroid/graphics/Canvas;->drawColor(I)V
# Host positions the pointer during this pause. The pending movement is
# consumed after this successful frame, leaving button-down first next time.
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "RENDER-EXCEPTION-POSITION-WINDOW"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-wide/16 v0, 4000
invoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
return-void
:fail
# Host queues a pointer during this pause, before the render exception.
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "RENDER-EXCEPTION-DRAW-ENTER"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-wide/16 v0, 4000
invoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "expected queued-input render failure"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
.end method
.method public onTouchEvent(Landroid/view/MotionEvent;)Z
.locals 2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "RENDER-EXCEPTION-UNEXPECTED-TOUCH"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const/4 v0, 1
return v0
.end method
')!
	os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 1
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v0, Lorg/vinix/bootstrap/DrawFailureView;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/DrawFailureView;-><init>(Landroid/content/Context;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.end method
')!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('RENDER-EXCEPTION-APK ' + out + '/probe.apk')
}
