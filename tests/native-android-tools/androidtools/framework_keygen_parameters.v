// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Generation requests are metadata. This adds no key-pair provider, device
// identity, certificate or attestation authority.
pub fn framework_keygen_parameters(smali string) ! {
	p := 'Landroid/security/keystore/KeyGenParameterSpec;'
	b := 'Landroid/security/keystore/KeyGenParameterSpec$Builder;'
	path := smali + '/android/security/keystore/KeyGenParameterSpec.smali'
	bpath := smali + '/android/security/keystore/KeyGenParameterSpec$Builder.smali'
	mut source := os.read_file(path)!
	mut builder := os.read_file(bpath)!
	if source.contains('vinixAlgorithmSpec') { return error('key generation parameters already installed') }
	new_fields := {'vinixAlgorithmSpec': 'Ljava/security/spec/AlgorithmParameterSpec;',
		'vinixDigests': '[Ljava/lang/String;', 'vinixAttestationChallenge': '[B', 'vinixUniqueIdIncluded': 'Z',
		'vinixAuthValiditySeconds': 'I'}
	for name, kind in new_fields { source += '\n.field ' + name + ':' + kind + '\n' }
	window_animations_method(source, 'public constructor <init>()V',
		'.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')!
	source = framework_replace_method(source, '<init>()V', signature_method('public constructor <init>()V',
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/4 v0, -1\niput v0, p0, ' + p + '->vinixAuthValiditySeconds:I\nreturn-void'))!
	// This is request metadata only; it grants no key or authentication authority.
	builder += signature_method('public setUserAuthenticationValidityDurationSeconds(I)' + b,
		'const/4 v0, -1\nif-lt p1, v0, :bad\niget-object v0, p0, ' + b + '->spec:' + p + '\niput p1, v0, ' + p + '->vinixAuthValiditySeconds:I\nreturn-object p0\n:bad\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "seconds must be -1 or larger"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0')
	source += signature_method('public getUserAuthenticationValidityDurationSeconds()I',
		'iget v0, p0, ' + p + '->vinixAuthValiditySeconds:I\nreturn v0')
	for kind, suffix in {'[Ljava/lang/String;': 'Strings', '[B': 'Bytes'} {
		source += signature_method('static vinixClone' + suffix + '(' + kind + ')' + kind,
			'if-eqz p0, :done\ninvoke-virtual {p0}, ' + kind + '->clone()Ljava/lang/Object;\nmove-result-object p0\ncheck-cast p0, ' + kind + '\n:done\nreturn-object p0')
	}
	mut copy_body := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	mut fields := new_fields.clone()
	for name, kind in {'blockModes': '[Ljava/lang/String;', 'encryptionPaddings': '[Ljava/lang/String;',
		'keySize': 'I', 'keystoreAlias': 'Ljava/lang/String;', 'purposes': 'I', 'userAuthenticationRequired': 'Z'} {
		fields[name] = kind
	}
	for name, kind in fields {
		op := if kind == 'Z' { '-boolean' } else if kind == 'I' { '' } else { '-object' }
		copy_body += 'iget' + op + ' v0, p1, ' + p + '->' + name + ':' + kind + '\n'
		if kind.starts_with('[') {
			suffix := if kind == '[B' { 'Bytes' } else { 'Strings' }
			copy_body += 'invoke-static {v0}, ' + p + '->vinixClone' + suffix + '(' + kind + ')' + kind + '\nmove-result-object v0\n'
		}
		copy_body += 'iput' + op + ' v0, p0, ' + p + '->' + name + ':' + kind + '\n'
	}
	source += signature_method('constructor <init>(' + p + ')V', copy_body + 'return-void')
	builder = framework_replace_method(builder, 'build()' + p, signature_method('public build()' + p,
		'iget-object v1, p0, ' + b + '->spec:' + p + '\nnew-instance v0, ' + p + '\ninvoke-direct {v0, v1}, ' + p + '-><init>(' + p + ')V\nreturn-object v0'))!
	for method, field in {'AlgorithmParameterSpec': 'vinixAlgorithmSpec', 'Digests': 'vinixDigests',
		'AttestationChallenge': 'vinixAttestationChallenge', 'UniqueIdIncluded': 'vinixUniqueIdIncluded',
		'BlockModes': 'blockModes', 'EncryptionPaddings': 'encryptionPaddings'} {
		kind := fields[field]
		op := if kind == 'Z' { '-boolean' } else { '-object' }
		mut body := ''
		if method == 'AlgorithmParameterSpec' { body += 'invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\n' }
		if kind.starts_with('[') {
			suffix := if kind == '[B' { 'Bytes' } else { 'Strings' }
			body += 'invoke-static {p1}, ' + p + '->vinixClone' + suffix + '(' + kind + ')' + kind + '\nmove-result-object p1\n'
		}
		body += 'iget-object v0, p0, ' + b + '->spec:' + p + '\n'
		if method in ['BlockModes', 'EncryptionPaddings'] {
			// The original fields are private to the enclosing class. Retain
			// its synthetic accessors instead of widening field visibility.
			accessor := if method == 'BlockModes' { r'access$302' } else { r'access$402' }
			if !source.contains(accessor + '(') { return error('key generation array accessor absent') }
			body += 'invoke-static {v0, p1}, ' + p + '->' + accessor + '(' + p + kind + ')' + kind + '\n'
		} else { body += 'iput' + op + ' p1, v0, ' + p + '->' + field + ':' + kind + '\n' }
		body += 'return-object p0'
		mut declaration := 'set' + method + '(' + kind + ')' + b
		if method in ['BlockModes', 'EncryptionPaddings'] {
			builder = framework_replace_method(builder, declaration, signature_method('public ' + declaration, body))!
		} else { builder += signature_method('public ' + declaration, body) }
		mut getter := 'iget' + op + ' v0, p0, ' + p + '->' + field + ':' + kind + '\n'
		if method == 'Digests' {
			getter += 'if-nez v0, :specified\nnew-instance v0, Ljava/lang/IllegalStateException;\ninvoke-direct {v0}, Ljava/lang/IllegalStateException;-><init>()V\nthrow v0\n:specified\n'
		}
		if kind.starts_with('[') {
			suffix := if kind == '[B' { 'Bytes' } else { 'Strings' }
			getter += 'invoke-static {v0}, ' + p + '->vinixClone' + suffix + '(' + kind + ')' + kind + '\nmove-result-object v0\n'
		}
		getter += 'return' + (if kind == 'Z' { '' } else { op }) + ' v0'
		declaration = (if kind == 'Z' { 'is' } else { 'get' }) + method + '()' + kind
		if method in ['BlockModes', 'EncryptionPaddings'] {
			source = framework_replace_method(source, declaration, signature_method('public ' + declaration, getter))!
		} else { source += signature_method('public ' + declaration, getter) }
	}
	source += signature_method('public isDigestsSpecified()Z',
		'iget-object v0, p0, ' + p + '->vinixDigests:[Ljava/lang/String;\nif-eqz v0, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	os.write_file(path, source)!
	os.write_file(bpath, builder)!
}
