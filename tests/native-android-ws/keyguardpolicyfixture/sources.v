// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const manager_type = 'Landroid/app/admin/DevicePolicyManager;'
const component_type = 'Landroid/content/ComponentName;'
const query_signature = 'getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I'
const pass_marker = 'KEYGUARD-POLICY-PASS cached-manager public-instance zero-flags null-admin component-preservation trust-mask dormant-config unmanaged-controls'
const fail_marker = 'KEYGUARD-POLICY-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn checks_source() string {
	return method('private static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
}

fn shape_source() string {
	return method('private static publicInstanceQuery()V', 5, '
const-class v0, ${manager_type}
const-string v1, "getKeyguardDisabledFeatures"
const/4 v2, 1
new-array v2, v2, [Ljava/lang/Class;
const-class v3, ${component_type}
const/4 v4, 0
aput-object v3, v2, v4
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
const-string v4, "keyguard policy query must return primitive int"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v4, "keyguard policy query must be public"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const/4 v2, 0
const-string v4, "keyguard policy query must be an instance method"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

// Match fgup.b's actual null-admin query, bit-0x10 gate and zero early return.
// The unexecuted nonzero continuation keeps the unresolved backend reference
// in this same loaded Main. No platform stub or trust configuration is supplied.
fn trust_mask_source() string {
	return method('private static guardedTrustConfiguration(${manager_type}${component_type})Z', 3, '
const/4 v0, 0
invoke-virtual {p0, v0}, ${manager_type}->${query_signature}
move-result v1
const/16 v2, 0x10
and-int/2addr v1, v2
if-ne v1, v2, :clear
invoke-virtual {p0, v0, p1}, ${manager_type}->getTrustAgentConfiguration(Landroid/content/ComponentName;Landroid/content/ComponentName;)Ljava/util/List;
move-result-object v1
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "unmanaged keyguard path must not reach trust-agent configuration"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:clear
return v0')
}

fn query_source() string {
	return method('private static query(${manager_type}${component_type})V', 6, '
const/4 v0, 0
const/4 v1, 0
const/4 v2, 0
if-eqz p1, :snapshot_done
invoke-virtual {p1}, ${component_type}->getPackageName()Ljava/lang/String;
move-result-object v0
invoke-virtual {p1}, ${component_type}->getClassName()Ljava/lang/String;
move-result-object v1
invoke-virtual {p1}, ${component_type}->hashCode()I
move-result v2
:snapshot_done
invoke-virtual {p0, p1}, ${manager_type}->${query_signature}
move-result v3
const/4 v4, 0
const-string v5, "absent policy backend must report zero disabled keyguard features"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
if-eqz p1, :done
invoke-virtual {p1}, ${component_type}->getPackageName()Ljava/lang/String;
move-result-object v3
const-string v5, "policy query must preserve component package"
invoke-static {v3, v0, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, ${component_type}->getClassName()Ljava/lang/String;
move-result-object v3
const-string v5, "policy query must preserve component class"
invoke-static {v3, v1, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, ${component_type}->hashCode()I
move-result v3
const-string v5, "policy query must preserve component hash"
invoke-static {v3, v2, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0, p1}, ${manager_type}->isAdminActive(Landroid/content/ComponentName;)Z
move-result v3
const/4 v4, 0
const-string v5, "component query must not activate an administrator"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
:done
return-void')
}

fn controls_source() string {
	return method('private static unmanagedControls(${manager_type}Landroid/content/Context;)V', 5, '
const/4 v0, 0
invoke-virtual {p0}, ${manager_type}->getDeviceOwner()Ljava/lang/String;
move-result-object v1
const-string v4, "policy query must preserve absent device owner"
invoke-static {v1, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0}, ${manager_type}->getProfileOwner()Landroid/content/ComponentName;
move-result-object v1
const-string v4, "policy query must preserve absent profile owner"
invoke-static {v1, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0}, ${manager_type}->getActiveAdmins()Ljava/util/List;
move-result-object v1
const-string v4, "policy query must preserve absent active admins"
invoke-static {v1, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0}, ${manager_type}->isDeviceManaged()Z
move-result v1
const-string v4, "policy query must not enroll device management"
invoke-static {v1, v0, v4}, ${main_type}->equal(IILjava/lang/String;)V
const-class v2, Landroid/app/KeyguardManager;
invoke-virtual {p1, v2}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v3
const-string v4, "credential control must use the real KeyguardManager"
invoke-static {v3, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
check-cast v1, Landroid/app/KeyguardManager;
invoke-virtual {v1}, Landroid/app/KeyguardManager;->isDeviceSecure()Z
move-result v1
const-string v4, "keyguard policy query must not fabricate an Android credential"
invoke-static {v1, v0, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn probe_source() string {
	mut cycles := ''
	for _ in 0 .. 3 {
		cycles += '
const/4 v4, 0
invoke-static {v0, v4}, ${main_type}->query(${manager_type}${component_type})V
invoke-static {v0, v1}, ${main_type}->query(${manager_type}${component_type})V
invoke-static {v0, v2}, ${main_type}->query(${manager_type}${component_type})V
invoke-static {v0, v3}, ${main_type}->query(${manager_type}${component_type})V
invoke-static {v0, v1}, ${main_type}->guardedTrustConfiguration(${manager_type}${component_type})Z
move-result v5
const-string v7, "GMS trust-disable mask gate must return false before backend call"
invoke-static {v5, v4, v7}, ${main_type}->equal(IILjava/lang/String;)V
'
	}
	return method('private static probe(Landroid/content/Context;)V', 8, '
const-string v7, "device_policy"
invoke-virtual {p0, v7}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, ${manager_type}
const-class v6, ${manager_type}
invoke-virtual {p0, v6}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v5
const-string v7, "string and class DPM lookup must share the cached manager"
invoke-static {v0, v5, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v5
const-string v7, "cached DPM must retain its platform class identity"
invoke-static {v5, v6, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
new-instance v1, ${component_type}
const-class v5, ${main_type}
invoke-direct {v1, p0, v5}, ${component_type}-><init>(Landroid/content/Context;Ljava/lang/Class;)V
new-instance v2, ${component_type}
const-string v5, "example.unmanaged"
const-string v6, "example.unmanaged.Admin"
invoke-direct {v2, v5, v6}, ${component_type}-><init>(Ljava/lang/String;Ljava/lang/String;)V
new-instance v3, ${component_type}
const-string v5, "android"
const-string v6, "android.app.admin.DeviceAdminReceiver"
invoke-direct {v3, v5, v6}, ${component_type}-><init>(Ljava/lang/String;Ljava/lang/String;)V
' + cycles + '
const-string v6, "device_policy"
invoke-virtual {p0, v6}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v5
const-string v7, "keyguard queries must preserve the cached DPM instance"
invoke-static {v0, v5, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v0, p0}, ${main_type}->unmanagedControls(${manager_type}Landroid/content/Context;)V
return-void')
}

fn verify_source_references(source string) {
	assert source.count('.method private static guardedTrustConfiguration(') == 1
	assert source.count('->guardedTrustConfiguration(') == 3, 'all cycles must invoke the actual trust-mask guard'
	assert source.count('${manager_type}->${query_signature}') == 2, 'direct admin query and null-admin mask query required'
	assert source.count('${manager_type}->getTrustAgentConfiguration(Landroid/content/ComponentName;Landroid/content/ComponentName;)Ljava/util/List;') == 1, 'same loaded Main must retain unresolved backend reference'
	assert source.count('->query(${manager_type}${component_type})V') == 12, 'all four admin forms required in every probe cycle'
	assert source.count('.method private static publicInstanceQuery()V') == 1
	assert source.count('->publicInstanceQuery()V') == 1
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + shape_source() + trust_mask_source() + query_source() + controls_source() + probe_source() +
		method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {}, ${main_type}->publicInstanceQuery()V
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Unmanaged keyguard feature policy checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2')}
}

fn expected_classes() []string { return ['org/vinix/bootstrap/Main.smali'] }
