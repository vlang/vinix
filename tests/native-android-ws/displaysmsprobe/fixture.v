// SPDX-License-Identifier: GPL-2.0-or-later
module displaysmsprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/DisplaySmsProbe.smali', r'.class public Lorg/vinix/bootstrap/DisplaySmsProbe;
.super Landroid/database/ContentObserver;
.field calls:I
.method public constructor <init>()V
.locals 1
const/4 v0, 0
invoke-direct {p0, v0}, Landroid/database/ContentObserver;-><init>(Landroid/os/Handler;)V
return-void
.end method
.method public onChange(Z)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/DisplaySmsProbe;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/DisplaySmsProbe;->calls:I
return-void
.end method
.method public static check(Landroid/content/Context;)V
.locals 8
const-string v0, "display"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/hardware/display/DisplayManager;
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/hardware/display/DisplayManager;->getDisplay(I)Landroid/view/Display;
move-result-object v2
if-eqz v2, :bad
invoke-virtual {v2}, Landroid/view/Display;->getState()I
move-result v3
sget v4, Landroid/view/Display;->STATE_ON:I
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/view/Display;->getDisplayId()I
move-result v3
invoke-static {v3, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v3, -1
invoke-virtual {v0, v3}, Landroid/hardware/display/DisplayManager;->getDisplay(I)Landroid/view/Display;
move-result-object v2
if-nez v2, :bad
const/4 v3, 1
invoke-virtual {v0, v3}, Landroid/hardware/display/DisplayManager;->getDisplay(I)Landroid/view/Display;
move-result-object v2
if-nez v2, :bad
invoke-virtual {v0}, Landroid/hardware/display/DisplayManager;->getDisplays()[Landroid/view/Display;
move-result-object v2
array-length v4, v2
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v4, 0
aput-object v4, v2, v1
invoke-virtual {v0}, Landroid/hardware/display/DisplayManager;->getDisplays()[Landroid/view/Display;
move-result-object v4
if-eq v2, v4, :bad
aget-object v2, v4, v1
invoke-virtual {v2}, Landroid/view/Display;->getState()I
move-result v2
const/4 v4, 2
invoke-static {v2, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "window"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/view/WindowManager;
invoke-interface {v0}, Landroid/view/WindowManager;->getDefaultDisplay()Landroid/view/Display;
move-result-object v0
invoke-virtual {v0}, Landroid/view/Display;->getState()I
move-result v0
invoke-static {v0, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Landroid/provider/Telephony$Sms;->CONTENT_URI:Landroid/net/Uri;
invoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;
move-result-object v1
const-string v2, "content://sms"
invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
invoke-static {v1, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v7, Lorg/vinix/bootstrap/DisplaySmsProbe;
invoke-direct {v7}, Lorg/vinix/bootstrap/DisplaySmsProbe;-><init>()V
invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;
move-result-object v6
invoke-virtual {v6, v0, v3, v7}, Landroid/content/ContentResolver;->registerContentObserver(Landroid/net/Uri;ZLandroid/database/ContentObserver;)V
move-object v1, v0
move-object v0, v6
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-virtual/range {v0 .. v5}, Landroid/content/ContentResolver;->query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;
move-result-object v0
if-nez v0, :bad
invoke-virtual {v6, v7}, Landroid/content/ContentResolver;->unregisterContentObserver(Landroid/database/ContentObserver;)V
iget v0, v7, Lorg/vinix/bootstrap/DisplaySmsProbe;->calls:I
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "DISPLAY-SMS-PASS active-default-display isolated-catalog sms-uri absent-provider no-fabricated-change"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
')!
}
