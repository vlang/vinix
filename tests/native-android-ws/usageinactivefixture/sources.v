// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const manager_type = 'Landroid/app/usage/UsageStatsManager;'
const query_signature = 'isAppInactive(Ljava/lang/String;)Z'
const pass_marker = 'USAGE-INACTIVE-PASS public-instance typed-service constructor arbitrary-packages null-empty-unicode repeat-32 legacy-service-null disabled-policy'
const fail_marker = 'USAGE-INACTIVE-FAIL'

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
const-string v1, "isAppInactive"
const/4 v2, 1
new-array v2, v2, [Ljava/lang/Class;
const-class v3, Ljava/lang/String;
const/4 v4, 0
aput-object v3, v2, v4
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Boolean;->TYPE:Ljava/lang/Class;
const-string v4, "isAppInactive must return primitive boolean"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v4, "isAppInactive must be public"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const/4 v2, 0
const-string v4, "isAppInactive must be an instance method"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn query_source() string {
	mut body := '
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
const-class v1, ${manager_type}
const-string v2, "real typed lookup and constructor must provide UsageStatsManager"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v0, 0
:again
'
	for argument in ['p1', '"com.google.android.gms"', '"com.google.android.apps.maps"',
		'"org.vinix.no_such_package.usage"', '""', '', '"org.vinix.使用.Δ"'] {
		body += if argument == 'p1' { 'move-object v1, p1\n' } else if argument == '' {
			'const/4 v1, 0\n'
		} else { 'const-string v1, ${argument}\n' }
		body += 'invoke-virtual {p0, v1}, ${manager_type}->${query_signature}\nmove-result v1\n' +
			'const/4 v2, 0\nconst-string v3, "disabled app-standby policy must not classify any argument as inactive"\n' +
			'invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V\n'
	}
	body += 'add-int/lit8 v0, v0, 1
const/16 v1, 32
if-lt v0, v1, :again
return-void'
	return method('private static query(${manager_type}Ljava/lang/String;)V', 4, body)
}

fn services_source() string {
	return method('private static service(Landroid/content/Context;)V', 5, '
const-string v0, "usagestats"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
const/4 v1, 0
const-string v2, "legacy usagestats string discovery must remain unavailable"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v3
const-string v4, "org.vinix.bootstrap"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
const-string v2, "own package argument must come from the actual fixture context"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
const-class v0, ${manager_type}
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
check-cast v0, ${manager_type}
invoke-static {v0, v3}, ${main_type}->query(${manager_type}Ljava/lang/String;)V
const-class v0, ${manager_type}
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
check-cast v0, ${manager_type}
invoke-static {v0, v3}, ${main_type}->query(${manager_type}Ljava/lang/String;)V
const-string v0, "usagestats"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
const/4 v1, 0
const-string v2, "queries must preserve legacy usagestats string discovery"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + shape_source() + query_source() + services_source() +
		method('private static run(Landroid/content/Context;)V', 3, '
invoke-static {}, ${main_type}->publicInstanceQuery()V
invoke-static {p0}, ${main_type}->service(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, ${main_type}->service(Landroid/content/Context;)V
new-instance v0, ${manager_type}
invoke-direct {v0}, ${manager_type}-><init>()V
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
invoke-static {v0, v1}, ${main_type}->query(${manager_type}Ljava/lang/String;)V
invoke-static {p0}, ${main_type}->service(Landroid/content/Context;)V
return-void') + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->run(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Disabled usage-inactivity query passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
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

fn verify_source_references(source string) {
	assert source.starts_with('.class public final ${main_type}'), 'exact fixture class required'
	for reference in ['${manager_type}->${query_signature}', '${manager_type}-><init>()V',
		'->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;', '->getSystemService(Ljava/lang/String;)Ljava/lang/Object;',
		'"usagestats"', '"com.google.android.gms"', '"com.google.android.apps.maps"',
		'"org.vinix.no_such_package.usage"', 'Ljava/lang/Boolean;->TYPE:Ljava/lang/Class;',
		'${main_type}->query(', '${main_type}->service('] {
		assert source.contains(reference), 'missing actual usage query assertion: ' + reference
	}
	assert source.contains('"org.vinix.使用.Δ"')
		|| source.to_lower().contains('"org.vinix.\\u4f7f\\u7528.\\u0394"'), 'Unicode argument must survive canonical escaping'
	assert source.count('${manager_type}->${query_signature}') == 7, 'all seven actual argument paths required'
	assert !source.contains('.class public final Landroid/'), 'fixture must not supply a platform stub'
}
