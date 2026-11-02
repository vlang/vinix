// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_subscription_service_classes() map[string]string {
	// Only the null-result API type is needed. No subscription records exist.
	return {
		'android/telephony/SubscriptionInfo': '.class public final Landroid/telephony/SubscriptionInfo;\n.super Ljava/lang/Object;\n'
	}
}

fn subscription_directive(line string, name string) bool {
	parts := line.fields()
	return parts.len > 0 && parts[0] == name
}

fn subscription_methods(source string) !map[string]string {
	lines := source.split_into_lines().map(it.trim_space())
	headers := lines.filter(subscription_directive(it, '.method'))
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end'
		&& it.fields()[1] == 'method')
	blocks := source.split('.method ')[1..]
	if headers.len != blocks.len || ends.len != blocks.len
		|| ends.any(it != '.end method') {
		return error('balanced canonical subscription API methods required')
	}
	mut result := map[string]string{}
	for block in blocks {
		header := block.all_before('\n')
		name := header.all_after_last(' ')
		if header.trim_space() != header || !name.contains('(') || name in result
			|| block.count('.end method') != 1 {
			return error('unique complete subscription API methods required')
		}
		end := block.index('.end method') or { return error('unterminated subscription method') }
		result[name] = '.method ' + block[..end] + '.end method'
	}
	return result
}

fn subscription_shape(source string, class_name string, modifiers string) !map[string]string {
	lines := source.split_into_lines().map(it.trim_space())
	if lines.filter(subscription_directive(it, '.class')) != ['.class ' + modifiers + ' L' + class_name + ';']
		|| lines.filter(subscription_directive(it, '.super')) != ['.super L' + if class_name == 'android/app/ContextImpl' {
			'android/content/Context;'
		} else {
			'java/lang/Object;'
		}] {
		return error('canonical subscription target class and superclass required')
	}
	mut fields := map[string]bool{}
	for line in lines.filter(subscription_directive(it, '.field')) {
		parts := line.all_before(' =').fields()
		if parts.len < 3 || !parts.last().contains(':') {
			return error('canonical subscription target fields required')
		}
		name := parts.last().all_before(':')
		if name in fields { return error('duplicate subscription target field') }
		fields[name] = true
	}
	if source.contains('vinixSubscription') || source.contains('vinix_subscription_') {
		return error('subscription service reserved member collision')
	}
	return subscription_methods(source)!
}

fn subscription_norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

// These lookup methods contain no quoted colons: normalize only their labels,
// retaining target sharing and every instruction in the preceding fallback.
fn subscription_labels(source string) string {
	mut names := map[string]string{}
	mut result := ''
	mut i := 0
	for i < source.len {
		if source[i] != `:` {
			result += source[i..i + 1]
			i++
			continue
		}
		mut end := i + 1
		for end < source.len && (source[end].is_alnum() || source[end] in [`_`, `$`, `-`]) { end++ }
		name := source[i..end]
		if name !in names { names[name] = ':subscription_label_' + names.len.str() }
		result += names[name]
		i = end
	}
	return result
}

