// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_account_broker_context_classes() map[string]string {
	name := 'android/atl/VinixAccountBrokerContext'
	mut source := '.class public final L${name};\n.super Ljava/lang/Object;\n'
	for method in ['callingUid()I','callingPid()I','callingPermission(Ljava/lang/String;)I','checkPermission(Ljava/lang/String;II)I'] {
		source += '.method public static native ${method}\n.end method\n'
	}
	return {name: source}
}

fn broker_wrap(source string, class_name string, signature string, original_name string,
	static_method bool, query string, args string) !string {
	if source.contains(' ' + original_name + '(') { return error('broker fallback already installed') }
	mut found := ''
	for block in source.split('.method ')[1..] {
		if !block.all_before('\n').ends_with(' ' + signature) { continue }
		if found != '' || block.all_before('\n').contains(' native ') { return error('invalid broker fallback method') }
		end := block.index('.end method') or { return error('unterminated broker fallback') }
		found = '.method ' + block[..end + '.end method'.len]
	}
	if found == '' { return error('missing broker fallback ' + signature) }
	params := signature.all_after('(')
	decl := '.method private ' + if static_method { 'static ' } else { '' }
	renamed := decl + original_name + '(' + params + '\n' + found.all_after('\n')
	method_decl := '.method public ' + if static_method { 'static ' } else { '' }
	query_regs := if args == '' { '{}' } else { '{' + args + '}' }
	original_regs := if static_method { '{}' } else { '{p0, ' + args + '}' }
	invoke := if static_method { 'invoke-static' } else { 'invoke-direct' }
	wrapper := method_decl + signature + '\n.locals 2\n:query_start\n' +
		'invoke-static ' + query_regs + ', Landroid/atl/VinixAccountBrokerContext;->' + query + '\n' +
		'move-result v0\n:query_end\nconst/4 v1, -2\nif-eq v0, v1, :fallback\nreturn v0\n' +
		'.catch Ljava/lang/UnsatisfiedLinkError; {:query_start .. :query_end} :unavailable\n' +
		':unavailable\nmove-exception v0\n:fallback\n' + invoke + ' ' + original_regs + ', L' + class_name + ';->' + original_name + '(' + params + '\nmove-result v0\nreturn v0\n.end method'
	return source.replace(found, renamed + '\n' + wrapper)
}

pub fn framework_account_broker_sources(binder string, context string) !map[string]string {
	mut b := binder
	for suffix in ['Uid','Pid'] {
		b = broker_wrap(b, 'android/os/Binder','getCalling' + suffix + '()I','vinixOriginalCalling' + suffix,true,'calling' + suffix + '()I','')!
	}
	mut c := context
	c = broker_wrap(c,'android/content/Context','checkCallingOrSelfPermission(Ljava/lang/String;)I','vinixOriginalCallingPermission',false,'callingPermission(Ljava/lang/String;)I','p1')!
	c = broker_wrap(c,'android/content/Context','checkPermission(Ljava/lang/String;II)I','vinixOriginalPermission',false,'checkPermission(Ljava/lang/String;II)I','p1, p2, p3')!
	signature := 'checkCallingPermission(Ljava/lang/String;)I'
	if !c.contains(' ' + signature + '\n') {
		c += '\n.method public ' + signature + '\n.locals 1\n' +
			'invoke-direct {p0, p1}, Landroid/content/Context;->vinixOriginalCallingPermission(Ljava/lang/String;)I\n' +
			'move-result v0\nreturn v0\n.end method\n'
	}
	c = broker_wrap(c,'android/content/Context',signature,'vinixOriginalCheckCallingPermission',false,'callingPermission(Ljava/lang/String;)I','p1')!
	return {'android/os/Binder': b, 'android/content/Context': c}
}

pub fn framework_account_broker_context(smali string) ! {
	paths := ['android/os/Binder','android/content/Context']
	mut classes := framework_account_broker_sources(os.read_file(smali + '/' + paths[0] + '.smali')!,os.read_file(smali + '/' + paths[1] + '.smali')!)!
	for name, source in framework_account_broker_context_classes() { classes[name] = source }
	for name, source in classes { os.write_file(smali + '/' + name + '.smali',source)! }
}
