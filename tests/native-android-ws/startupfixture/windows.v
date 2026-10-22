// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_window_probe(dir string) ! {
	os.write_file(dir + '/WindowProbe.smali', '.class public Lorg/vinix/bootstrap/WindowProbe;\n.super Ljava/lang/Object;\n' +
		method('public static check(Landroid/content/Context;)V', '
const/4 v2, 0
new-instance v0, Landroid/view/ContextThemeWrapper;
const v1, 0x1030128
invoke-direct {v0, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v1, Landroid/view/Window;
invoke-direct {v1, v0, v2}, Landroid/view/Window;-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
invoke-virtual {v1}, Landroid/view/Window;->isFloating()Z
move-result v3
if-nez v3, :bad
new-instance v0, Landroid/view/ContextThemeWrapper;
const v1, 0x103012e
invoke-direct {v0, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v1, Landroid/view/Window;
invoke-direct {v1, v0, v2}, Landroid/view/Window;-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
invoke-virtual {v1}, Landroid/view/Window;->isFloating()Z
move-result v3
if-eqz v3, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-WINDOW-PASS activity-theme dialog-theme"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Window floating theme"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
