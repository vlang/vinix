// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_content_capture_probe(dir string) ! {
	view := 'Lorg/vinix/bootstrap/ContentCaptureView;'
	session := 'Landroid/view/contentcapture/ContentCaptureSession;'
	os.write_file(dir + '/ContentCaptureView.smali', '.class public ${view}\n.super Landroid/view/View;\n.field public attached:I\n' +
		method('public constructor <init>(Landroid/content/Context;)V',
			'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('protected onAttachedToWindow()V', '
invoke-super {p0}, Landroid/view/View;->onAttachedToWindow()V
invoke-virtual {p0}, Landroid/view/View;->getContentCaptureSession()${session}
move-result-object v0
if-nez v0, :bad
iget v0, p0, ${view}->attached:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${view}->attached:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "content capture session without a capture service"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
	os.write_file(dir + '/ContentCaptureProbe.smali', '.class public Lorg/vinix/bootstrap/ContentCaptureProbe;\n.super Ljava/lang/Object;\n' +
		method('public static check(Landroid/content/Context;)V', '
new-instance v0, Landroid/widget/FrameLayout;
invoke-direct {v0, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v1, ${view}
invoke-direct {v1, p0}, ${view}-><init>(Landroid/content/Context;)V
invoke-virtual {v1}, Landroid/view/View;->getContentCaptureSession()${session}
move-result-object v2
if-nez v2, :bad
new-instance v2, Landroid/os/Binder;
invoke-direct {v2}, Landroid/os/Binder;-><init>()V
invoke-virtual {v0, v2}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
# Match fragment creation: attach a child that queries content capture in onAttach.
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
iget v2, v1, ${view}->attached:I
const/4 v3, 1
if-ne v2, v3, :bad
invoke-virtual {v0}, Landroid/view/View;->getContentCaptureSession()${session}
move-result-object v2
if-nez v2, :bad
invoke-virtual {v1}, Landroid/view/View;->getContentCaptureSession()${session}
move-result-object v2
if-nez v2, :bad
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
invoke-virtual {v1}, Landroid/view/View;->getContentCaptureSession()${session}
move-result-object v2
if-nez v2, :bad
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
iget v2, v1, ${view}->attached:I
const/4 v3, 2
if-ne v2, v3, :bad
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CONTENT-CAPTURE-PASS unavailable detached attach-callback remove reattach"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "unavailable View content capture contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
