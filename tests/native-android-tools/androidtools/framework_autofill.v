// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// AutofillValue is also used as an ordinary typed value by Compose semantics,
// independently of an installed autofill service.
fn framework_autofill(smali string) ! {
	owner := 'Landroid/view/autofill/AutofillValue;'
	creator := 'Landroid/view/autofill/VinixAutofillValueCreator;'
	mut text := '.class public final ' + owner + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
		'.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n.field private final type:I\n.field private final value:Ljava/lang/Object;\n'
	text += signature_method('private constructor <init>(ILjava/lang/Object;)V',
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ' + owner + '->type:I\niput-object p2, p0, ' + owner + '->value:Ljava/lang/Object;\nreturn-void')
	text += signature_method('static constructor <clinit>()V', 'new-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\nsput-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
	text += signature_method('private checkType(I)V', 'iget v0, p0, ' + owner + '->type:I\nif-eq v0, p1, :ok\nnew-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "AutofillValue has a different type"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n:ok\nreturn-void')
	mut write := 'iget v0, p0, ' + owner + '->type:I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n'
	mut read := 'invoke-virtual {p0}, Landroid/os/Parcel;->readInt()I\nmove-result v0\n'
	for i, name in ['Text', 'Toggle', 'List', 'Date'] {
		type_id := (i + 1).str()
		kind := ['Ljava/lang/CharSequence;', 'Z', 'I', 'J'][i]
		boxed := ['Ljava/lang/CharSequence;', 'Ljava/lang/Boolean;', 'Ljava/lang/Integer;',
			'Ljava/lang/Long;'][i]
		wide := if kind == 'J' { ', p1' } else { '' }
		mut factory := ''
		if i == 0 {
			factory = 'if-nez p0, :non_null\nconst/4 v0, 0\nreturn-object v0\n:non_null\nmove-object v0, p0\n' +
				'instance-of v1, p0, Landroid/text/Spanned;\nif-eqz v1, :text_ready\nnew-instance v0, Landroid/text/SpannableStringBuilder;\ninvoke-direct {v0, p0}, Landroid/text/SpannableStringBuilder;-><init>(Ljava/lang/CharSequence;)V\n:text_ready\n'
		} else {
			factory = 'invoke-static {p0' + wide + '}, ' + boxed + '->valueOf(' + kind + ')' + boxed + '\nmove-result-object v0\n'
		}
		text += signature_method('public static for' + name + '(' + kind + ')' + owner,
			factory + 'const/4 v1, ' + type_id + '\nnew-instance v2, ' + owner + '\ninvoke-direct {v2, v1, v0}, ' + owner + '-><init>(ILjava/lang/Object;)V\nreturn-object v2')
		text += signature_method('public is' + name + '()Z', 'iget v0, p0, ' + owner + '->type:I\nconst/4 v1, ' + type_id + '\nif-eq v0, v1, :yes\nconst/4 v0, 0\nreturn v0\n:yes\nconst/4 v0, 1\nreturn v0')
		mut getter := 'const/4 v0, ' + type_id + '\ninvoke-direct {p0, v0}, ' + owner + '->checkType(I)V\niget-object v0, p0, ' + owner + '->value:Ljava/lang/Object;\ncheck-cast v0, ' + boxed + '\n'
		if i == 0 {
			getter += 'return-object v0'
		} else {
			getter += 'invoke-virtual {v0}, ' + boxed + '->' + ['', 'booleanValue', 'intValue',
				'longValue'][i] + '()' + kind + '\nmove-result' + if i == 3 { '-wide' } else { '' } + ' v0\nreturn' + if i == 3 {
				'-wide'
			} else {
				''
			} + ' v0'
		}
		text += signature_method('public get' + name + 'Value()' + kind, getter)
		write += 'const/4 v1, ' + type_id + '\nif-ne v0, v1, :write_next_' + type_id + '\ninvoke-virtual {p0}, ' + owner + '->get' + name + 'Value()' + kind + '\nmove-result' + if i == 0 {
			'-object'
		} else if i == 3 {
			'-wide'
		} else {
			''
		} + ' v2\n'
		if i == 0 {
			// TextUtils' unspanned CharSequence parcel representation: kind=1, String.
			write += 'const/4 v1, 1\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-interface {v2}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v2\ninvoke-virtual {p1, v2}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
		} else {
			write += 'invoke-virtual {p1, v2' + if i == 3 { ', v3' } else { '' } + '}, Landroid/os/Parcel;->write' + if i == 3 {
				'Long(J)'
			} else {
				'Int(I)'
			} + 'V\n'
		}
		write += 'return-void\n:write_next_' + type_id + '\n'
		read += 'const/4 v1, ' + type_id + '\nif-ne v0, v1, :read_next_' + type_id + '\n'
		if i == 0 {
			read += 'invoke-virtual {p0}, Landroid/os/Parcel;->readInt()I\nmove-result v1\nconst/4 v2, 1\nif-ne v1, v2, :invalid\ninvoke-virtual {p0}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v2\n'
		} else {
			read += 'invoke-virtual {p0}, Landroid/os/Parcel;->read' + if i == 3 {
				'Long()J\nmove-result-wide'
			} else {
				'Int()I\nmove-result'
			} + ' v2\n'
			if i == 1 { read += 'if-eqz v2, :toggle_ready\nconst/4 v2, 1\n:toggle_ready\n' }
		}
		read += 'invoke-static {v2' + if i == 3 { ', v3' } else { '' } + '}, ' + owner + '->for' + name + '(' + kind + ')' + owner + '\nmove-result-object v0\nreturn-object v0\n:read_next_' + type_id + '\n'
	}
	text += signature_method('public isEmpty()Z', 'invoke-virtual {p0}, ' + owner + '->isText()Z\nmove-result v0\nif-eqz v0, :no\ninvoke-virtual {p0}, ' + owner + '->getTextValue()Ljava/lang/CharSequence;\nmove-result-object v0\ninvoke-interface {v0}, Ljava/lang/CharSequence;->length()I\nmove-result v0\nif-nez v0, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	text += signature_method('public equals(Ljava/lang/Object;)Z', 'if-eq p0, p1, :yes\ninstance-of v0, p1, ' + owner + '\nif-eqz v0, :no\ncheck-cast p1, ' + owner + '\niget v0, p0, ' + owner + '->type:I\niget v1, p1, ' + owner + '->type:I\nif-ne v0, v1, :no\niget-object v1, p0, ' + owner + '->value:Ljava/lang/Object;\niget-object v2, p1, ' + owner + '->value:Ljava/lang/Object;\nconst/4 v3, 1\nif-ne v0, v3, :compare\ninvoke-virtual {v1}, Ljava/lang/Object;->toString()Ljava/lang/String;\nmove-result-object v1\ninvoke-virtual {v2}, Ljava/lang/Object;->toString()Ljava/lang/String;\nmove-result-object v2\n:compare\ninvoke-virtual {v1, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n:yes\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	text += signature_method('public hashCode()I', 'iget-object v0, p0, ' + owner + '->value:Ljava/lang/Object;\niget v1, p0, ' + owner + '->type:I\nconst/4 v2, 1\nif-ne v1, v2, :hash\ninvoke-virtual {v0}, Ljava/lang/Object;->toString()Ljava/lang/String;\nmove-result-object v0\n:hash\ninvoke-virtual {v0}, Ljava/lang/Object;->hashCode()I\nmove-result v0\nadd-int/2addr v0, v1\nreturn v0')
	text += signature_method('public describeContents()I', 'const/4 v0, 0\nreturn v0')
	text += signature_method('public writeToParcel(Landroid/os/Parcel;I)V', write + 'return-void')
	text += signature_method('public static vinixReadFromParcel(Landroid/os/Parcel;)' + owner, read + ':invalid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "Invalid AutofillValue parcel type"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0')
	os.mkdir_all(smali + '/android/view/autofill')!
	os.write_file(smali + '/android/view/autofill/AutofillValue.smali', text)!
	os.write_file(smali + '/android/view/autofill/VinixAutofillValueCreator.smali', '.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
		signature_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		signature_method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'invoke-static {p1}, ' + owner + '->vinixReadFromParcel(Landroid/os/Parcel;)' + owner + '\nmove-result-object v0\nreturn-object v0') +
		signature_method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [' + owner + '\nreturn-object v0'))!
}
