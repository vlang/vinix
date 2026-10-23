// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_autofill_probe(dir string) ! {
	value := 'Landroid/view/autofill/AutofillValue;'
	probe := 'Lorg/vinix/bootstrap/AutofillProbe;'
	factory := 'Lorg/vinix/bootstrap/AutofillToggleFactory;'
	os.write_file(dir + '/AutofillToggleFactory.smali', '.class public ${factory}\n.super Ljava/lang/Object;\n' +
		method('public static make(Z)${value}',
			'invoke-static {p0}, ${value}->forToggle(Z)${value}\nmove-result-object v0\nreturn-object v0'))!
	mut check := ''
	mut helpers := ''
	for i, name in ['Text', 'Toggle', 'List', 'Date'] {
		kind := ['Ljava/lang/CharSequence;', 'Z', 'I', 'J'][i]
		wide := if i == 3 { ', v2' } else { '' }
		init := ['const-string v1, " main street "', 'const/4 v1, 1', 'const/4 v1, 7',
			'const-wide v1, 0x123456789abL'][i]
		owner := if i == 1 { factory } else { value }
		factory_name := if i == 1 { 'make' } else { 'for' + name }
		check += '${init}\ninvoke-static {v1${wide}}, ${owner}->${factory_name}(${kind})${value}\nmove-result-object v0\n' +
			'invoke-static {v0}, ${probe}->roundTrip(${value})${value}\nmove-result-object v0\n' +
			'invoke-static {v0, v1${wide}}, ${probe}->expect${name}(${value}${kind})V\n'
		if i == 1 {
			// Maps creates both values through a separate API outline wrapper.
			check += 'const/4 v1, 0\ninvoke-static {v1}, ${factory}->make(Z)${value}\nmove-result-object v0\n' +
				'invoke-static {v0}, ${probe}->roundTrip(${value})${value}\nmove-result-object v0\n' +
				'invoke-static {v0, v1}, ${probe}->expectToggle(${value}Z)V\n' +
				'invoke-static {v1}, ${value}->forList(I)${value}\nmove-result-object v2\n' +
				'invoke-virtual {v0, v2}, ${value}->equals(Ljava/lang/Object;)Z\nmove-result v2\nif-nez v2, :bad\n'
		}
		mut expect := ''
		for other in ['Text', 'Toggle', 'List', 'Date'] {
			expect += 'invoke-virtual {p0}, ${value}->is${other}()Z\nmove-result v0\n' +
				if name == other { 'if-eqz v0, :bad\n' } else { 'if-nez v0, :bad\n' }
		}
		expect += 'invoke-virtual {p0}, ${value}->isEmpty()Z\nmove-result v0\nif-nez v0, :bad\n' +
			'invoke-virtual {p0}, ${value}->get${name}Value()${kind}\n'
		if i == 0 {
			expect += 'move-result-object v0\ninvoke-virtual {p1, v0}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\n'
		} else if i == 3 {
			expect += 'move-result-wide v0\ncmp-long v0, v0, p1\nif-nez v0, :bad\n'
		} else {
			expect += 'move-result v0\nif-ne v0, p1, :bad\n'
		}
		wrong_name := ['Toggle', 'Text', 'Date', 'List'][i]
		wrong_kind := ['Z', 'Ljava/lang/CharSequence;', 'J', 'I'][i]
		expect += ':wrong_start\ninvoke-virtual {p0}, ${value}->get${wrong_name}Value()${wrong_kind}\n:wrong_end\ngoto :bad\n' +
			'.catch Ljava/lang/IllegalStateException; {:wrong_start .. :wrong_end} :caught\n:caught\nmove-exception v0\nreturn-void\n' +
			':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "AutofillValue ${name} value, type, emptiness and wrong-getter contract"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
		helpers += method('private static expect${name}(${value}${kind})V', expect)
	}
	check += 'const/4 v0, 0\ninvoke-static {v0}, ${value}->forText(Ljava/lang/CharSequence;)${value}\nmove-result-object v0\nif-nez v0, :bad\n' +
		'const-string v0, ""\ninvoke-static {v0}, ${value}->forText(Ljava/lang/CharSequence;)${value}\nmove-result-object v0\n' +
		'invoke-static {v0}, ${probe}->roundTrip(${value})${value}\nmove-result-object v0\n' +
		'invoke-virtual {v0}, ${value}->isText()Z\nmove-result v1\nif-eqz v1, :bad\n' +
		'invoke-virtual {v0}, ${value}->isEmpty()Z\nmove-result v1\nif-eqz v1, :bad\n' +
		'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-AUTOFILL-PASS toggle-wrapper true false typed-values parcel equality wrong-getters null-text empty-text"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n' +
		':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "AutofillValue factory and empty contract"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	helper := method('private static roundTrip(${value})${value}', '
invoke-virtual {p0}, ${value}->describeContents()I
move-result v0
if-nez v0, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-interface {p0, v0, v1}, Landroid/os/Parcelable;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v2, ${value}->CREATOR:Landroid/os/Parcelable\$Creator;
invoke-interface {v2, v0}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v3
check-cast v3, ${value}
invoke-virtual {p0, v3}, ${value}->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v3, p0}, ${value}->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {p0}, ${value}->hashCode()I
move-result v4
invoke-virtual {v3}, ${value}->hashCode()I
move-result v5
if-ne v4, v5, :bad
const/4 v4, 2
invoke-interface {v2, v4}, Landroid/os/Parcelable\$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v2
check-cast v2, [${value}
array-length v5, v2
if-ne v4, v5, :bad
aget-object v5, v2, v1
if-nez v5, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-object v3
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "AutofillValue Parcelable interface, equality, hash and creator contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	os.write_file(dir + '/AutofillProbe.smali', '.class public ${probe}\n.super Ljava/lang/Object;\n' +
		method('public static check()V', check) + helpers + helper)!
}
