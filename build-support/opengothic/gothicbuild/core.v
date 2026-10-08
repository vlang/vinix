// SPDX-License-Identifier: GPL-2.0-or-later
module gothicbuild

import androidhost as ah

fn global(name string) !string {
	return callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn get(id string, key string) !string { return call('operator.getitem', o(id), v(ah.Value(key)))! }

fn set(id string, key string, item string) ! {
	call('operator.setitem', o(id), v(ah.Value(key)), o(item))!
}

fn exists(id string) !bool { return truth(method(id, 'exists', [], {})!)! }

fn is_file(id string) !bool { return truth(method(id, 'is_file', [], {})!)! }

fn is_dir(id string) !bool { return truth(method(id, 'is_dir', [], {})!)! }

fn symlink(id string) !bool { return truth(method(id, 'is_symlink', [], {})!)! }

fn mkdir(id string, parents bool) ! {
	mut kwargs := {
		'exist_ok': v(ah.Value(true))
	}
	if parents { kwargs['parents'] = v(ah.Value(true)) }
	method(id, 'mkdir', [], kwargs)!
}

fn write(id string, data string) ! { method(id, 'write_text', [v(ah.Value(data))], {})! }

fn read(id string) !string { return method(id, 'read_text', [], {})! }

fn strings(items []string) !string {
	mut values := []string{}
	for item in items { values << literal(ah.Value(item))! }
	return collection('list', values)!
}

fn public(name string, args []string, kwargs map[string]ah.Value) !string {
	return invoke(name, args.map(o(it)), kwargs)!
}

fn command(args []string, kwargs map[string]ah.Value) ! { public('run', args, kwargs)! }

fn run(args string, kwargs string) ! {
	mut parts := []string{}
	iter := iterator(args)!
	for {
		part := next(iter)!
		if part.done { break }
		parts << call('str', o(part.value))!
	}
	callback('function', {
		'name':         ah.Value('subprocess.run')
		'args':         ah.Value([o(collection('list', parts)!)])
		'kwargs':       ah.Value({
			'check': v(ah.Value(true))
		})
		'kwargs_owner': ah.Value(kwargs)
	})!
}

fn apply_patch(source string, name string) ! {
	patch := call('operator.truediv', o(join(global('ROOT')!, 'build-support/opengothic')!), o(name))!
	clean := invoke('subprocess.run', [o(collection('list', [
		literal(ah.Value('git'))!,
		literal(ah.Value('-C'))!,
		call('str', o(source))!,
		literal(ah.Value('apply'))!,
		literal(ah.Value('--check'))!,
		call('str', o(patch))!,
	])!)], {
		'capture_output': v(ah.Value(true))
	})!
	if compare('eq', attribute(clean, 'returncode')!, literal(ah.Value(0))!)! {
		command([literal(ah.Value('git'))!, literal(ah.Value('-C'))!, source,
			literal(ah.Value('apply'))!, patch], {})!
	} else {
		command([literal(ah.Value('git'))!, literal(ah.Value('-C'))!, source,
			literal(ah.Value('apply'))!, literal(ah.Value('--reverse'))!,
			literal(ah.Value('--check'))!, patch], {})!
	}
}

fn download(url string, path string) ! {
	if is_file(path)! && truth(attribute(method(path, 'stat', [], {})!, 'st_size')!)! { return }
	part := call('operator.add', o(attribute(path, 'suffix')!), v(ah.Value('.part')))!
	temporary := method(path, 'with_suffix', [o(part)], {})!
	command([literal(ah.Value('curl'))!, literal(ah.Value('-fL'))!, literal(ah.Value('--retry'))!,
		literal(ah.Value('3'))!, literal(ah.Value('-o'))!, temporary, url], {})!
	method(temporary, 'replace', [o(path)], {})!
}

fn checkout(url string, path string, commit string, submodules string) ! {
	if !exists(path)! {
		command([literal(ah.Value('git'))!, literal(ah.Value('clone'))!,
			literal(ah.Value('--no-checkout'))!, literal(ah.Value('--filter=blob:none'))!, url,
			path], {})!
		command([literal(ah.Value('git'))!, literal(ah.Value('-C'))!, path,
			literal(ah.Value('checkout'))!, literal(ah.Value('--detach'))!, commit], {})!
	}
	output := invoke('subprocess.check_output', [o(collection('list', [
		literal(ah.Value('git'))!,
		literal(ah.Value('-C'))!,
		call('str', o(path))!,
		literal(ah.Value('rev-parse'))!,
		literal(ah.Value('HEAD'))!,
	])!)], {
		'text': v(ah.Value(true))
	})!
	actual := method(output, 'strip', [], {})!
	if compare('ne', actual, commit)! {
		failed('SystemExit', 'Expected ${text(commit)!} in ${text(path)!}, found ${text(actual)!}', none)!
	}
	if truth(submodules)! {
		command([literal(ah.Value('git'))!, literal(ah.Value('-C'))!, path,
			literal(ah.Value('submodule'))!, literal(ah.Value('update'))!,
			literal(ah.Value('--init'))!, literal(ah.Value('--recursive'))!], {})!
	}
}

fn copy_file(source string, target string) ! {
	mkdir(attribute(target, 'parent')!, true)!
	if exists(target)! || symlink(target)! { method(target, 'unlink', [], {})! }
	if symlink(source)! {
		method(target, 'symlink_to', [o(call('os.readlink', o(source))!)], {})!
	} else {
		call('shutil.copy2', o(source), o(target))!
	}
}

fn stage_game(installation string, game string) ! {
	found := call('builtins.dict')!
	entries := iterator(method(installation, 'iterdir', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { break }
		if is_dir(entry.value)! {
			key := method(attribute(entry.value, 'name')!, 'lower', [], {})!
			call('operator.setitem', o(found), o(key), o(entry.value))!
		}
	}
	work := method(found, 'get', [v(ah.Value('_work'))], {})!
	inner := call('builtins.dict')!
	if truth(work)! {
		iter := iterator(method(work, 'iterdir', [], {})!)!
		for {
			entry := next(iter)!
			if entry.done { break }
			key := method(attribute(entry.value, 'name')!, 'lower', [], {})!
			call('operator.setitem', o(inner), o(key), o(entry.value))!
		}
	}
	if !truth(call('operator.contains', o(found), v(ah.Value('data')))!)!
		|| !truth(call('operator.contains', o(inner), v(ah.Value('data')))!)! {
		failed('SystemExit', 'No Gothic II installation in ${text(installation)!}: it needs Data and _work/Data', none)!
	}
	if exists(game)! { call('shutil.rmtree', o(game))! }
	call('shutil.copytree', o(get(found, 'data')!), o(join(game, 'Data')!))!
	iter := iterator(method(work, 'iterdir', [], {})!)!
	for {
		entry := next(iter)!
		if entry.done { break }
		name := attribute(entry.value, 'name')!
		lower := method(name, 'lower', [], {})!
		dest_name := if compare('eq', lower, literal(ah.Value('data'))!)! {
			literal(ah.Value('Data'))!
		} else {
			name
		}
		target := call('operator.truediv', o(join(game, '_work')!), o(dest_name))!
		if is_dir(entry.value)! {
			call('shutil.copytree', o(entry.value), o(target))!
		} else {
			public('copy_file', [entry.value, target], {})!
		}
	}
	if truth(call('operator.contains', o(found), v(ah.Value('system')))!)! {
		call('shutil.copytree', o(get(found, 'system')!), o(join(game, 'System')!))!
	}
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'run' { run(args[0], args[1])! }
		'apply_patch' { apply_patch(args[0], args[1])! }
		'download' { download(args[0], args[1])! }
		'checkout' { checkout(args[0], args[1], args[2], args[3])! }
		'copy_file' { copy_file(args[0], args[1])! }
		'stage_game' { stage_game(args[0], args[1])! }
		'fetch' { return ah.Value(fetch(args[0], args[1])!) }
		'main' { main_policy()! }
		else { return error('unknown OpenGothic build operation') }
	}
	return ah.Value(null()!)
}
