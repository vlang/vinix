// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// Values describe installed authenticators; the native query owns discovery.
// Contract: AOSP android-14.0.0_r1 core/java/android/accounts/AuthenticatorDescription.java.
pub fn framework_authenticator_descriptions(source string) !string {
	mut classes := []string{}
	for line in source.split_into_lines() {
		if line.trim_space().starts_with('.class ') { classes << line.trim_space() }
	}
	if classes.len != 1 || !classes[0].ends_with(' Landroid/accounts/AccountManager;') {
		return error('expected AccountManager class')
	}
	signature := 'getAuthenticatorTypes()[Landroid/accounts/AuthenticatorDescription;'
	return framework_replace_method(source, signature,
		'.method public native ' + signature + '\n.end method')!
}

fn authenticator_description_method(signature string, locals int, body string) string {
	return '\n.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

pub fn framework_authenticator_description_classes() map[string]string {
	cls := 'Landroid/accounts/AuthenticatorDescription;'
	creator := 'Landroid/accounts/AuthenticatorDescription$Creator;'
	full := '(Ljava/lang/String;Ljava/lang/String;IIIIZ)V'
	mut value := '.class public ' + cls + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
		'.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n'
	for name in ['type', 'packageName'] {
		value += '.field public final ' + name + ':Ljava/lang/String;\n'
	}
	for name in ['labelId', 'iconId', 'smallIconId', 'accountPreferencesId'] {
		value += '.field public final ' + name + ':I\n'
	}
	value += '.field public final customTokens:Z\n'
	value += authenticator_description_method('static constructor <clinit>()V', 1,
		'new-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\n' +
		'sput-object v0, ' + cls + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
	value += authenticator_description_method('public constructor <init>(Ljava/lang/String;Ljava/lang/String;IIII)V', 8,
		'move-object v0, p0\nmove-object v1, p1\nmove-object v2, p2\nmove v3, p3\nmove v4, p4\nmove v5, p5\nmove v6, p6\nconst/4 v7, 0x0\n' +
		'invoke-direct/range {v0 .. v7}, ' + cls + '-><init>' + full + '\nreturn-void')
	mut construct := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
		'if-eqz p1, :bad_type\nif-eqz p2, :bad_package\n' +
		'iput-object p1, p0, ' + cls + '->type:Ljava/lang/String;\niput-object p2, p0, ' + cls + '->packageName:Ljava/lang/String;\n'
	for i, name in ['labelId', 'iconId', 'smallIconId', 'accountPreferencesId'] {
		construct += 'iput p' + (i + 3).str() + ', p0, ' + cls + '->' + name + ':I\n'
	}
	construct += 'iput-boolean p7, p0, ' + cls + '->customTokens:Z\nreturn-void\n' +
		':bad_type\nconst-string v1, "type cannot be null"\ngoto :throw_invalid\n' +
		':bad_package\nconst-string v1, "packageName cannot be null"\n' +
		':throw_invalid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0'
	value += authenticator_description_method('public constructor <init>' + full, 2, construct)
	mut key := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + cls + '->type:Ljava/lang/String;\n' +
		'const/4 v0, 0x0\niput-object v0, p0, ' + cls + '->packageName:Ljava/lang/String;\n'
	for name in ['labelId', 'iconId', 'smallIconId', 'accountPreferencesId'] {
		key += 'iput v0, p0, ' + cls + '->' + name + ':I\n'
	}
	key += 'iput-boolean v0, p0, ' + cls + '->customTokens:Z\nreturn-void'
	value += authenticator_description_method('private constructor <init>(Ljava/lang/String;)V', 1, key)
	value += authenticator_description_method('public static newKey(Ljava/lang/String;)' + cls, 2,
		'if-nez p0, :valid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\n' +
		'const-string v1, "type cannot be null"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n' +
		'new-instance v0, ' + cls + '\ninvoke-direct {v0, p0}, ' + cls + '-><init>(Ljava/lang/String;)V\nreturn-object v0')
	mut read := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	mut write := ''
	for name in ['type', 'packageName'] {
		read += 'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, ' + cls + '->' + name + ':Ljava/lang/String;\n'
		write += 'iget-object v0, p0, ' + cls + '->' + name + ':Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
	}
	for name in ['labelId', 'iconId', 'smallIconId', 'accountPreferencesId'] {
		read += 'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\niput v0, p0, ' + cls + '->' + name + ':I\n'
		write += 'iget v0, p0, ' + cls + '->' + name + ':I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n'
	}
	read += 'invoke-virtual {p1}, Landroid/os/Parcel;->readByte()B\nmove-result v0\nconst/4 v1, 0x1\nif-eq v0, v1, :custom\nconst/4 v1, 0x0\n:custom\niput-boolean v1, p0, ' + cls + '->customTokens:Z\nreturn-void'
	write += 'iget-boolean v0, p0, ' + cls + '->customTokens:Z\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeByte(B)V\nreturn-void'
	// Package access lets the generated creator call the parcel constructor
	// without a compiler-generated synthetic accessor or another public API.
	value += authenticator_description_method('constructor <init>(Landroid/os/Parcel;)V', 2, read)
	value += authenticator_description_method('public writeToParcel(Landroid/os/Parcel;I)V', 1, write)
	value += authenticator_description_method('public describeContents()I', 1, 'const/4 v0, 0x0\nreturn v0')
	value += authenticator_description_method('public hashCode()I', 1,
		'iget-object v0, p0, ' + cls + '->type:Ljava/lang/String;\ninvoke-virtual {v0}, Ljava/lang/String;->hashCode()I\nmove-result v0\nreturn v0')
	value += authenticator_description_method('public equals(Ljava/lang/Object;)Z', 2,
		'if-eq p0, p1, :same\ninstance-of v0, p1, ' + cls + '\nif-eqz v0, :different\ncheck-cast p1, ' + cls + '\n' +
		'iget-object v0, p0, ' + cls + '->type:Ljava/lang/String;\niget-object v1, p1, ' + cls + '->type:Ljava/lang/String;\n' +
		'invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n' +
		':same\nconst/4 v0, 0x1\nreturn v0\n:different\nconst/4 v0, 0x0\nreturn v0')
	value += authenticator_description_method('public toString()Ljava/lang/String;', 2,
		'new-instance v0, Ljava/lang/StringBuilder;\nconst-string v1, "AuthenticatorDescription {type="\n' +
		'invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\n' +
		'iget-object v1, p0, ' + cls + '->type:Ljava/lang/String;\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
		'const-string v1, "}"\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
		'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nreturn-object v0')
	creator_source := '.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
		authenticator_description_method('public constructor <init>()V', 0,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		authenticator_description_method('public createFromParcel(Landroid/os/Parcel;)' + cls, 1,
			'new-instance v0, ' + cls + '\ninvoke-direct {v0, p1}, ' + cls + '-><init>(Landroid/os/Parcel;)V\nreturn-object v0') +
		authenticator_description_method('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 1,
			'invoke-virtual {p0, p1}, ' + creator + '->createFromParcel(Landroid/os/Parcel;)' + cls + '\nmove-result-object v0\nreturn-object v0') +
		authenticator_description_method('public newArray(I)[' + cls, 1,
			'new-array v0, p1, [' + cls + '\nreturn-object v0') +
		authenticator_description_method('public bridge synthetic newArray(I)[Ljava/lang/Object;', 1,
			'invoke-virtual {p0, p1}, ' + creator + '->newArray(I)[' + cls + '\nmove-result-object v0\nreturn-object v0')
	return {'android/accounts/AuthenticatorDescription': value,
		'android/accounts/AuthenticatorDescription$Creator': creator_source}
}
