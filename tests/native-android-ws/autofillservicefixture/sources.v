// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const manager_type = 'Landroid/view/autofill/AutofillManager;'
const value_type = 'Landroid/view/autofill/AutofillValue;'
const query_signature = 'getAutofillServiceComponentName()Landroid/content/ComponentName;'
const pass_marker = 'AUTOFILL-SERVICE-PASS typed-manager string-null component-null public-instance null-branch notifications typed-values'
const fail_marker = 'AUTOFILL-SERVICE-FAIL'

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
const-string v1, "getAutofillServiceComponentName"
const/4 v2, 0
new-array v2, v2, [Ljava/lang/Class;
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/content/ComponentName;
const-string v4, "query return type must be the real ComponentName class"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v4, "component query must be public"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const/4 v2, 0
const-string v4, "component query must be an instance method"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

// The invoked caller reaches the same null guard as a provider lookup. The
// ComponentName continuation remains in the loaded Main class, without a stub.
fn null_branch_source() string {
	return method('private static selectedProvider(${manager_type}Ljava/lang/String;)Z', 2, '
:try_start
invoke-virtual {p0}, ${manager_type}->${query_signature}
move-result-object v0
if-eqz v0, :absent
invoke-virtual {v0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
invoke-virtual {p1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
return v1
:try_end
.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :unavailable
:unavailable
move-exception v0
:absent
const/4 v1, 0
return v1')
}

fn notification_source() string {
	return method('private static inactiveNotifications(${manager_type})V', 3, '
const/4 v0, 0
const/4 v1, 7
const/4 v2, 1
invoke-virtual {p0, v0, v1, v2}, ${manager_type}->notifyViewVisibilityChanged(Landroid/view/View;IZ)V
invoke-virtual {p0, v0, v1, v0}, ${manager_type}->notifyValueChanged(Landroid/view/View;ILandroid/view/autofill/AutofillValue;)V
invoke-virtual {p0, v0, v1, v0}, ${manager_type}->notifyViewEntered(Landroid/view/View;ILandroid/graphics/Rect;)V
invoke-virtual {p0, v0, v1}, ${manager_type}->notifyViewExited(Landroid/view/View;I)V
invoke-virtual {p0, v0}, ${manager_type}->registerCallback(Landroid/view/autofill/AutofillManager$AutofillCallback;)V
invoke-virtual {p0, v0}, ${manager_type}->unregisterCallback(Landroid/view/autofill/AutofillManager$AutofillCallback;)V
invoke-virtual {p0}, ${manager_type}->${query_signature}
move-result-object v1
const-string v2, "inactive notifications must not fabricate a provider"
invoke-static {v1, v0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn value_source() string {
	return method('private static ordinaryValues()V', 6, '
const/4 v0, 0
invoke-static {v0}, ${value_type}->forText(Ljava/lang/CharSequence;)${value_type}
move-result-object v1
const-string v5, "null text must retain its null factory result"
invoke-static {v1, v0, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "ordinary text"
invoke-static {v0}, ${value_type}->forText(Ljava/lang/CharSequence;)${value_type}
move-result-object v1
invoke-virtual {v1}, ${value_type}->isText()Z
move-result v2
const/4 v3, 1
const-string v5, "text value must retain its type"
invoke-static {v2, v3, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v1}, ${value_type}->getTextValue()Ljava/lang/CharSequence;
move-result-object v2
const-string v5, "plain text value must retain its content"
invoke-static {v2, v0, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, ${value_type}->isEmpty()Z
move-result v2
const/4 v3, 0
const-string v5, "ordinary text must not become empty"
invoke-static {v2, v3, v5}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v0, 1
invoke-static {v0}, ${value_type}->forToggle(Z)${value_type}
move-result-object v1
invoke-virtual {v1}, ${value_type}->getToggleValue()Z
move-result v2
const-string v5, "toggle value must retain its value"
invoke-static {v2, v0, v5}, ${main_type}->equal(IILjava/lang/String;)V
const/16 v0, 42
invoke-static {v0}, ${value_type}->forList(I)${value_type}
move-result-object v1
invoke-virtual {v1}, ${value_type}->getListValue()I
move-result v2
const-string v5, "list value must retain its index"
invoke-static {v2, v0, v5}, ${main_type}->equal(IILjava/lang/String;)V
const-wide v0, 0x123456789L
invoke-static {v0, v1}, ${value_type}->forDate(J)${value_type}
move-result-object v2
invoke-virtual {v2}, ${value_type}->getDateValue()J
move-result-wide v2
cmp-long v4, v0, v2
const/4 v0, 0
const-string v5, "date value must retain all long bits"
invoke-static {v4, v0, v5}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn probe_source() string {
	mut cycles := ''
	for _ in 0 .. 3 {
		cycles += '
const-class v0, ${manager_type}
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v2
const-string v5, "typed lookup must return a real AutofillManager"
invoke-static {v2, v0, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
check-cast v1, ${manager_type}
invoke-virtual {v1}, ${manager_type}->${query_signature}
move-result-object v2
const/4 v3, 0
const-string v5, "absent backing service must yield no selected component"
invoke-static {v2, v3, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v2, "com.google.android.gms"
invoke-static {v1, v2}, ${main_type}->selectedProvider(${manager_type}Ljava/lang/String;)Z
move-result v2
const-string v5, "null provider caller must return false without dereference"
invoke-static {v2, v3, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v1}, ${main_type}->inactiveNotifications(${manager_type})V
const-string v0, "autofill"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
const-string v5, "existing unsupported string lookup must remain null"
invoke-static {v0, v3, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	}
	return method('private static probe(Landroid/content/Context;)V', 6, cycles + 'return-void')
}

fn verify_source_references(source string) {
	assert source.count('.method private static selectedProvider(') == 1, 'one actual nullable-provider caller required'
	assert source.count('->selectedProvider(') == 3, 'all three probe cycles must invoke the nullable caller'
	assert source.count('${manager_type}->${query_signature}') == 5, 'direct, nullable and notification queries must remain present'
	assert source.count('Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;') == 1, 'nonnull continuation must remain present'
	assert source.count('.method private static publicInstanceQuery()V') == 1
	assert source.count('->publicInstanceQuery()V') == 1
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + shape_source() + null_branch_source() + notification_source() + value_source() + probe_source() +
		method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {}, ${main_type}->publicInstanceQuery()V
invoke-static {}, ${main_type}->ordinaryValues()V
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, ${main_type}->probe(Landroid/content/Context;)V
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Absent autofill service query and typed value checks passed"
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
