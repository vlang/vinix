// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone guest proof for ActionProvider and the measured PopupMenu fallback.
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
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="ActionProvider fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
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
const-string v1, "ActionProvider fixture"
invoke-virtual {v0, v1}, Landroid/widget/Button;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
invoke-static {p0, v0}, Lorg/vinix/bootstrap/ProviderProbe;->run(Landroid/content/Context;Landroid/view/View;)V
const-string v0, "BOOTSTRAP-ACTION-PROVIDER-PASS"
const-string v1, "defaults virtual factories visibility listeners reset and popup callback order"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
const-string v0, "BOOTSTRAP-READY"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
.end method
')!
	os.write_file(root + '/BaseProvider.smali', r'.class public Lorg/vinix/bootstrap/BaseProvider;
.super Landroid/view/ActionProvider;
.field public view:Landroid/view/View;
.field public creates:I
.method public constructor <init>(Landroid/content/Context;Landroid/view/View;)V
.locals 0
invoke-direct {p0, p1}, Landroid/view/ActionProvider;-><init>(Landroid/content/Context;)V
iput-object p2, p0, Lorg/vinix/bootstrap/BaseProvider;->view:Landroid/view/View;
return-void
.end method
.method public onCreateActionView()Landroid/view/View;
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/BaseProvider;->creates:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/BaseProvider;->creates:I
iget-object v0, p0, Lorg/vinix/bootstrap/BaseProvider;->view:Landroid/view/View;
return-object v0
.end method
')!
	os.write_file(root + '/DynamicProvider.smali', dynamic_provider())!
	os.write_file(root + '/PopupListener.smali', r'.class public Lorg/vinix/bootstrap/PopupListener;
.super Ljava/lang/Object;
.implements Landroid/widget/PopupMenu$OnMenuItemClickListener;
.field public handled:Z
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public onMenuItemClick(Landroid/view/MenuItem;)Z
.locals 1
const/4 v0, 2
invoke-static {v0}, Lorg/vinix/bootstrap/ProviderProbe;->append(I)V
iget-boolean v0, p0, Lorg/vinix/bootstrap/PopupListener;->handled:Z
return v0
.end method
')!
	os.write_file(root + '/ProviderListener.smali', r'.class public Lorg/vinix/bootstrap/ProviderListener;
.super Ljava/lang/Object;
.implements Landroid/view/ActionProvider$VisibilityListener;
.implements Landroid/view/ActionProvider$SubUiVisibilityListener;
.field public calls:I
.field public subCalls:I
.field public last:Z
.field public subLast:Z
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public onActionProviderVisibilityChanged(Z)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/ProviderListener;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ProviderListener;->calls:I
iput-boolean p1, p0, Lorg/vinix/bootstrap/ProviderListener;->last:Z
return-void
.end method
.method public onSubUiVisibilityChanged(Z)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/ProviderListener;->subCalls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ProviderListener;->subCalls:I
iput-boolean p1, p0, Lorg/vinix/bootstrap/ProviderListener;->subLast:Z
return-void
.end method
')!
	os.write_file(root + '/ModernProvider.smali', r'.class public Lorg/vinix/bootstrap/ModernProvider;
.super Lorg/vinix/bootstrap/BaseProvider;
.field public item:Landroid/view/MenuItem;
.method public constructor <init>(Landroid/content/Context;Landroid/view/View;)V
.locals 0
invoke-direct {p0, p1, p2}, Lorg/vinix/bootstrap/BaseProvider;-><init>(Landroid/content/Context;Landroid/view/View;)V
return-void
.end method
.method public onCreateActionView(Landroid/view/MenuItem;)Landroid/view/View;
.locals 1
iput-object p1, p0, Lorg/vinix/bootstrap/ModernProvider;->item:Landroid/view/MenuItem;
iget-object v0, p0, Lorg/vinix/bootstrap/BaseProvider;->view:Landroid/view/View;
return-object v0
.end method
')!
	os.write_file(root + '/ProviderProbe.smali', provider_probe())!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	for name in ['classes.dex', 'unsigned.apk', 'probe.apk'] {
		if os.is_file(out + '/' + name) { os.rm(out + '/' + name)! }
	}
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest',
		out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main',
		'assemble', out + '/smali', '-o', out + '/classes.dex'])
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'),
		'sign', '--ks', os.abs_path('build/android-maps/canvas242-apk/fixture.p12'), '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('ACTION-PROVIDER-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}

fn dynamic_provider() string {
	mut text := r'.class public Lorg/vinix/bootstrap/DynamicProvider;
.super Lorg/vinix/bootstrap/BaseProvider;
.field public overrides:Z
.field public visible:Z
.field public handled:Z
.field public overrideCalls:I
.field public visibleCalls:I
.field public actions:I
.field public resets:I
.method public constructor <init>(Landroid/content/Context;Landroid/view/View;)V
.locals 0
invoke-direct {p0, p1, p2}, Lorg/vinix/bootstrap/BaseProvider;-><init>(Landroid/content/Context;Landroid/view/View;)V
return-void
.end method
'
	for signature, field in {
		'overridesItemVisibility': 'overrideCalls'
		'isVisible':               'visibleCalls'
		'onPerformDefaultAction':  'actions'
	} {
		value := if signature == 'overridesItemVisibility' {
			'overrides'
		} else if signature == 'isVisible' {
			'visible'
		} else {
			'handled'
		}
		text += '.method public ' + signature + '()Z\n.locals 1\niget v0, p0, Lorg/vinix/bootstrap/DynamicProvider;->' + field + ':I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/DynamicProvider;->' + field + ':I\n'
		if signature == 'onPerformDefaultAction' {
			text += 'const/4 v0, 3\ninvoke-static {v0}, Lorg/vinix/bootstrap/ProviderProbe;->append(I)V\n'
		}
		text += 'iget-boolean v0, p0, Lorg/vinix/bootstrap/DynamicProvider;->' + value + ':Z\nreturn v0\n.end method\n'
	}
	return text + r'.method public reset()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/DynamicProvider;->resets:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/DynamicProvider;->resets:I
invoke-super {p0}, Landroid/view/ActionProvider;->reset()V
return-void
.end method
'
}

fn equal(actual string, expected int, label string) string {
	return 'const/16 v8, ' + expected.str() + '\nconst-string v9, "' + label + '"\ninvoke-static {' + actual + ', v8, v9}, Lorg/vinix/bootstrap/ProviderProbe;->equal(IILjava/lang/String;)V\n'
}

fn provider_probe() string {
	mut text := r'.class public Lorg/vinix/bootstrap/ProviderProbe;
.super Ljava/lang/Object;
.implements Landroid/view/MenuItem$OnMenuItemClickListener;
.field public static sequence:I
.field public itemHandled:Z
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static append(I)V
.locals 1
sget v0, Lorg/vinix/bootstrap/ProviderProbe;->sequence:I
mul-int/lit8 v0, v0, 10
add-int/2addr v0, p0
sput v0, Lorg/vinix/bootstrap/ProviderProbe;->sequence:I
return-void
.end method
.method public onMenuItemClick(Landroid/view/MenuItem;)Z
.locals 1
const/4 v0, 1
invoke-static {v0}, Lorg/vinix/bootstrap/ProviderProbe;->append(I)V
iget-boolean v0, p0, Lorg/vinix/bootstrap/ProviderProbe;->itemHandled:Z
return v0
.end method
.method public static equal(IILjava/lang/String;)V
.locals 1
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void
.end method
.method public static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
.locals 1
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void
.end method
.method public static find(Landroid/view/View;)Landroid/widget/Button;
.locals 4
instance-of v0, p0, Landroid/widget/Button;
if-eqz v0, :group
check-cast p0, Landroid/widget/Button;
invoke-virtual {p0}, Landroid/widget/Button;->getText()Ljava/lang/CharSequence;
move-result-object v0
const-string v1, "Provider leaf"
invoke-virtual {v1, v0}, Ljava/lang/String;->contentEquals(Ljava/lang/CharSequence;)Z
move-result v0
if-eqz v0, :none
return-object p0
:group
instance-of v0, p0, Landroid/view/ViewGroup;
if-eqz v0, :none
check-cast p0, Landroid/view/ViewGroup;
const/4 v0, 0
invoke-virtual {p0}, Landroid/view/ViewGroup;->getChildCount()I
move-result v1
:loop
if-ge v0, v1, :none
invoke-virtual {p0, v0}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v2
invoke-static {v2}, Lorg/vinix/bootstrap/ProviderProbe;->find(Landroid/view/View;)Landroid/widget/Button;
move-result-object v3
if-nez v3, :found
add-int/lit8 v0, v0, 1
goto :loop
:found
return-object v3
:none
const/4 v0, 0
return-object v0
.end method
.method public static click(Landroid/widget/PopupMenu;)V
.locals 2
invoke-virtual {p0}, Landroid/widget/PopupMenu;->show()V
invoke-virtual {p0}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v0
invoke-virtual {v0}, Landroid/app/Dialog;->getWindow()Landroid/view/Window;
move-result-object v0
invoke-virtual {v0}, Landroid/view/Window;->getDecorView()Landroid/view/View;
move-result-object v0
invoke-static {v0}, Lorg/vinix/bootstrap/ProviderProbe;->find(Landroid/view/View;)Landroid/widget/Button;
move-result-object v0
if-nez v0, :click
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "real provider popup button missing"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:click
invoke-virtual {v0}, Landroid/view/View;->performClick()Z
return-void
.end method
.method public static run(Landroid/content/Context;Landroid/view/View;)V
.locals 10
new-instance v0, Lorg/vinix/bootstrap/BaseProvider;
invoke-direct {v0, p0, p1}, Lorg/vinix/bootstrap/BaseProvider;-><init>(Landroid/content/Context;Landroid/view/View;)V
'
	for method, value in {
		'overridesItemVisibility': 0
		'isVisible':               1
		'hasSubMenu':              0
		'onPerformDefaultAction':  0
	} {
		text += 'invoke-virtual {v0}, Landroid/view/ActionProvider;->' + method + '()Z\nmove-result v7\n' + equal('v7', value, 'default ' + method)
	}
	text += r'const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/view/ActionProvider;->onPrepareSubMenu(Landroid/view/SubMenu;)V
invoke-virtual {v0, v1}, Landroid/view/ActionProvider;->onCreateActionView(Landroid/view/MenuItem;)Landroid/view/View;
move-result-object v7
const-string v9, "legacy factory virtual forwarding"
invoke-static {v7, p1, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget v7, v0, Lorg/vinix/bootstrap/BaseProvider;->creates:I
'
	text += equal('v7', 1, 'legacy factory called exactly once')
	text += r'new-instance v0, Lorg/vinix/bootstrap/DynamicProvider;
invoke-direct {v0, p0, p1}, Lorg/vinix/bootstrap/DynamicProvider;-><init>(Landroid/content/Context;Landroid/view/View;)V
new-instance v1, Lorg/vinix/bootstrap/ProviderListener;
invoke-direct {v1}, Lorg/vinix/bootstrap/ProviderListener;-><init>()V
new-instance v2, Lorg/vinix/bootstrap/ProviderListener;
invoke-direct {v2}, Lorg/vinix/bootstrap/ProviderListener;-><init>()V
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
iget v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->overrideCalls:I
'
	text += equal('v7', 0, 'no listener skips predicate')
	text += r'invoke-virtual {v0, v1}, Landroid/view/ActionProvider;->setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
iget v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->overrideCalls:I
'
	text += equal('v7', 1, 'false override predicate called')
	text += 'iget v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->visibleCalls:I\n' + equal('v7', 0, 'false override skips isVisible')
	text += 'iget v7, v1, Lorg/vinix/bootstrap/ProviderListener;->calls:I\n' + equal('v7', 0, 'false override skips listener')
	text += r'const/4 v7, 1
iput-boolean v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->overrides:Z
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
iget-boolean v7, v1, Lorg/vinix/bootstrap/ProviderListener;->last:Z
'
	text += equal('v7', 0, 'false visibility delivered')
	text += r'const/4 v7, 1
iput-boolean v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->visible:Z
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
iget-boolean v7, v1, Lorg/vinix/bootstrap/ProviderListener;->last:Z
'
	text += equal('v7', 1, 'true visibility delivered')
	text += 'iget v7, v1, Lorg/vinix/bootstrap/ProviderListener;->calls:I\n' + equal('v7', 2, 'visibility callbacks not cached')
	text += r'invoke-virtual {v0, v2}, Landroid/view/ActionProvider;->setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
iget v7, v1, Lorg/vinix/bootstrap/ProviderListener;->calls:I
'
	text += equal('v7', 2, 'old visibility listener detached')
	text += 'iget v7, v2, Lorg/vinix/bootstrap/ProviderListener;->calls:I\n' + equal('v7', 1, 'replacement visibility listener called')
	text += r'const/4 v7, 0
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
iget v7, v2, Lorg/vinix/bootstrap/ProviderListener;->calls:I
'
	text += equal('v7', 1, 'null removes visibility listener')
	text += r'invoke-virtual {v0, v2}, Landroid/view/ActionProvider;->setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
'
	text += r'invoke-virtual {v0, v1}, Landroid/view/ActionProvider;->setSubUiVisibilityListener(Landroid/view/ActionProvider$SubUiVisibilityListener;)V
const/4 v7, 1
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->subUiVisibilityChanged(Z)V
const/4 v7, 0
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->subUiVisibilityChanged(Z)V
iget v7, v1, Lorg/vinix/bootstrap/ProviderListener;->subCalls:I
'
	text += equal('v7', 2, 'subUI true and false delivered')
	text += 'iget-boolean v7, v1, Lorg/vinix/bootstrap/ProviderListener;->subLast:Z\n' + equal('v7', 0, 'last subUI state false')
	text += r'const/4 v7, 0
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->setSubUiVisibilityListener(Landroid/view/ActionProvider$SubUiVisibilityListener;)V
const/4 v7, 1
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->subUiVisibilityChanged(Z)V
iget v7, v1, Lorg/vinix/bootstrap/ProviderListener;->subCalls:I
'
	text += equal('v7', 2, 'null removes subUI listener')
	text += r'invoke-virtual {v0, v2}, Landroid/view/ActionProvider;->setSubUiVisibilityListener(Landroid/view/ActionProvider$SubUiVisibilityListener;)V
const/4 v7, 1
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->subUiVisibilityChanged(Z)V
invoke-virtual {v0}, Landroid/view/ActionProvider;->reset()V
invoke-virtual {v0}, Landroid/view/ActionProvider;->refreshVisibility()V
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->subUiVisibilityChanged(Z)V
iget v7, v2, Lorg/vinix/bootstrap/ProviderListener;->calls:I
'
	text += equal('v7', 1, 'reset detaches visibility')
	text += 'iget v7, v2, Lorg/vinix/bootstrap/ProviderListener;->subCalls:I\n' + equal('v7', 1, 'reset detaches subUI')
	text += r'const/4 v7, 0
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
invoke-virtual {v0, v7}, Landroid/view/ActionProvider;->setSubUiVisibilityListener(Landroid/view/ActionProvider$SubUiVisibilityListener;)V
new-instance v3, Landroid/widget/PopupMenu;
invoke-direct {v3, p0, p1}, Landroid/widget/PopupMenu;-><init>(Landroid/content/Context;Landroid/view/View;)V
invoke-virtual {v3}, Landroid/widget/PopupMenu;->getMenu()Landroid/view/Menu;
move-result-object v4
const-string v7, "Provider leaf"
invoke-interface {v4, v7}, Landroid/view/Menu;->add(Ljava/lang/CharSequence;)Landroid/view/MenuItem;
move-result-object v4
invoke-interface {v4}, Landroid/view/MenuItem;->getActionProvider()Landroid/view/ActionProvider;
move-result-object v7
const/4 v8, 0
const-string v9, "provider initially null"
invoke-static {v7, v8, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v4, p1}, Landroid/view/MenuItem;->setActionView(Landroid/view/View;)Landroid/view/MenuItem;
invoke-interface {v4, v0}, Landroid/view/MenuItem;->setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
move-result-object v7
const-string v9, "set provider returns same item"
invoke-static {v7, v4, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v4}, Landroid/view/MenuItem;->getActionProvider()Landroid/view/ActionProvider;
move-result-object v7
const-string v9, "provider identity retained"
invoke-static {v7, v0, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v4}, Landroid/view/MenuItem;->getActionView()Landroid/view/View;
move-result-object v7
const/4 v8, 0
const-string v9, "provider clears old direct action view"
invoke-static {v7, v8, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/view/ActionProvider;->setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
invoke-interface {v4, v0}, Landroid/view/MenuItem;->setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
iget v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->resets:I
'
	text += equal('v7', 2, 'same provider replacement resets old provider')
	text += r'new-instance v5, Lorg/vinix/bootstrap/DynamicProvider;
invoke-direct {v5, p0, p1}, Lorg/vinix/bootstrap/DynamicProvider;-><init>(Landroid/content/Context;Landroid/view/View;)V
invoke-interface {v4, v5}, Landroid/view/MenuItem;->setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
iget v7, v0, Lorg/vinix/bootstrap/DynamicProvider;->resets:I
'
	text += equal('v7', 3, 'different provider resets old provider')
	text += r'const/4 v7, 0
invoke-interface {v4, v7}, Landroid/view/MenuItem;->setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
iget v7, v5, Lorg/vinix/bootstrap/DynamicProvider;->resets:I
'
	text += equal('v7', 1, 'null provider resets old provider')
	text += r'new-instance v6, Lorg/vinix/bootstrap/ModernProvider;
invoke-direct {v6, p0, p1}, Lorg/vinix/bootstrap/ModernProvider;-><init>(Landroid/content/Context;Landroid/view/View;)V
invoke-virtual {v6, v4}, Landroid/view/ActionProvider;->onCreateActionView(Landroid/view/MenuItem;)Landroid/view/View;
move-result-object v7
const-string v9, "modern factory override result"
invoke-static {v7, p1, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget-object v7, v6, Lorg/vinix/bootstrap/ModernProvider;->item:Landroid/view/MenuItem;
const-string v9, "modern factory receives exact MenuItem"
invoke-static {v7, v4, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget v7, v6, Lorg/vinix/bootstrap/BaseProvider;->creates:I
'
	text += equal('v7', 0, 'modern factory does not invoke legacy override')
	// Separate listeners use separate objects to distinguish callback stages.
	text += r'new-instance v1, Lorg/vinix/bootstrap/ProviderProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/ProviderProbe;-><init>()V
new-instance v2, Lorg/vinix/bootstrap/PopupListener;
invoke-direct {v2}, Lorg/vinix/bootstrap/PopupListener;-><init>()V
invoke-interface {v4, v1}, Landroid/view/MenuItem;->setOnMenuItemClickListener(Landroid/view/MenuItem$OnMenuItemClickListener;)Landroid/view/MenuItem;
invoke-virtual {v3, v2}, Landroid/widget/PopupMenu;->setOnMenuItemClickListener(Landroid/widget/PopupMenu$OnMenuItemClickListener;)V
invoke-interface {v4, v5}, Landroid/view/MenuItem;->setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
'
	for i, expected in [1, 12, 123, 123] {
		item_handled := if i == 0 { 1 } else { 0 }
		popup_handled := if i == 1 { 1 } else { 0 }
		provider_handled := if i == 3 { 1 } else { 0 }
		text += 'const/4 v7, ' + item_handled.str() + '\niput-boolean v7, v1, Lorg/vinix/bootstrap/ProviderProbe;->itemHandled:Z\n' +
			'const/4 v7, ' + popup_handled.str() + '\niput-boolean v7, v2, Lorg/vinix/bootstrap/PopupListener;->handled:Z\n' +
			'const/4 v7, ' + provider_handled.str() + '\niput-boolean v7, v5, Lorg/vinix/bootstrap/DynamicProvider;->handled:Z\n' +
			'const/4 v7, 0\nsput v7, Lorg/vinix/bootstrap/ProviderProbe;->sequence:I\ninvoke-static {v3}, Lorg/vinix/bootstrap/ProviderProbe;->click(Landroid/widget/PopupMenu;)V\n' +
			'sget v7, Lorg/vinix/bootstrap/ProviderProbe;->sequence:I\n' + equal('v7', expected, 'popup callback order case ' + i.str())
	}
	text += 'iget v7, v5, Lorg/vinix/bootstrap/DynamicProvider;->actions:I\n' + equal('v7', 2, 'provider invoked only after unhandled callbacks')
	text += r'const/4 v7, 0
invoke-interface {v4, v7}, Landroid/view/MenuItem;->setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
invoke-interface {v4}, Landroid/view/MenuItem;->getActionProvider()Landroid/view/ActionProvider;
move-result-object v7
const/4 v8, 0
const-string v9, "null provider retained after clear"
invoke-static {v7, v8, v9}, Lorg/vinix/bootstrap/ProviderProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
sput v8, Lorg/vinix/bootstrap/ProviderProbe;->sequence:I
invoke-static {v3}, Lorg/vinix/bootstrap/ProviderProbe;->click(Landroid/widget/PopupMenu;)V
sget v7, Lorg/vinix/bootstrap/ProviderProbe;->sequence:I
'
	text += equal('v7', 12, 'no provider leaves callback chain unhandled')
	text += 'return-void\n.end method\n'
	// This listener is a separate class because the two interfaces share the
	// same method signature and must return independent handling decisions.
	return text
}