pub fn framework_subscription_context_source(original string) !string {
	methods := subscription_shape(original, 'android/app/ContextImpl', 'public final')!
	string_signature := 'getSystemService(Ljava/lang/String;)Ljava/lang/Object;'
	typed_signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
	old_string := methods[string_signature] or { return error('string service lookup missing') }
	old_typed := methods[typed_signature] or { return error('typed service lookup missing') }
	expected_string := '.method public getSystemService(Ljava/lang/String;)Ljava/lang/Object;
.registers 3
const-string v0, "device_policy"
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :other
invoke-direct {p0}, Landroid/app/ContextImpl;->vinixDevicePolicy()Landroid/app/admin/DevicePolicyManager;
move-result-object v0
return-object v0
:other
invoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixPolicyFallbackString(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method'
	expected_typed := '.method public getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
.registers 3
const-class v0, Landroid/app/StatsManager;
if-ne p1, v0, :stats_other
const/4 v0, 0x0
return-object v0
:stats_other
const-class v0, Landroid/content/pm/CrossProfileApps;
if-ne p1, v0, :cross_other
const/4 v0, 0x0
return-object v0
:cross_other
const-class v0, Landroid/service/persistentdata/PersistentDataBlockManager;
if-ne p1, v0, :persistent_other
const/4 v0, 0x0
return-object v0
:persistent_other
const-class v0, Landroid/net/wifi/rtt/WifiRttManager;
if-ne p1, v0, :rtt_other
const/4 v0, 0x0
return-object v0
:rtt_other
invoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixRttFallbackClass(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method'
	if subscription_labels(subscription_norm(old_string).replace('.locals 1', '.registers 3')) != subscription_labels(expected_string)
		|| subscription_labels(subscription_norm(old_typed)) != subscription_labels(expected_typed) {
		return error('retained subscription service fallback instructions required')
	}
	string_guard := '\nconst-string v0, "telephony_subscription_service"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :vinix_subscription_string_other\ninvoke-direct {p0}, Landroid/app/ContextImpl;->vinixSubscriptionService()Landroid/telephony/SubscriptionManager;\nmove-result-object v0\nreturn-object v0\n:vinix_subscription_string_other\n'
	typed_guard := '\nconst-class v0, Landroid/telephony/SubscriptionManager;\nif-ne p1, v0, :vinix_subscription_typed_other\ninvoke-direct {p0}, Landroid/app/ContextImpl;->vinixSubscriptionService()Landroid/telephony/SubscriptionManager;\nmove-result-object v0\nreturn-object v0\n:vinix_subscription_typed_other\n'
	string_registers := if subscription_norm(old_string).split_into_lines().contains('.locals 1') {
		'.locals 1'
	} else {
		'.registers 3'
	}
	if old_string.count(string_registers) != 1 || old_typed.count('.registers 3') != 1 {
		return error('unambiguous subscription lookup register declarations required')
	}
	mut result := original.replace(old_string, old_string.replace(string_registers, string_registers + string_guard))
	result = result.replace(old_typed, old_typed.replace('.registers 3', '.registers 3' + typed_guard))
	// Explicit DEX monitors are required: ART's execution path here does not
	// supply the locking implied by a method's synchronized access flag alone.
	return result + '\n.field private vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
.method private vinixSubscriptionService()Landroid/telephony/SubscriptionManager;
.registers 2
monitor-enter p0
:vinix_subscription_locked
iget-object v0, p0, Landroid/app/ContextImpl;->vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
if-nez v0, :vinix_subscription_unlock
new-instance v0, Landroid/telephony/SubscriptionManager;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager;-><init>()V
iput-object v0, p0, Landroid/app/ContextImpl;->vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
:vinix_subscription_unlock
monitor-exit p0
return-object v0
:vinix_subscription_failed
move-exception v0
monitor-exit p0
throw v0
.catchall {:vinix_subscription_locked .. :vinix_subscription_unlock} :vinix_subscription_failed
.end method\n'
}

pub fn framework_subscription_manager_source(original string) !string {
	methods := subscription_shape(original, 'android/telephony/SubscriptionManager', 'public')!
	if methods.keys() != ['<init>()V']
		|| subscription_norm(methods['<init>()V']) != '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method'
		|| original.split_into_lines().any(subscription_directive(it.trim_space(), '.field')) {
		return error('retained constructor-only subscription manager required')
	}
	// AOSP distinguishes unavailable subscription information (null) from a
	// known empty list. The Android 13 number API throws when ISub is absent.
	return original + '\n.method public getActiveSubscriptionInfoList()Ljava/util/List;
.registers 2
const/4 v0, 0x0
return-object v0
.end method
.method public getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;
.registers 3
const/4 v0, 0x0
return-object v0
.end method
.method public getPhoneNumber(I)Ljava/lang/String;
.registers 4
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "subscription service unavailable."
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
.end method\n'
}

pub fn framework_subscription_telephony_source(original string) !string {
	methods := subscription_shape(original, 'android/telephony/TelephonyManager', 'public')!
	for signature in ['getPhoneCount()I', 'getActiveModemCount()I',
		'createForSubscriptionId(I)Landroid/telephony/TelephonyManager;'] {
		if signature in methods { return error('subscription telephony API already exists') }
	}
	if '<init>()V' !in methods
		|| subscription_norm(methods['<init>()V']) != '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method' {
		return error('retained telephony no-argument constructor required')
	}
	// This WS target has no voice/SMS/data modem (framework_absent_hardware).
	// These are hardware counts, independent of the subscription binder state.
	// Keep the original constructor unchanged; only factory children bind an ID.
	return original + '\n.field private vinixSubscriptionId:I
.method public getPhoneCount()I
.registers 2
const/4 v0, 0x0
return v0
.end method
.method public getActiveModemCount()I
.registers 2
const/4 v0, 0x0
return v0
.end method
.method public createForSubscriptionId(I)Landroid/telephony/TelephonyManager;
.registers 3
new-instance v0, Landroid/telephony/TelephonyManager;
invoke-direct {v0}, Landroid/telephony/TelephonyManager;-><init>()V
iput p1, v0, Landroid/telephony/TelephonyManager;->vinixSubscriptionId:I
return-object v0
.end method\n'
}

pub fn framework_subscription_service(smali string) ! {
	context := smali + '/android/app/ContextImpl.smali'
	subscription := smali + '/android/telephony/SubscriptionManager.smali'
	telephony := smali + '/android/telephony/TelephonyManager.smali'
	patched_context := framework_subscription_context_source(os.read_file(context)!)!
	patched_subscription := framework_subscription_manager_source(os.read_file(subscription)!)!
	patched_telephony := framework_subscription_telephony_source(os.read_file(telephony)!)!
	classes := framework_subscription_service_classes()
	for name, _ in classes {
		path := smali + '/' + name + '.smali'
		if os.exists(path) || os.is_link(path) {
			return error('subscription info API type already exists')
		}
	}
	// Validate the complete batch, including new path collisions, before writes.
	for name, source in classes {
		path := smali + '/' + name + '.smali'
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
	}
	os.write_file(context, patched_context)!
	os.write_file(subscription, patched_subscription)!
	os.write_file(telephony, patched_telephony)!
}
