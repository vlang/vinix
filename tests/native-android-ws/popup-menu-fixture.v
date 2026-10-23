// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone signed guest proof. Final PASS requires a real guest pointer click.
module main

import os
import crypto.sha256

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	if os.args.len != 2 { panic('OUTPUT') }
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.mkdir_all(out + '/res/menu')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Popup fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(out + '/res/values/strings.xml', '<resources><string name="root_title">Root resource</string><string name="parent_title">Parent resource</string><string name="deep_title">Deep resource</string><string name="leaf_title">Leaf resource</string><string name="renamed_title">Renamed resource</string><string name="xml_title">XML resource</string><color name="fixture_icon">#ff123456</color></resources>')!
	os.write_file(out + '/res/menu/popup.xml', '<menu xmlns:android="http://schemas.android.com/apk/res/android"><item android:id="@+id/xml_visible" android:title="@string/xml_title" android:checkable="true" android:checked="true"/><item android:id="@+id/xml_hidden" android:title="XML hidden" android:visible="false"/><item android:id="@+id/xml_disabled" android:title="XML disabled" android:enabled="false"/></menu>')!
	os.write_file(root + '/Main.smali', r'.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 2
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v0, Landroid/widget/Button;
invoke-direct {v0, p0}, Landroid/widget/Button;-><init>(Landroid/content/Context;)V
const-string v1, "Popup fixture anchor"
invoke-virtual {v0, v1}, Landroid/widget/Button;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
new-instance v1, Lorg/vinix/bootstrap/PopupProbe;
invoke-direct {v1, p0, v0}, Lorg/vinix/bootstrap/PopupProbe;-><init>(Landroid/content/Context;Landroid/view/View;)V
invoke-virtual {p0}, Landroid/app/Activity;->invalidateOptionsMenu()V
return-void
.end method
.method public onCreateOptionsMenu(Landroid/view/Menu;)Z
.locals 1
invoke-static {p0, p1}, Lorg/vinix/bootstrap/PopupProbe;->ownerMenu(Landroid/content/Context;Landroid/view/Menu;)V
const/4 v0, 0
return v0
.end method
')!
	os.write_file(root + '/PopupContext.smali', r'.class public Lorg/vinix/bootstrap/PopupContext;
.super Landroid/content/ContextWrapper;
.field public static measuring:Z
.field public static calls:I
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
return-void
.end method
.method public getResources()Landroid/content/res/Resources;
.locals 1
sget-boolean v0, Lorg/vinix/bootstrap/PopupContext;->measuring:Z
if-eqz v0, :resources
sget v0, Lorg/vinix/bootstrap/PopupContext;->calls:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/bootstrap/PopupContext;->calls:I
:resources
invoke-super {p0}, Landroid/content/ContextWrapper;->getResources()Landroid/content/res/Resources;
move-result-object v0
return-object v0
.end method
')!
	os.write_file(root + '/ItemListener.smali', r'.class public Lorg/vinix/bootstrap/ItemListener;
.super Ljava/lang/Object;
.implements Landroid/view/MenuItem$OnMenuItemClickListener;
.field private probe:Lorg/vinix/bootstrap/PopupProbe;
.field private handled:Z
.method public constructor <init>(Lorg/vinix/bootstrap/PopupProbe;Z)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/ItemListener;->probe:Lorg/vinix/bootstrap/PopupProbe;
iput-boolean p2, p0, Lorg/vinix/bootstrap/ItemListener;->handled:Z
return-void
.end method
.method public onMenuItemClick(Landroid/view/MenuItem;)Z
.locals 2
iget-object v0, p0, Lorg/vinix/bootstrap/ItemListener;->probe:Lorg/vinix/bootstrap/PopupProbe;
iget v1, v0, Lorg/vinix/bootstrap/PopupProbe;->itemCalls:I
add-int/lit8 v1, v1, 1
iput v1, v0, Lorg/vinix/bootstrap/PopupProbe;->itemCalls:I
iget-boolean v0, p0, Lorg/vinix/bootstrap/ItemListener;->handled:Z
return v0
.end method
')!
	os.write_file(root + '/PopupProbe.smali', popup_probe())!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	for name in ['classes.dex', 'unsigned.apk', 'probe.apk'] {
		if os.is_file(out + '/' + name) { os.rm(out + '/' + name)! }
	}
	if os.is_dir(out + '/compiled-res') { os.rmdir_all(out + '/compiled-res')! }
	os.mkdir_all(out + '/compiled-res')!
	checked([os.abs_path('build/android-native-ws/aapt2'), 'compile', '--dir', out + '/res', '-o',
		out + '/compiled-res'])
	mut link := [os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest',
		out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk']
	link << os.walk_ext(out + '/compiled-res', '.flat')
	checked(link)
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main',
		'assemble', out + '/smali', '-o', out + '/classes.dex'])
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'),
		'sign', '--ks', os.abs_path('build/android-maps/canvas242-apk/fixture.p12'), '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('POPUP-MENU-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}

fn popup_probe() string {
	return r'.class public Lorg/vinix/bootstrap/PopupProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.implements Landroid/widget/PopupMenu$OnMenuItemClickListener;
.implements Landroid/widget/PopupMenu$OnDismissListener;
.field public itemCalls:I
.field private popupCalls:I
.field private dismisses:I
.field private stage:I
.field private guest:Z
.field private popup:Landroid/widget/PopupMenu;
.field private context:Landroid/content/Context;
.field private presentation:Landroid/app/Dialog;

.method private static require(ZLjava/lang/String;)V
.locals 1
if-nez p0, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void
.end method
.method private static equal(IILjava/lang/String;)V
.locals 1
const/4 v0, 0
if-ne p0, p1, :check
const/4 v0, 1
:check
invoke-static {v0, p2}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
return-void
.end method
.method private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
.locals 1
const/4 v0, 0
if-ne p0, p1, :check
const/4 v0, 1
:check
invoke-static {v0, p2}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
return-void
.end method
.method private static log(Ljava/lang/String;)V
.locals 1
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v0, p0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
.method private static title(Landroid/view/MenuItem;Ljava/lang/String;)V
.locals 2
invoke-interface {p0}, Landroid/view/MenuItem;->getTitle()Ljava/lang/CharSequence;
move-result-object v0
invoke-virtual {p1, v0}, Ljava/lang/String;->contentEquals(Ljava/lang/CharSequence;)Z
move-result v0
const-string v1, "Activity options owner fallback resource title"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
return-void
.end method
.method private static icon(Landroid/view/MenuItem;)V
.locals 3
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
const-string v1, "icon"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
instance-of v1, v0, Landroid/graphics/drawable/ColorDrawable;
const-string v2, "native menu resource icon storage"
invoke-static {v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
check-cast v0, Landroid/graphics/drawable/ColorDrawable;
invoke-virtual {v0}, Landroid/graphics/drawable/ColorDrawable;->getColor()I
move-result v0
const v1, 0xff123456
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
return-void
.end method
.method public static ownerMenu(Landroid/content/Context;Landroid/view/Menu;)V
.locals 8
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "root_title"
const-string v2, "string"
const-string v3, "org.vinix.bootstrap"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v4
invoke-interface {p1, v4}, Landroid/view/Menu;->add(I)Landroid/view/MenuItem;
move-result-object v5
const-string v6, "Root resource"
invoke-static {v5, v6}, Lorg/vinix/bootstrap/PopupProbe;->title(Landroid/view/MenuItem;Ljava/lang/String;)V
const/4 v1, 0
const/16 v2, 800
const/4 v3, 0
invoke-interface {p1, v1, v2, v3, v4}, Landroid/view/Menu;->addSubMenu(IIII)Landroid/view/SubMenu;
move-result-object v6
invoke-interface {v6}, Landroid/view/SubMenu;->getItem()Landroid/view/MenuItem;
move-result-object v7
const-string v1, "Root resource"
invoke-static {v7, v1}, Lorg/vinix/bootstrap/PopupProbe;->title(Landroid/view/MenuItem;Ljava/lang/String;)V
invoke-interface {v6, v4}, Landroid/view/Menu;->add(I)Landroid/view/MenuItem;
move-result-object v5
const-string v1, "renamed_title"
const-string v2, "string"
const-string v3, "org.vinix.bootstrap"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v4
invoke-interface {v5, v4}, Landroid/view/MenuItem;->setTitle(I)Landroid/view/MenuItem;
const-string v1, "Renamed resource"
invoke-static {v5, v1}, Lorg/vinix/bootstrap/PopupProbe;->title(Landroid/view/MenuItem;Ljava/lang/String;)V
const-string v1, "fixture_icon"
const-string v2, "color"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v4
invoke-interface {v5, v4}, Landroid/view/MenuItem;->setIcon(I)Landroid/view/MenuItem;
invoke-static {v5}, Lorg/vinix/bootstrap/PopupProbe;->icon(Landroid/view/MenuItem;)V
const-string v0, "POPUP-MENU-ACTIVITY-OWNER-PASS"
invoke-static {v0}, Lorg/vinix/bootstrap/PopupProbe;->log(Ljava/lang/String;)V
return-void
.end method
.method private id(Ljava/lang/String;Ljava/lang/String;)I
.locals 2
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->context:Landroid/content/Context;
invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "org.vinix.bootstrap"
invoke-virtual {v0, p1, p2, v1}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
if-eqz v0, :bad
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method private static find(Landroid/view/View;Ljava/lang/String;)Landroid/view/View;
.locals 4
instance-of v0, p0, Landroid/widget/Button;
if-eqz v0, :group
move-object v0, p0
check-cast v0, Landroid/widget/Button;
invoke-virtual {v0}, Landroid/widget/Button;->getText()Ljava/lang/CharSequence;
move-result-object v0
invoke-virtual {p1, v0}, Ljava/lang/String;->contentEquals(Ljava/lang/CharSequence;)Z
move-result v0
if-eqz v0, :group
return-object p0
:group
instance-of v0, p0, Landroid/view/ViewGroup;
if-eqz v0, :none
check-cast p0, Landroid/view/ViewGroup;
invoke-virtual {p0}, Landroid/view/ViewGroup;->getChildCount()I
move-result v1
const/4 v2, 0
:next
if-ge v2, v1, :none
invoke-virtual {p0, v2}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v3
invoke-static {v3, p1}, Lorg/vinix/bootstrap/PopupProbe;->find(Landroid/view/View;Ljava/lang/String;)Landroid/view/View;
move-result-object v3
if-nez v3, :found
add-int/lit8 v2, v2, 1
goto :next
:found
return-object v3
:none
const/4 v0, 0
return-object v0
.end method
.method private button(Ljava/lang/String;)Landroid/view/View;
.locals 2
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v0
invoke-virtual {v0}, Landroid/app/Dialog;->getWindow()Landroid/view/Window;
move-result-object v0
invoke-virtual {v0}, Landroid/view/Window;->getDecorView()Landroid/view/View;
move-result-object v0
invoke-static {v0, p1}, Lorg/vinix/bootstrap/PopupProbe;->find(Landroid/view/View;Ljava/lang/String;)Landroid/view/View;
move-result-object v0
if-nez v0, :ok
new-instance v1, Ljava/lang/AssertionError;
invoke-direct {v1, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:ok
return-object v0
.end method
.method private click(Ljava/lang/String;)Landroid/view/View;
.locals 1
invoke-direct {p0, p1}, Lorg/vinix/bootstrap/PopupProbe;->button(Ljava/lang/String;)Landroid/view/View;
move-result-object v0
invoke-virtual {v0}, Landroid/view/View;->performClick()Z
return-object v0
.end method
.method private later()V
.locals 3
new-instance v0, Landroid/os/Handler;
invoke-direct {v0}, Landroid/os/Handler;-><init>()V
# Dialog.dismiss posts its callback after 10ms; inspect after that deadline.
const-wide/16 v1, 50
invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
return-void
.end method
.method private measureStart()V
.locals 1
const/4 v0, 0
sput v0, Lorg/vinix/bootstrap/PopupContext;->calls:I
const/4 v0, 1
sput-boolean v0, Lorg/vinix/bootstrap/PopupContext;->measuring:Z
return-void
.end method
.method private measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
.locals 2
const/4 v0, 0
sput-boolean v0, Lorg/vinix/bootstrap/PopupContext;->measuring:Z
sget v0, Lorg/vinix/bootstrap/PopupContext;->calls:I
if-lez v0, :bad
invoke-interface {p1}, Landroid/view/MenuItem;->getTitle()Ljava/lang/CharSequence;
move-result-object v0
invoke-virtual {p2, v0}, Ljava/lang/String;->contentEquals(Ljava/lang/CharSequence;)Z
move-result v0
const-string v1, "compiled resource title and constructor Context"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "native resource lookup bypassed constructor Context"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method public constructor <init>(Landroid/content/Context;Landroid/view/View;)V
.locals 10
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Lorg/vinix/bootstrap/PopupContext;
invoke-direct {v0, p1}, Lorg/vinix/bootstrap/PopupContext;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->context:Landroid/content/Context;
# First new API interaction deliberately reproduces old native_init failure.
new-instance v1, Landroid/widget/PopupMenu;
invoke-direct {v1, v0, p2}, Landroid/widget/PopupMenu;-><init>(Landroid/content/Context;Landroid/view/View;)V
iput-object v1, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v1, p0}, Landroid/widget/PopupMenu;->setOnMenuItemClickListener(Landroid/widget/PopupMenu$OnMenuItemClickListener;)V
invoke-virtual {v1, p0}, Landroid/widget/PopupMenu;->setOnDismissListener(Landroid/widget/PopupMenu$OnDismissListener;)V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->getGravity()I
move-result v2
const/4 v3, 0
const-string v4, "default gravity"
invoke-static {v2, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const/16 v2, 0x55
invoke-virtual {v1, v2}, Landroid/widget/PopupMenu;->setGravity(I)V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->getGravity()I
move-result v3
const-string v4, "stored gravity"
invoke-static {v2, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->getMenu()Landroid/view/Menu;
move-result-object v2
invoke-virtual {v1}, Landroid/widget/PopupMenu;->getMenu()Landroid/view/Menu;
move-result-object v3
const-string v4, "stable menu identity"
invoke-static {v2, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v3
const/4 v4, 0
const-string v5, "empty show has no presentation"
invoke-static {v3, v4, v5}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v3, "root_title"
const-string v4, "string"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->measureStart()V
const/4 v3, 0
const/16 v4, 10
const/4 v5, 0
invoke-interface {v2, v3, v4, v5, v7}, Landroid/view/Menu;->add(IIII)Landroid/view/MenuItem;
move-result-object v6
const-string v7, "Root resource"
invoke-direct {p0, v6, v7}, Lorg/vinix/bootstrap/PopupProbe;->measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
const-string v3, "parent_title"
const-string v4, "string"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->measureStart()V
const/4 v3, 0
const/16 v4, 20
const/4 v5, 0
invoke-interface {v2, v3, v4, v5, v7}, Landroid/view/Menu;->addSubMenu(IIII)Landroid/view/SubMenu;
move-result-object v8
invoke-interface {v8}, Landroid/view/SubMenu;->getItem()Landroid/view/MenuItem;
move-result-object v6
const-string v7, "Parent resource"
invoke-direct {p0, v6, v7}, Lorg/vinix/bootstrap/PopupProbe;->measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
const-string v3, "deep_title"
const-string v4, "string"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->measureStart()V
const/4 v3, 0
const/16 v4, 30
const/4 v5, 0
invoke-interface {v8, v3, v4, v5, v7}, Landroid/view/Menu;->addSubMenu(IIII)Landroid/view/SubMenu;
move-result-object v9
invoke-interface {v9}, Landroid/view/SubMenu;->getItem()Landroid/view/MenuItem;
move-result-object v6
const-string v7, "Deep resource"
invoke-direct {p0, v6, v7}, Lorg/vinix/bootstrap/PopupProbe;->measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
const-string v3, "leaf_title"
const-string v4, "string"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->measureStart()V
const/4 v3, 0
const/16 v4, 40
const/4 v5, 0
invoke-interface {v9, v3, v4, v5, v7}, Landroid/view/Menu;->add(IIII)Landroid/view/MenuItem;
move-result-object v6
const-string v7, "Leaf resource"
invoke-direct {p0, v6, v7}, Lorg/vinix/bootstrap/PopupProbe;->measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
const-string v3, "renamed_title"
const-string v4, "string"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->measureStart()V
invoke-interface {v6, v7}, Landroid/view/MenuItem;->setTitle(I)Landroid/view/MenuItem;
const-string v7, "Renamed resource"
invoke-direct {p0, v6, v7}, Lorg/vinix/bootstrap/PopupProbe;->measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
const-string v3, "fixture_icon"
const-string v4, "color"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->measureStart()V
invoke-interface {v6, v7}, Landroid/view/MenuItem;->setIcon(I)Landroid/view/MenuItem;
const-string v7, "Renamed resource"
invoke-direct {p0, v6, v7}, Lorg/vinix/bootstrap/PopupProbe;->measureEnd(Landroid/view/MenuItem;Ljava/lang/String;)V
invoke-static {v6}, Lorg/vinix/bootstrap/PopupProbe;->icon(Landroid/view/MenuItem;)V
const-string v3, "popup"
const-string v4, "menu"
invoke-direct {p0, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->id(Ljava/lang/String;Ljava/lang/String;)I
move-result v3
invoke-virtual {v1, v3}, Landroid/widget/PopupMenu;->inflate(I)V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v8
invoke-virtual {v1}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v9
const-string v7, "repeated show reuses presentation"
invoke-static {v8, v9, v7}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v7, "XML resource"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->button(Ljava/lang/String;)Landroid/view/View;
move-result-object v6
invoke-virtual {v6}, Landroid/view/View;->isSelected()Z
move-result v3
const-string v7, "checked XML item selected"
invoke-static {v3, v7}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
const-string v7, "XML disabled"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->button(Ljava/lang/String;)Landroid/view/View;
move-result-object v6
invoke-virtual {v6}, Landroid/view/View;->isEnabled()Z
move-result v3
xor-int/lit8 v3, v3, 1
const-string v7, "disabled XML button"
invoke-static {v3, v7}, Lorg/vinix/bootstrap/PopupProbe;->require(ZLjava/lang/String;)V
invoke-virtual {v6}, Landroid/view/View;->performClick()Z
iget v3, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/4 v4, 0
const-string v7, "disabled click ignored"
invoke-static {v3, v4, v7}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
invoke-virtual {v8}, Landroid/app/Dialog;->getWindow()Landroid/view/Window;
move-result-object v3
invoke-virtual {v3}, Landroid/view/Window;->getDecorView()Landroid/view/View;
move-result-object v3
const-string v7, "XML hidden"
invoke-static {v3, v7}, Lorg/vinix/bootstrap/PopupProbe;->find(Landroid/view/View;Ljava/lang/String;)Landroid/view/View;
move-result-object v3
const/4 v4, 0
const-string v7, "hidden item has no button"
invoke-static {v3, v4, v7}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v7, "Parent resource"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->click(Ljava/lang/String;)Landroid/view/View;
const-string v7, "Deep resource"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->click(Ljava/lang/String;)Landroid/view/View;
const-string v7, "Renamed resource"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->button(Ljava/lang/String;)Landroid/view/View;
const-string v7, "Back"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->click(Ljava/lang/String;)Landroid/view/View;
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->click(Ljava/lang/String;)Landroid/view/View;
const-string v7, "Root resource"
invoke-direct {p0, v7}, Lorg/vinix/bootstrap/PopupProbe;->button(Ljava/lang/String;)Landroid/view/View;
move-result-object v6
iget v3, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/4 v4, 2
const-string v7, "two submenu callbacks, Back has none"
invoke-static {v3, v4, v7}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->dismiss()V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->dismiss()V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {v1}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v9
iput-object v9, p0, Lorg/vinix/bootstrap/PopupProbe;->presentation:Landroid/app/Dialog;
invoke-virtual {v6}, Landroid/view/View;->performClick()Z
iget v3, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/4 v4, 2
const-string v7, "old presentation button ignored"
invoke-static {v3, v4, v7}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const/4 v3, 1
iput v3, p0, Lorg/vinix/bootstrap/PopupProbe;->stage:I
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->later()V
return-void
.end method
.method public onMenuItemClick(Landroid/view/MenuItem;)Z
.locals 3
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
invoke-interface {p1}, Landroid/view/MenuItem;->getItemId()I
move-result v0
const/16 v1, 103
if-ne v0, v1, :guest
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->dismiss()V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v0
iput-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->presentation:Landroid/app/Dialog;
goto :done
:guest
const/16 v1, 900
if-ne v0, v1, :done
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/PopupProbe;->guest:Z
const-string v0, "POPUP-MENU-GUEST-ITEM-CLICK"
invoke-static {v0}, Lorg/vinix/bootstrap/PopupProbe;->log(Ljava/lang/String;)V
:done
const/4 v0, 1
return v0
.end method
.method public onDismiss(Landroid/widget/PopupMenu;)V
.locals 3
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
const-string v1, "dismiss listener receives popup identity"
invoke-static {p1, v0, v1}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->dismisses:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/PopupProbe;->dismisses:I
iget-boolean v1, p0, Lorg/vinix/bootstrap/PopupProbe;->guest:Z
if-eqz v1, :done
const/16 v1, 8
const-string v2, "real guest leaf dismiss exactly once"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
invoke-virtual {p1}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v0
const/4 v1, 0
const-string v2, "real guest leaf cleared presentation"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "POPUP-MENU-PASS resources submenus listeners hidden disabled repeated reentrant stale guest-click"
invoke-static {v0}, Lorg/vinix/bootstrap/PopupProbe;->log(Ljava/lang/String;)V
:done
return-void
.end method
.method private listenerCase(ILjava/lang/String;I)V
.locals 7
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->getMenu()Landroid/view/Menu;
move-result-object v1
invoke-interface {v1}, Landroid/view/Menu;->clear()V
const/4 v2, 0
const/4 v3, 0
invoke-interface {v1, v2, p1, v3, p2}, Landroid/view/Menu;->add(IIILjava/lang/CharSequence;)Landroid/view/MenuItem;
move-result-object v1
if-ltz p3, :show
new-instance v2, Lorg/vinix/bootstrap/ItemListener;
invoke-direct {v2, p0, p3}, Lorg/vinix/bootstrap/ItemListener;-><init>(Lorg/vinix/bootstrap/PopupProbe;Z)V
invoke-interface {v1, v2}, Landroid/view/MenuItem;->setOnMenuItemClickListener(Landroid/view/MenuItem$OnMenuItemClickListener;)Landroid/view/MenuItem;
:show
invoke-virtual {v0}, Landroid/widget/PopupMenu;->show()V
invoke-direct {p0, p2}, Lorg/vinix/bootstrap/PopupProbe;->click(Ljava/lang/String;)Landroid/view/View;
move-result-object v6
const/16 v1, 103
if-eq p1, v1, :reentrant
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v1
const/4 v2, 0
const-string v3, "leaf dismissed after listener"
invoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void
:reentrant
invoke-virtual {v6}, Landroid/view/View;->performClick()Z
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v1
iget-object v2, p0, Lorg/vinix/bootstrap/PopupProbe;->presentation:Landroid/app/Dialog;
const-string v3, "reentrant replacement survives old leaf and stale click"
invoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void
.end method
.method public run()V
.locals 8
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->stage:I
const/4 v1, 1
if-ne v0, v1, :second
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->dismisses:I
const-string v2, "double dismiss notifies once"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v2
iget-object v3, p0, Lorg/vinix/bootstrap/PopupProbe;->presentation:Landroid/app/Dialog;
const-string v4, "old delayed dismissal preserves reopened presentation"
invoke-static {v2, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->dismiss()V
const/4 v0, 0
iput v0, p0, Lorg/vinix/bootstrap/PopupProbe;->itemCalls:I
iput v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/16 v0, 100
const-string v1, "Item handles"
const/4 v2, 1
invoke-direct {p0, v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->listenerCase(ILjava/lang/String;I)V
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/4 v1, 0
const-string v2, "true item listener precedes popup listener"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const/16 v0, 101
const-string v1, "Item falls back"
const/4 v2, 0
invoke-direct {p0, v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->listenerCase(ILjava/lang/String;I)V
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/4 v1, 1
const-string v2, "false item listener falls back"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const/16 v0, 102
const-string v1, "No item listener"
const/4 v2, -1
invoke-direct {p0, v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->listenerCase(ILjava/lang/String;I)V
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->itemCalls:I
const/4 v1, 2
const-string v2, "exactly two item listener calls"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const-string v2, "null item listener falls back"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const/16 v0, 103
const-string v1, "Reentrant leaf"
const/4 v2, -1
invoke-direct {p0, v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->listenerCase(ILjava/lang/String;I)V
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popupCalls:I
const/4 v1, 3
const-string v2, "stale reentrant button has no callback"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const/4 v0, 2
iput v0, p0, Lorg/vinix/bootstrap/PopupProbe;->stage:I
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->later()V
return-void
:second
const/4 v1, 2
if-ne v0, v1, :third
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->dismisses:I
const/4 v1, 6
const-string v2, "six old presentations notified once each"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
iget-object v0, p0, Lorg/vinix/bootstrap/PopupProbe;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v2
iget-object v3, p0, Lorg/vinix/bootstrap/PopupProbe;->presentation:Landroid/app/Dialog;
const-string v4, "reentrant replacement survives delayed callback"
invoke-static {v2, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->dismiss()V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->dismiss()V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->getMenu()Landroid/view/Menu;
move-result-object v1
invoke-interface {v1}, Landroid/view/Menu;->clear()V
const-string v2, "Only hidden"
invoke-interface {v1, v2}, Landroid/view/Menu;->add(Ljava/lang/CharSequence;)Landroid/view/MenuItem;
move-result-object v2
const/4 v3, 0
invoke-interface {v2, v3}, Landroid/view/MenuItem;->setVisible(Z)Landroid/view/MenuItem;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {v0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v2
const/4 v3, 0
const-string v4, "all-hidden menu creates no presentation"
invoke-static {v2, v3, v4}, Lorg/vinix/bootstrap/PopupProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v1}, Landroid/view/Menu;->clear()V
const/4 v2, 0
const/16 v3, 900
const/4 v4, 0
const-string v5, "Guest click leaf"
invoke-interface {v1, v2, v3, v4, v5}, Landroid/view/Menu;->add(IIILjava/lang/CharSequence;)Landroid/view/MenuItem;
invoke-virtual {v0}, Landroid/widget/PopupMenu;->show()V
const/4 v0, 3
iput v0, p0, Lorg/vinix/bootstrap/PopupProbe;->stage:I
invoke-direct {p0}, Lorg/vinix/bootstrap/PopupProbe;->later()V
return-void
:third
iget v0, p0, Lorg/vinix/bootstrap/PopupProbe;->dismisses:I
const/4 v1, 7
const-string v2, "final pending dismissal, empty show has no callback"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/PopupProbe;->equal(IILjava/lang/String;)V
const-string v0, "POPUP-MENU-PROGRAMMATIC-PASS"
invoke-static {v0}, Lorg/vinix/bootstrap/PopupProbe;->log(Ljava/lang/String;)V
const-string v0, "POPUP-MENU-GUEST-CLICK-READY"
invoke-static {v0}, Lorg/vinix/bootstrap/PopupProbe;->log(Ljava/lang/String;)V
return-void
.end method
'
}
