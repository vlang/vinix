// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const build_type = 'Landroid/os/Build;'
const properties_type = 'Landroid/os/SystemProperties;'
const pass_marker = 'BUILD-ABIS-PASS measured-arm64 public-static-final ordered-arrays empty-32 independent-mutable stable-fields fresh-helper custom-property-restored'
const fail_marker = 'BUILD-ABIS-FAIL'
const fixture_scope = 'Standalone real Process.is64Bit and os.arch observations, Build ABI array public/static/final String[] linkage and aarch64 values, CPU primary/secondary and property consistency, stable distinct public arrays with finally-restored element mutation, and the private property-list helper empty/missing/order/separator/fresh-array behavior. Only a unique fixture property is changed through reflection of the existing process-local Properties and restored with its exact prior presence/Object. No real CPU capability property, Build.VERSION, SDK override, platform stub, 32-bit execution, Google module completion, account or authentication success is supplied.'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn helpers_source() string {
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
return-void') + method('private static different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static text(Ljava/lang/Object;Ljava/lang/String;)V', 2, '
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1, p1}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static array([Ljava/lang/String;[Ljava/lang/String;)V', 6, '
array-length v0, p0
array-length v1, p1
const-string v5, "exact ABI array length and ordered values required"
invoke-static {v0, v1, v5}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v2, 0
:next
if-ge v2, v0, :done
aget-object v3, p0, v2
aget-object v4, p1, v2
invoke-static {v3, v4}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
add-int/lit8 v2, v2, 1
goto :next
:done
return-void') + method('private static one([Ljava/lang/String;Ljava/lang/String;)V', 3, '
array-length v0, p0
const/4 v1, 1
const-string v2, "ARM ABI arrays must contain exactly one supported ABI"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v0, 0
aget-object v0, p0, v0
invoke-static {v0, p1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
return-void') + method('private static empty([Ljava/lang/String;)V', 3, '
array-length v0, p0
const/4 v1, 0
const-string v2, "empty ABI value must produce a zero-length String array"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn measure_source() string {
	return method('private static measure()V', 5, '
const-string v0, "os.arch"
invoke-static {v0}, Ljava/lang/System;->getProperty(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-static {}, Landroid/os/Process;->is64Bit()Z
move-result v1
new-instance v2, Ljava/lang/StringBuilder;
invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
const-string v3, "BUILD-ABIS-OBSERVATION os.arch="
invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v2, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v3, " process64="
invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Z)Ljava/lang/StringBuilder;
invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v2
sget-object v3, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v3, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v3}, Ljava/io/PrintStream;->flush()V
const-string v2, "aarch64"
invoke-static {v0, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const/4 v2, 1
const-string v3, "the actual fixture process must be 64 bit"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn shape_source() string {
	mut body := method('private static fieldShape(Ljava/lang/String;)V', 5, '
const-class v0, ${build_type}
invoke-virtual {v0, p0}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getDeclaringClass()Ljava/lang/Class;
move-result-object v2
const-string v4, "ABI fields must be declared by Build"
invoke-static {v2, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getType()Ljava/lang/Class;
move-result-object v2
const-class v3, [Ljava/lang/String;
const-string v4, "ABI fields must have exact String-array type"
invoke-static {v2, v3, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getModifiers()I
move-result v2
and-int/lit8 v2, v2, 0x19
const/16 v3, 0x19
const-string v4, "ABI array fields must be public static final"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
	mut fields := ''
	for name in ['SUPPORTED_ABIS', 'SUPPORTED_64_BIT_ABIS', 'SUPPORTED_32_BIT_ABIS'] {
		fields += 'const-string v0, "${name}"\ninvoke-static {v0}, ${main_type}->fieldShape(Ljava/lang/String;)V\n'
	}
	body += method('private static shapes()V', 1, fields + 'return-void')
	return body
}

fn baseline_source() string {
	mut body := '
sget-object v0, ${build_type}->SUPPORTED_ABIS:[Ljava/lang/String;
sget-object v1, ${build_type}->SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;
sget-object v2, ${build_type}->SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;
const-string v3, "arm64-v8a"
invoke-static {v0, v3}, ${main_type}->one([Ljava/lang/String;Ljava/lang/String;)V
invoke-static {v1, v3}, ${main_type}->one([Ljava/lang/String;Ljava/lang/String;)V
invoke-static {v2}, ${main_type}->empty([Ljava/lang/String;)V
const-string v4, "each public ABI array must be a distinct object"
invoke-static {v0, v1, v4}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v0, v2, v4}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v1, v2, v4}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	for index, name in ['SUPPORTED_ABIS', 'SUPPORTED_64_BIT_ABIS', 'SUPPORTED_32_BIT_ABIS'] {
		body += 'sget-object v4, ${build_type}->${name}:[Ljava/lang/String;\nconst-string v5, "initialized static ABI fields must keep their array identity"\ninvoke-static {v${index}, v4, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
	}
	body += '
sget-object v4, ${build_type}->CPU_ABI:Ljava/lang/String;
invoke-static {v4, v3}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
sget-object v4, ${build_type}->CPU_ABI2:Ljava/lang/String;
const-string v5, ""
invoke-static {v4, v5}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
'
	for key, value in {'ro.product.cpu.abi': 'arm64-v8a', 'ro.product.cpu.abi2': '',
		'ro.product.cpu.abilist': 'arm64-v8a', 'ro.product.cpu.abilist64': 'arm64-v8a',
		'ro.product.cpu.abilist32': ''} {
		body += 'const-string v4, "${key}"\nconst-string v5, "fixture-missing-property"\ninvoke-static {v4, v5}, ${properties_type}->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v4\nconst-string v5, "${value}"\ninvoke-static {v4, v5}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V\n'
	}
	body += 'return-void'
	return method('private static baseline()V', 6, body)
}

fn restore_arrays_source() string {
	return method('private static restoreArrays([Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)V', 2, '
:try_start
const/4 v0, 0
aput-object p1, p0, v0
aput-object p3, p2, v0
:try_end
goto :primary
:failed
move-exception v0
if-eqz p4, :cleanup_only
if-eq p4, v0, :primary
invoke-virtual {p4, v0}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
goto :primary
:cleanup_only
throw v0
:primary
if-eqz p4, :done
throw p4
:done
return-void
.catchall {:try_start .. :try_end} :failed') + method('private static mutableArrays()V', 7, '
sget-object v0, ${build_type}->SUPPORTED_ABIS:[Ljava/lang/String;
sget-object v1, ${build_type}->SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;
const/4 v4, 0
aget-object v2, v0, v4
aget-object v3, v1, v4
:try_start
const-string v5, "fixture-mutated-all"
aput-object v5, v0, v4
const-string v5, "arm64-v8a"
invoke-static {v1, v5}, ${main_type}->one([Ljava/lang/String;Ljava/lang/String;)V
aput-object v2, v0, v4
const-string v5, "fixture-mutated-64"
aput-object v5, v1, v4
const-string v5, "arm64-v8a"
invoke-static {v0, v5}, ${main_type}->one([Ljava/lang/String;Ljava/lang/String;)V
sget-object v5, ${build_type}->CPU_ABI:Ljava/lang/String;
invoke-static {v5, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v5, "ro.product.cpu.abilist64"
const-string v6, "fixture-missing-property"
invoke-static {v5, v6}, ${properties_type}->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
invoke-static {v5, v3}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
:try_end
const/4 v6, 0
invoke-static {v0, v2, v1, v3, v6}, ${main_type}->restoreArrays([Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)V
return-void
:failed
move-exception v6
invoke-static {v0, v2, v1, v3, v6}, ${main_type}->restoreArrays([Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn reflection_source() string {
	return method('private static propertyMap()Ljava/util/Properties;', 3, '
const-class v0, ${properties_type}
const-string v1, "properties"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/util/Properties;
return-object v0') + method('private static helper()Ljava/lang/reflect/Method;', 5, '
const/4 v0, 2
new-array v0, v0, [Ljava/lang/Class;
const-class v1, Ljava/lang/String;
const/4 v2, 0
aput-object v1, v0, v2
const/4 v2, 1
aput-object v1, v0, v2
const-class v1, ${build_type}
const-string v2, "getStringList"
invoke-virtual {v1, v2, v0}, Ljava/lang/Class;->getDeclaredMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v1
and-int/lit8 v1, v1, 0xa
const/16 v2, 0xa
const-string v4, "the property-list helper must remain private static"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
const-class v2, [Ljava/lang/String;
const-string v4, "the private helper must return String array"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Method;->setAccessible(Z)V
return-object v0') + method('private static parse(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;', 4, '
const/4 v0, 2
new-array v0, v0, [Ljava/lang/Object;
const/4 v1, 0
aput-object p1, v0, v1
const/4 v1, 1
aput-object p2, v0, v1
const/4 v1, 0
invoke-virtual {p0, v1, v0}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, [Ljava/lang/String;
return-object v0') + method('private static parsed(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;)V', 4, '
invoke-static {p0, p1, p2}, ${main_type}->parse(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
invoke-static {v0, p3}, ${main_type}->array([Ljava/lang/String;[Ljava/lang/String;)V
invoke-static {p0, p1, p2}, ${main_type}->parse(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v1
const-string v2, "helper calls must return independent arrays including empties"
invoke-static {v0, v1, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
array-length v2, v0
if-eqz v2, :done
const/4 v2, 0
const-string v3, "fixture-mutated-helper"
aput-object v3, v0, v2
invoke-static {v1, p3}, ${main_type}->array([Ljava/lang/String;[Ljava/lang/String;)V
invoke-static {p0, p1, p2}, ${main_type}->parse(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v2
invoke-static {v2, p3}, ${main_type}->array([Ljava/lang/String;[Ljava/lang/String;)V
:done
return-void')
}

fn restore_property_source() string {
	return method('private static restoreProperty(Ljava/util/Properties;Ljava/lang/String;Ljava/lang/Object;ZLjava/lang/Throwable;)V', 3, '
:try_start
if-eqz p3, :remove
invoke-virtual {p0, p1, p2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
goto :verify
:remove
invoke-virtual {p0, p1}, Ljava/util/Properties;->remove(Ljava/lang/Object;)Ljava/lang/Object;
:verify
invoke-virtual {p0, p1}, Ljava/util/Properties;->containsKey(Ljava/lang/Object;)Z
move-result v0
const-string v2, "fixture property presence must be restored exactly"
invoke-static {v0, p3, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0, p1}, Ljava/util/Properties;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
const-string v2, "fixture property must restore the exact prior Object"
invoke-static {v0, p2, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
:try_end
goto :primary
:failed
move-exception v0
if-eqz p4, :cleanup_only
if-eq p4, v0, :primary
invoke-virtual {p4, v0}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
goto :primary
:cleanup_only
throw v0
:primary
if-eqz p4, :done
throw p4
:done
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn expected_array(values []string) string {
	mut body := 'const/16 v5, ${values.len}\nnew-array v5, v5, [Ljava/lang/String;\n'
	for index, value in values {
		body += 'const/16 v6, ${index}\nconst-string v7, "${value}"\naput-object v7, v5, v6\n'
	}
	return body
}

fn property_cases_source() string {
	mut body := '
invoke-static {}, ${main_type}->helper()Ljava/lang/reflect/Method;
move-result-object v0
invoke-static {}, ${main_type}->propertyMap()Ljava/util/Properties;
move-result-object v1
const-string v2, "vinix.fixture.build_abis.list"
invoke-virtual {v1, v2}, Ljava/util/Properties;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v3
invoke-virtual {v1, v2}, Ljava/util/Properties;->containsKey(Ljava/lang/Object;)Z
move-result v4
:try_start
invoke-virtual {v1, v2}, Ljava/util/Properties;->remove(Ljava/lang/Object;)Ljava/lang/Object;
'
	body += expected_array([]string{}) + 'const-string v6, ","\ninvoke-static {v0, v2, v6, v5}, ${main_type}->parsed(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;)V\n'
	for value in ['', 'first,second,third', ',first,,second,', ' first ,second', 'first;second;third'] {
		body += 'const-string v7, "${value}"\ninvoke-virtual {v1, v2, v7}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n'
		values := match value {
			'' { []string{} }
			',first,,second,' { ['', 'first', '', 'second'] }
			' first ,second' { [' first ', 'second'] }
			else { ['first', 'second', 'third'] }
		}
		separator := if value.contains(';') { ';' } else { ',' }
		body += expected_array(values) + 'const-string v6, "${separator}"\ninvoke-static {v0, v2, v6, v5}, ${main_type}->parsed(Ljava/lang/reflect/Method;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;)V\n'
	}
	body += '
:try_end
const/4 v7, 0
invoke-static {v1, v2, v3, v4, v7}, ${main_type}->restoreProperty(Ljava/util/Properties;Ljava/lang/String;Ljava/lang/Object;ZLjava/lang/Throwable;)V
return-void
:failed
move-exception v7
invoke-static {v1, v2, v3, v4, v7}, ${main_type}->restoreProperty(Ljava/util/Properties;Ljava/lang/String;Ljava/lang/Object;ZLjava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed'
	return method('private static properties()V', 8, body)
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		helpers_source() + measure_source() + shape_source() + baseline_source() + restore_arrays_source() +
		reflection_source() + restore_property_source() + property_cases_source() +
		method('private static run()V', 0, '
invoke-static {}, ${main_type}->measure()V
invoke-static {}, ${main_type}->shapes()V
invoke-static {}, ${main_type}->baseline()V
invoke-static {}, ${main_type}->mutableArrays()V
invoke-static {}, ${main_type}->baseline()V
invoke-static {}, ${main_type}->properties()V
invoke-static {}, ${main_type}->baseline()V
return-void') + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {}, ${main_type}->run()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Build ABI arrays and independent property lists passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2
.catchall {:try_start .. :try_end} :failed')}
}

fn expected_classes() []string { return ['org/vinix/bootstrap/Main.smali'] }

fn verify_source_references(source string) {
	assert source.starts_with('.class public final ${main_type}'), 'one actual fixture Activity required'
	for name in ['SUPPORTED_ABIS', 'SUPPORTED_64_BIT_ABIS', 'SUPPORTED_32_BIT_ABIS'] {
		assert source.contains('${build_type}->${name}:[Ljava/lang/String;'), 'missing actual ABI field: ' + name
	}
	for reference in ['Landroid/os/Process;->is64Bit()Z', '"os.arch"', '"BUILD-ABIS-OBSERVATION os.arch="',
		'${build_type}->CPU_ABI:Ljava/lang/String;', '${build_type}->CPU_ABI2:Ljava/lang/String;',
		'"getStringList"', '"properties"', '"vinix.fixture.build_abis.list"',
		'"ro.product.cpu.abilist64"', '"ro.product.cpu.abilist32"', 'Ljava/lang/reflect/Method;->invoke(',
		'${main_type}->restoreArrays(', '${main_type}->restoreProperty(', '->addSuppressed(',
		'"fixture-mutated-all"', '"fixture-mutated-64"', '"fixture-mutated-helper"'] {
		assert source.contains(reference), 'missing Build ABI fixture assertion: ' + reference
	}
	assert !source.contains('${properties_type}->set(') && !source.contains('Ljava/lang/System;->setProperty(')
		&& !source.contains('Build$VERSION;'), 'no new setter, architecture override or SDK mutation permitted'
}
