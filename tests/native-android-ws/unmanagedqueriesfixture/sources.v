// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const pass_marker = 'UNMANAGED-QUERIES-PASS owner-null profile-false service-lookups restrictions-defaults snapshots repeated-queries'
const fail_marker = 'UNMANAGED-QUERIES-FAIL'

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

fn restrictions_source() string {
	return method('private static restrictions(Landroid/os/UserManager;Ljava/lang/String;)Landroid/os/Bundle;', 5, '
invoke-virtual {p0, p1}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v0
invoke-virtual {v0}, Landroid/os/Bundle;->size()I
move-result v1
const/4 v2, 0
const-string v4, "unmanaged application restrictions must be a nonnull empty snapshot"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
const-string v3, "enableWorkAccountAdmin"
invoke-virtual {v0, v3}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z
move-result v1
const-string v4, "GMS work-account key must be absent"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v3}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z
move-result v1
const-string v4, "absent work-account key must default false"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v3, v2}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;Z)Z
move-result v1
const-string v4, "GMS explicit false default must be honored"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v2, 1
invoke-virtual {v0, v3, v2}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;Z)Z
move-result v1
const-string v4, "caller true default is a positive control"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, Landroid/os/Bundle;->size()I
move-result v1
const/4 v2, 0
const-string v4, "default reads must not insert restriction keys"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-object v0')
}

// Preserve the bounded GMS caller's actual query order. The retained owner
// component/boolean controls then establish consistency with existing APIs.
fn cycle_source() string {
	mut body := '
invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->getDeviceOwner()Ljava/lang/String;
move-result-object v0
const/4 v1, 0
const-string v2, "getDeviceOwner must report no enrolled owner package"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, Landroid/os/UserManager;->isManagedProfile()Z
move-result v0
const-string v2, "current single user is not a managed profile"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p1, p2}, ${main_type}->restrictions(Landroid/os/UserManager;Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v3
'
	for signature in ['getDeviceOwnerComponentOnCallingUser()Landroid/content/ComponentName;', 'getDeviceOwnerComponentOnAnyUser()Landroid/content/ComponentName;'] {
		body += 'invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->${signature}\nmove-result-object v0\nconst-string v2, "owner package and retained component query must agree"\ninvoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
	}
	body += '
invoke-virtual {p0, p2}, Landroid/app/admin/DevicePolicyManager;->isDeviceOwnerApp(Ljava/lang/String;)Z
move-result v0
const-string v2, "fixture package cannot be owner without enrollment"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->isDeviceManaged()Z
move-result v0
const-string v2, "retained device-managed query must remain false"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-object v3'
	return method('private static cycle(Landroid/app/admin/DevicePolicyManager;Landroid/os/UserManager;Ljava/lang/String;)Landroid/os/Bundle;', 4, body)
}

fn profile_source() string {
	return method('private static profile(Landroid/os/UserManager;)Ljava/util/List;', 4, '
invoke-virtual {p0}, Landroid/os/UserManager;->getUserProfiles()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v1
const/4 v2, 1
const-string v3, "unmanaged guest exposes only current user profile"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v1, 0
invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/UserHandle;
invoke-virtual {v1}, Landroid/os/UserHandle;->getIdentifier()I
move-result v1
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v2
const-string v3, "only profile identifier must match current Android user"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
return-object v0') + method('private static profiles(Landroid/os/UserManager;)V', 5, '
invoke-static {p0}, ${main_type}->profile(Landroid/os/UserManager;)Ljava/util/List;
move-result-object v0
invoke-static {p0}, ${main_type}->profile(Landroid/os/UserManager;)Ljava/util/List;
move-result-object v1
const-string v4, "profile queries must return independent lists"
invoke-static {v0, v1, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v0}, Ljava/util/List;->clear()V
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 1
const-string v4, "clearing one profile snapshot must not change another"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p0}, ${main_type}->profile(Landroid/os/UserManager;)Ljava/util/List;
move-result-object v2
const-string v4, "later profile query must not reuse cleared list"
invoke-static {v0, v2, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v1, v2, v4}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 0
const-string v4, "later query must preserve caller-owned cleared list"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 1
const-string v4, "later query must preserve other live profile snapshot"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0}, Landroid/os/UserManager;->isManagedProfile()Z
move-result v2
const/4 v3, 0
const-string v4, "profile snapshot mutation cannot change managed state"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn probe_source() string {
	return method('private static probe(Landroid/content/Context;)V', 8, '
const-string v7, "device_policy"
invoke-virtual {p0, v7}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/admin/DevicePolicyManager;
const-class v7, Landroid/app/admin/DevicePolicyManager;
invoke-virtual {p0, v7}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
const-string v7, "DPM string/class lookup must share cached instance"
invoke-static {v0, v1, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/app/admin/DevicePolicyManager;
const-string v7, "DPM lookup must resolve the SDK class identity"
invoke-static {v1, v2, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v7, "user"
invoke-virtual {p0, v7}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/UserManager;
const-class v7, Landroid/os/UserManager;
invoke-virtual {p0, v7}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/os/UserManager;
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v3
invoke-virtual {v2}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v4
const-class v5, Landroid/os/UserManager;
const-string v7, "UM string and class lookup must resolve the same SDK class"
invoke-static {v3, v5, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v4, v5, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v3
invoke-static {v0, v1, v3}, ${main_type}->cycle(Landroid/app/admin/DevicePolicyManager;Landroid/os/UserManager;Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v4
const-string v6, "enableWorkAccountAdmin"
const/4 v7, 1
invoke-virtual {v4, v6, v7}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V
invoke-static {v0, v2, v3}, ${main_type}->cycle(Landroid/app/admin/DevicePolicyManager;Landroid/os/UserManager;Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v5
const-string v7, "restriction queries must return fresh snapshots"
invoke-static {v4, v5, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v4, v6}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z
move-result v6
const/4 v7, 1
const-string v2, "later query must preserve caller-owned true mutation"
invoke-static {v6, v7, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0, v1, v3}, ${main_type}->cycle(Landroid/app/admin/DevicePolicyManager;Landroid/os/UserManager;Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v6
const-string v7, "third restriction snapshot must remain independent"
invoke-static {v4, v6, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v5, v6, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v6, "enableWorkAccountAdmin"
invoke-virtual {v4, v6}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z
move-result v6
const/4 v7, 1
const-string v2, "repeated queries must preserve caller-owned restriction mutation"
invoke-static {v6, v7, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v1}, ${main_type}->profiles(Landroid/os/UserManager;)V
return-void')
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + restrictions_source() + cycle_source() + profile_source() + probe_source() + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Unmanaged ownership and profile query contracts passed"
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
