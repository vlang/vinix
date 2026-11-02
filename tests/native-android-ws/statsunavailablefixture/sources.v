// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const pass_marker = 'STATS-UNAVAILABLE-PASS class-identity string-null typed-null early-returns dormant-references service-fallback repeated-queries'
const fail_marker = 'STATS-UNAVAILABLE-FAIL'

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

// The audited fojo.e returns false immediately after string lookup/null cast.
// Its nonnull continuation is intentionally rejected rather than simulated.
fn early_source() string {
	return method('private static earlyFalse(Landroid/content/Context;)Z', 2, '
const-string v0, "stats"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/StatsManager;
if-nez v0, :unexpected
const/4 v0, 0
return v0
:unexpected
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "unavailable stats branch must return before telemetry"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static earlyVoid(Landroid/content/Context;)V', 2, '
const-string v0, "stats"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/StatsManager;
if-eqz v0, :done
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "unavailable post-init branch must return without telemetry"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
}

// Do not call this method or add APK definitions for either unresolved platform
// reference. It deliberately models fojo.h in the same loaded/used class.
// ARM evidence must retain every ART verification/health diagnostic.
fn dormant_source() string {
	return method('private static dormantRemove(Landroid/app/StatsManager;J)V', 1, '
:try_start
invoke-virtual {p0, p1, p2}, Landroid/app/StatsManager;->removeConfig(J)V
:try_end
return-void
.catch Landroid/app/StatsManager$StatsUnavailableException; {:try_start .. :try_end} :caught
:caught
move-exception v0
return-void')
}

fn verify_dormant_references(source string) {
	signature := '.method private static dormantRemove(Landroid/app/StatsManager;J)V'
	assert source.count(signature) == 1, 'one dormant method required in the actual Main class'
	block := source.all_after(signature).all_before('.end method')
	assert block.count('Landroid/app/StatsManager;->removeConfig(J)V') == 1, 'exact real unresolved method tuple required'
	assert block.count('.catch Landroid/app/StatsManager$StatsUnavailableException;') == 1, 'exact real unresolved catch type required'
	assert source.count('->dormantRemove(') == 0, 'dormant method must never be invoked by the fixture'
}

fn probe_source() string {
	return method('private static probe(Landroid/content/Context;)V', 7, '
const-class v0, Landroid/app/StatsManager;
const-string v1, "android.app.StatsManager"
invoke-static {v1}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v2
const-string v6, "StatsManager reflective and DEX identities must match"
invoke-static {v0, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v5, 0
:again
const-string v1, "stats"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/app/StatsManager;
const/4 v2, 0
const-string v6, "string stats lookup must report unavailable"
invoke-static {v1, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/app/StatsManager;
const-string v6, "typed stats lookup must report unavailable without construction"
invoke-static {v1, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {p0}, ${main_type}->earlyFalse(Landroid/content/Context;)Z
move-result v1
const-string v6, "GMS-like availability query must return false"
invoke-static {v1, v2, v6}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p0}, ${main_type}->earlyVoid(Landroid/content/Context;)V
const-string v1, "device_policy"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v3
const-class v1, Landroid/app/admin/DevicePolicyManager;
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v4
const-string v6, "known DPM fallback must retain string/class cached identity"
invoke-static {v3, v4, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v3}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v2
const-string v6, "known DPM fallback must retain actual SDK class identity"
invoke-static {v1, v2, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
add-int/lit8 v5, v5, 1
const/4 v1, 3
if-lt v5, v1, :again
return-void')
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + early_source() + dormant_source() + probe_source() + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Stats unavailable branches and service fallback passed"
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

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali']
}
