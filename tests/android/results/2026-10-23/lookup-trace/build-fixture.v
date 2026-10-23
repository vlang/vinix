// SPDX-License-Identifier: GPL-2.0-or-later
// Signed guest regression for lookup identity/order and opt-in diagnostic work.
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
	os.write_file(root + '/LookupGroup.smali', '.class public Lorg/vinix/bootstrap/LookupGroup;
.super Landroid/widget/FrameLayout;
.field public static resourceCalls:I
.field public static measuring:Z
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
return-void
.end method
.method public getResources()Landroid/content/res/Resources;
.locals 1
sget-boolean v0, Lorg/vinix/bootstrap/LookupGroup;->measuring:Z
if-eqz v0, :resources
sget v0, Lorg/vinix/bootstrap/LookupGroup;->resourceCalls:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/bootstrap/LookupGroup;->resourceCalls:I
:resources
invoke-super {p0}, Landroid/widget/FrameLayout;->getResources()Landroid/content/res/Resources;
move-result-object v0
return-object v0
.end method
')!
	os.write_file(root + '/LookupProbe.smali', '.class public Lorg/vinix/bootstrap/LookupProbe;
.super Ljava/lang/Object;
.method public static same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
.locals 1
const/4 v0, 1
sput-boolean v0, Lorg/vinix/bootstrap/LookupGroup;->measuring:Z
invoke-virtual {p0, p1}, Landroid/view/View;->findViewById(I)Landroid/view/View;
move-result-object v0
const/4 p1, 0
sput-boolean p1, Lorg/vinix/bootstrap/LookupGroup;->measuring:Z
if-eq v0, p2, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p3}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void
.end method
.method public static check(Landroid/content/Context;)Landroid/view/View;
.locals 8
new-instance v0, Lorg/vinix/bootstrap/LookupGroup;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/LookupGroup;-><init>(Landroid/content/Context;)V
const/16 v6, 100
invoke-virtual {v0, v6}, Landroid/view/View;->setId(I)V
new-instance v1, Lorg/vinix/bootstrap/LookupGroup;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/LookupGroup;-><init>(Landroid/content/Context;)V
const/16 v6, 101
invoke-virtual {v1, v6}, Landroid/view/View;->setId(I)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const/16 v6, 200
invoke-virtual {v2, v6}, Landroid/view/View;->setId(I)V
invoke-virtual {v1, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
new-instance v3, Landroid/view/View;
invoke-direct {v3, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v3, v6}, Landroid/view/View;->setId(I)V
invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
new-instance v4, Landroid/view/View;
invoke-direct {v4, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const/16 v6, 100
invoke-virtual {v4, v6}, Landroid/view/View;->setId(I)V
invoke-virtual {v0, v4}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v5, 0
sput v5, Lorg/vinix/bootstrap/LookupGroup;->resourceCalls:I
sget-object v5, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v7, "LOOKUP-TRACE-PROBE-BEGIN"
invoke-virtual {v5, v7}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
move-object v7, v0
const-string v5, "own ID precedes descendant"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
const/16 v6, 101
move-object v7, v1
const-string v5, "direct group identity"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
const/16 v6, 300
invoke-virtual {v4, v6}, Landroid/view/View;->setId(I)V
move-object v7, v4
const-string v5, "direct leaf identity"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
const/16 v6, 200
move-object v7, v2
const-string v5, "first duplicate follows depth first order"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
const/16 v6, 999
const/4 v7, 0
const-string v5, "missing ID returns null"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
new-instance v7, Lorg/vinix/bootstrap/LookupGroup;
invoke-direct {v7, p0}, Lorg/vinix/bootstrap/LookupGroup;-><init>(Landroid/content/Context;)V
const/4 v6, -1
const-string v5, "existing NO_ID self identity"
invoke-static {v7, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
const/16 v6, 200
move-object v7, v3
const-string v5, "removed branch excluded"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const-string v5, "reparented branch follows earlier duplicate"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
move-object v7, v2
const-string v5, "remaining nested identity"
invoke-static {v0, v6, v7, v5}, Lorg/vinix/bootstrap/LookupProbe;->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V
const-string v5, "LookupProbe"
const-string v7, "LOOKUP-WARNING-PRESERVED"
invoke-static {v5, v7}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
const-string v7, "LOOKUP-ERROR-PRESERVED"
invoke-static {v5, v7}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I
const-string v5, "LOOKUP_EXPECT_TRACE"
invoke-static {v5}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
const-string v7, "1"
invoke-virtual {v7, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
sget v6, Lorg/vinix/bootstrap/LookupGroup;->resourceCalls:I
if-eqz v5, :off
if-lez v6, :bad
const-string v7, "LOOKUP-TRACE-RESOURCE-WORK-PRESENT"
goto :passed
:off
if-nez v6, :bad
const-string v7, "LOOKUP-TRACE-RESOURCE-WORK-SKIPPED"
:passed
sget-object v5, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v5, v7}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v7, "LOOKUP-TRACE-PROBE-END"
invoke-virtual {v5, v7}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v7, "LOOKUP-TRACE-PASS"
invoke-virtual {v5, v7}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-object v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "lookup diagnostic resource-work gate"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
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
invoke-static {p0}, Lorg/vinix/bootstrap/LookupProbe;->check(Landroid/content/Context;)Landroid/view/View;
move-result-object v0
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.end method
')!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o',
		dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('LOOKUP-TRACE-APK ' + out + '/probe.apk')
}
