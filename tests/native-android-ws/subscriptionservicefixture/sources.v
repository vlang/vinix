// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const pass_marker = 'SUBSCRIPTION-SERVICE-PASS service-identity null-list null-info unavailable-phone zero-modems fresh-bound-wrappers dormant-getters fallback-controls'
const fail_marker = 'SUBSCRIPTION-SERVICE-FAIL'

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
return-void') + method('private static distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
}

// These are real cjzs-style null branches. The absent SubscriptionInfo getter
// methods deliberately remain referenced in this same loaded/used Main class.
// Do not provide APK platform stubs or suppress ART verifier diagnostics.
fn nullable_source() string {
	return method('private static nullableSlot(Landroid/telephony/SubscriptionManager;I)Ljava/lang/Integer;', 3, '
const/4 v0, 0
invoke-virtual {p0, p1}, Landroid/telephony/SubscriptionManager;->getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;
move-result-object v1
if-eqz v1, :done
invoke-virtual {v1}, Landroid/telephony/SubscriptionInfo;->getSimSlotIndex()I
move-result v2
invoke-static {v2}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v0
:done
return-object v0') + method('private static nullableSubscription(Landroid/telephony/SubscriptionManager;I)Ljava/lang/Integer;', 4, '
const/4 v0, 0
invoke-virtual {p0}, Landroid/telephony/SubscriptionManager;->getActiveSubscriptionInfoList()Ljava/util/List;
move-result-object v1
if-eqz v1, :done
invoke-interface {v1}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v1
:again
invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :done
invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/telephony/SubscriptionInfo;
invoke-virtual {v2}, Landroid/telephony/SubscriptionInfo;->getSimSlotIndex()I
move-result v3
if-ne v3, p1, :again
invoke-virtual {v2}, Landroid/telephony/SubscriptionInfo;->getSubscriptionId()I
move-result v3
invoke-static {v3}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v0
:done
return-object v0')
}

fn verify_dormant_references(source string) {
	for signature in ['nullableSlot(Landroid/telephony/SubscriptionManager;I)Ljava/lang/Integer;',
		'nullableSubscription(Landroid/telephony/SubscriptionManager;I)Ljava/lang/Integer;'] {
		assert source.count('.method private static ' + signature) == 1, 'one actual null-branch method required'
		assert source.count('->' + signature) == 1, 'actual null branch must be invoked by the fixture'
	}
	assert source.count('Landroid/telephony/SubscriptionInfo;->getSimSlotIndex()I') == 2, 'both exact unresolved slot getters required'
	assert source.count('Landroid/telephony/SubscriptionInfo;->getSubscriptionId()I') == 1, 'exact unresolved ID getter required'
}

fn phone_source() string {
	return method('private static unavailablePhone(Landroid/telephony/SubscriptionManager;I)V', 3, '
:try_start
invoke-virtual {p0, p1}, Landroid/telephony/SubscriptionManager;->getPhoneNumber(I)Ljava/lang/String;
move-result-object v0
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "phone lookup must throw when subscription service is unavailable"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Ljava/lang/IllegalStateException; {:try_start .. :try_end} :unavailable
:unavailable
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v0
const-string v1, "subscription service unavailable."
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
const-string v2, "unavailable phone exception must retain exact message"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn telephony_source() string {
	return method('private static noModems(Landroid/telephony/TelephonyManager;)V', 3, '
const/4 v0, 0
invoke-virtual {p0}, Landroid/telephony/TelephonyManager;->getPhoneCount()I
move-result v1
const-string v2, "fixed guest has no phone modem"
invoke-static {v1, v0, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0}, Landroid/telephony/TelephonyManager;->getActiveModemCount()I
move-result v1
const-string v2, "fixed guest has no active modem"
invoke-static {v1, v0, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static boundId(Landroid/telephony/TelephonyManager;I)V', 3, '
const-class v0, Landroid/telephony/TelephonyManager;
const-string v1, "vinixSubscriptionId"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->getInt(Ljava/lang/Object;)I
move-result v1
const-string v2, "fresh telephony wrapper must retain requested subscription ID"
invoke-static {v1, p1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static wrappers(Landroid/telephony/TelephonyManager;I)V', 5, '
invoke-virtual {p0, p1}, Landroid/telephony/TelephonyManager;->createForSubscriptionId(I)Landroid/telephony/TelephonyManager;
move-result-object v0
invoke-virtual {p0, p1}, Landroid/telephony/TelephonyManager;->createForSubscriptionId(I)Landroid/telephony/TelephonyManager;
move-result-object v1
const-string v4, "subscription wrapper must be distinct from parent"
invoke-static {v0, p0, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v1, p0, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v4, "same requested ID still requires fresh wrappers"
invoke-static {v0, v1, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v0, p1}, ${main_type}->boundId(Landroid/telephony/TelephonyManager;I)V
invoke-static {v1, p1}, ${main_type}->boundId(Landroid/telephony/TelephonyManager;I)V
xor-int/lit8 v2, p1, 1
invoke-virtual {p0, v2}, Landroid/telephony/TelephonyManager;->createForSubscriptionId(I)Landroid/telephony/TelephonyManager;
move-result-object v3
const-string v4, "different requested ID requires another distinct wrapper"
invoke-static {v3, p0, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v3, v0, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v3, v1, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v3, v2}, ${main_type}->boundId(Landroid/telephony/TelephonyManager;I)V
invoke-static {v0, p1}, ${main_type}->boundId(Landroid/telephony/TelephonyManager;I)V
invoke-static {p0}, ${main_type}->noModems(Landroid/telephony/TelephonyManager;)V
invoke-static {v0}, ${main_type}->noModems(Landroid/telephony/TelephonyManager;)V
invoke-static {v1}, ${main_type}->noModems(Landroid/telephony/TelephonyManager;)V
invoke-static {v3}, ${main_type}->noModems(Landroid/telephony/TelephonyManager;)V
return-void')
}

fn query_source() string {
	return method('private static query(Landroid/telephony/SubscriptionManager;Landroid/telephony/TelephonyManager;I)V', 4, '
const/4 v0, 0
invoke-virtual {p0}, Landroid/telephony/SubscriptionManager;->getActiveSubscriptionInfoList()Ljava/util/List;
move-result-object v1
const-string v3, "unavailable subscription list must be null"
invoke-static {v1, v0, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0, p2}, Landroid/telephony/SubscriptionManager;->getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;
move-result-object v1
const-string v3, "unavailable subscription info must be null for every requested ID"
invoke-static {v1, v0, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {p0, p2}, ${main_type}->nullableSlot(Landroid/telephony/SubscriptionManager;I)Ljava/lang/Integer;
move-result-object v1
const-string v3, "GMS-like nullable slot path must return null before absent getter"
invoke-static {v1, v0, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {p0, p2}, ${main_type}->nullableSubscription(Landroid/telephony/SubscriptionManager;I)Ljava/lang/Integer;
move-result-object v1
const-string v3, "GMS-like nullable list path must return null before absent getters"
invoke-static {v1, v0, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {p0, p2}, ${main_type}->unavailablePhone(Landroid/telephony/SubscriptionManager;I)V
invoke-static {p1, p2}, ${main_type}->wrappers(Landroid/telephony/TelephonyManager;I)V
return-void')
}

fn probe_source() string {
	mut ids := ''
	for id in ['-0x80000000', '-1', '0', '1', '7', '0x7fffffff'] {
		ids += 'const v2, ${id}\ninvoke-static {v0, v1, v2}, ${main_type}->query(Landroid/telephony/SubscriptionManager;Landroid/telephony/TelephonyManager;I)V\n'
	}
	return method('private static probe(Landroid/content/Context;)V', 7, '
const-string v0, "telephony_subscription_service"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/telephony/SubscriptionManager;
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/telephony/SubscriptionManager;
const-string v6, "real subscription provider class must resolve"
invoke-static {v1, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0, v2}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
const-string v6, "string and typed subscription lookup must share cached instance"
invoke-static {v0, v1, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "telephony_subscription_service"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
invoke-static {v0, v1, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "phone"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/telephony/TelephonyManager;
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v2
const-class v3, Landroid/telephony/TelephonyManager;
const-string v6, "real telephony provider class must resolve"
invoke-static {v2, v3, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-class v2, Landroid/telephony/SubscriptionInfo;
const-string v3, "android.telephony.SubscriptionInfo"
invoke-static {v3}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v3
const-string v6, "SubscriptionInfo type identity must match without an APK stub"
invoke-static {v2, v3, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
${ids}
const-string v2, "telephony_subscription_service"
invoke-virtual {p0, v2}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
const-string v6, "queries must preserve the cached subscription service"
invoke-static {v0, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
new-instance v2, Landroid/telephony/TelephonyManager;
invoke-direct {v2}, Landroid/telephony/TelephonyManager;-><init>()V
invoke-static {v2}, ${main_type}->noModems(Landroid/telephony/TelephonyManager;)V
const/4 v3, 0
invoke-virtual {v1}, Landroid/telephony/TelephonyManager;->getSimState()I
move-result v4
const-string v6, "legacy SIM-state query must retain its unknown result"
invoke-static {v4, v3, v6}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v1}, Landroid/telephony/TelephonyManager;->getLine1Number()Ljava/lang/String;
move-result-object v4
const-string v6, "legacy line-number query must retain its null result"
invoke-static {v4, v3, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v2, 0
const-class v3, Landroid/app/StatsManager;
invoke-virtual {p0, v3}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v3
const-string v6, "StatsManager typed lookup must remain unavailable"
invoke-static {v3, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v3, "device_policy"
invoke-virtual {p0, v3}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v3
const-class v4, Landroid/app/admin/DevicePolicyManager;
invoke-virtual {p0, v4}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v5
const-string v6, "known DPM fallback must retain cached string/class identity"
invoke-static {v3, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v3}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v3
const-string v6, "known DPM fallback must retain real class identity"
invoke-static {v3, v4, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + nullable_source() + phone_source() + telephony_source() + query_source() + probe_source() + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Subscription unavailable paths and zero modem checks passed"
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
