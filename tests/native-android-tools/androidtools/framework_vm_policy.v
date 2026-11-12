// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Preserve VM policy configuration across the builder/copy/get/set API. VM
// leak detection still needs runtime instrumentation; this is not a detector.
pub fn framework_vm_policy(smali string) ! {
	p := 'Landroid/os/StrictMode$VmPolicy;'
	b := 'Landroid/os/StrictMode$VmPolicy$Builder;'
	l := 'Landroid/os/StrictMode$OnVmViolationListener;'
	e := 'Ljava/util/concurrent/Executor;'
	m := 'Ljava/util/HashMap;'
	ctor := '(I' + m + l + e + ')V'
	fields := '.field mask:I\n.field limits:' + m + '\n.field listener:' + l + '\n.field executor:' + e + '\n'
	mut source := '.class public final ' + p + '\n.super Ljava/lang/Object;\n' +
		'.field public static final LAX:' + p + '\n' + fields.replace('.field ', '.field final ')
	source += signature_method('constructor <init>' + ctor,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ' + p + '->mask:I\n' +
		'new-instance v0, ' + m + '\ninvoke-direct {v0, p2}, ' + m + '-><init>(Ljava/util/Map;)V\niput-object v0, p0, ' + p + '->limits:' + m + '\n' +
		'iput-object p3, p0, ' + p + '->listener:' + l + '\niput-object p4, p0, ' + p + '->executor:' + e + '\nreturn-void')
	// Keep the previously exposed no-argument constructor for compatibility.
	source += signature_method('public constructor <init>()V',
		'const/4 v0, 0\nnew-instance v1, ' + m + '\ninvoke-direct {v1}, ' + m + '-><init>()V\ninvoke-direct {p0, v0, v1, v0, v0}, ' + p + '-><init>' + ctor + '\nreturn-void')
	source += signature_method('static constructor <clinit>()V',
		'new-instance v0, ' + p + '\ninvoke-direct {v0}, ' + p + '-><init>()V\nsput-object v0, ' + p + '->LAX:' + p + '\nreturn-void')
	os.write_file(smali + '/android/os/StrictMode$VmPolicy.smali', source)!
	source = '.class public final ' + b + '\n.super Ljava/lang/Object;\n' + fields
	source += signature_method('public constructor <init>()V',
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, ' + m + '\ninvoke-direct {v0}, ' + m + '-><init>()V\niput-object v0, p0, ' + b + '->limits:' + m + '\nreturn-void')
	source += signature_method('public constructor <init>(' + p + ')V',
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niget v0, p1, ' + p + '->mask:I\niput v0, p0, ' + b + '->mask:I\n' +
		'iget-object v1, p1, ' + p + '->limits:' + m + '\nnew-instance v0, ' + m + '\ninvoke-direct {v0, v1}, ' + m + '-><init>(Ljava/util/Map;)V\niput-object v0, p0, ' + b + '->limits:' + m + '\n' +
		'iget-object v0, p1, ' + p + '->listener:' + l + '\niput-object v0, p0, ' + b + '->listener:' + l + '\n' +
		'iget-object v0, p1, ' + p + '->executor:' + e + '\niput-object v0, p0, ' + b + '->executor:' + e + '\nreturn-void')
	for name, bit in {'LeakedSqlLiteObjects': 1, 'LeakedClosableObjects': 2, 'ActivityLeaks': 4,
		'LeakedRegistrationObjects': 16, 'FileUriExposure': 32, 'ContentUriWithoutPermission': 128,
		'UntaggedSockets': 256, 'NonSdkApiUsage': 512, 'ImplicitDirectBoot': 1024,
		'CredentialProtectedWhileLocked': 2048, 'IncorrectContextUse': 4096, 'UnsafeIntentLaunch': 8192} {
		source += signature_method('public detect' + name + '()' + b,
			'iget v0, p0, ' + b + '->mask:I\nconst v1, ${bit}\nor-int v0, v0, v1\niput v0, p0, ' + b + '->mask:I\nreturn-object p0')
	}
	for name, bit in {'penaltyLog': 0x40000000, 'penaltyDeath': 0x10000000, 'penaltyDropBox': 0x04000000} {
		source += signature_method('public ' + name + '()' + b,
			'iget v0, p0, ' + b + '->mask:I\nconst v1, ${bit}\nor-int v0, v0, v1\niput v0, p0, ' + b + '->mask:I\nreturn-object p0')
	}
	// Existing detectAll requests all supported detection configuration flags.
	source += signature_method('public detectAll()' + b,
		'iget v0, p0, ' + b + '->mask:I\nconst v1, 0x39b7\nor-int v0, v0, v1\niput v0, p0, ' + b + '->mask:I\nreturn-object p0')
	source += signature_method('public setClassInstanceLimit(Ljava/lang/Class;I)' + b,
		'if-nez p1, :valid\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n:valid\n' +
		'iget v0, p0, ' + b + '->mask:I\nor-int/lit8 v0, v0, 8\niput v0, p0, ' + b + '->mask:I\n' +
		'iget-object v0, p0, ' + b + '->limits:' + m + '\ninvoke-static {p2}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;\nmove-result-object v1\ninvoke-virtual {v0, p1, v1}, ' + m + '->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\nreturn-object p0')
	source += signature_method('public penaltyListener(' + e + l + ')' + b,
		'if-nez p1, :valid\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n:valid\n' +
		'iput-object p1, p0, ' + b + '->executor:' + e + '\niput-object p2, p0, ' + b + '->listener:' + l + '\nreturn-object p0')
	source += signature_method('public build()' + p,
		'iget v1, p0, ' + b + '->mask:I\niget-object v2, p0, ' + b + '->limits:' + m + '\niget-object v3, p0, ' + b + '->listener:' + l + '\niget-object v4, p0, ' + b + '->executor:' + e + '\n' +
		'if-nez v3, :build\nif-eqz v1, :build\nconst v0, 0x74000000\nand-int v0, v1, v0\nif-nez v0, :build\nconst v0, 0x40000000\nor-int v1, v1, v0\niput v1, p0, ' + b + '->mask:I\n' +
		':build\nnew-instance v0, ' + p + '\ninvoke-direct {v0, v1, v2, v3, v4}, ' + p + '-><init>' + ctor + '\nreturn-object v0')
	os.write_file(smali + '/android/os/StrictMode$VmPolicy$Builder.smali', source)!
	os.write_file(smali + '/android/os/StrictMode$OnVmViolationListener.smali',
		interface_class('android/os/StrictMode$OnVmViolationListener', ['onVmViolation(Landroid/os/strictmode/Violation;)V']))!
	path := smali + '/android/os/StrictMode.smali'
	mut strict := os.read_file(path)!
	strict += '\n.field private static volatile vinixVmPolicy:' + p + '\n'
	strict = framework_replace_method(strict, 'getVmPolicy()' + p,
		signature_method('public static synchronized getVmPolicy()' + p,
			'sget-object v0, Landroid/os/StrictMode;->vinixVmPolicy:' + p + '\nif-nez v0, :ready\nsget-object v0, ' + p + '->LAX:' + p + '\n:ready\nreturn-object v0'))!
	strict = framework_replace_method(strict, 'setVmPolicy(' + p + ')V',
		signature_method('public static synchronized setVmPolicy(' + p + ')V',
			'if-nez p0, :valid\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n:valid\nsput-object p0, Landroid/os/StrictMode;->vinixVmPolicy:' + p + '\nreturn-void'))!
	os.write_file(path, strict)!
}
