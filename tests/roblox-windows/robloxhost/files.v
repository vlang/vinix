// SPDX-License-Identifier: MIT
module robloxhost

import androidhost as ah

fn take(id string, index int) !string {
	return call('operator.getitem', o(id), v(ah.Value(index)))!
}

fn value_int(n int) !string { return literal(ah.Value(n))! }

fn public_host(name string, args []string) !string { return invoke(name, args.map(o(it)), {})! }

fn tuple_pair(a string, b string) !string { return collection('tuple', [a, b])! }

fn download(url string, target string) ! {
	partial := method(target, 'with_name', [o(call('operator.add', o(attribute(target, 'name')!), v(ah.Value('.partial')))!)], {})!
	response_manager := invoke('urllib.request.urlopen', [o(url)], {
		'timeout': v(ah.Value(120))
	})!
	response := enter(response_manager)!
	download_output(response, partial) or {
		if !retire(response_manager, err)! { return err }
		method(partial, 'rename', [o(target)], {})!
		return
	}
	retire(response_manager, none)!
	method(partial, 'rename', [o(target)], {})!
}

fn download_output(response string, partial string) ! {
	manager := method(partial, 'open', [v(ah.Value('wb'))], {})!
	output := enter(manager)!
	call('shutil.copyfileobj', o(response), o(output), v(ah.Value(1024 * 1024))) or {
		if !retire(manager, err)! { return err }
		return
	}
	retire(manager, none)!
}

fn md5(path string) !string {
	digest := call('hashlib.md5')!
	manager := method(path, 'open', [v(ah.Value('rb'))], {})!
	source := enter(manager)!
	mut buffer := Md5Buffer{}
	md5_blocks(digest, source, mut buffer) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return md5_result(digest, buffer.last)!
	}
	retire(manager, none)!
	return md5_result(digest, buffer.last)!
}

struct Md5Buffer {
mut:
	last string
}

fn md5_result(digest string, last string) !string {
	result := method(digest, 'hexdigest', [], {})!
	release(digest, last)!
	return result
}

fn md5_blocks(digest string, source string, mut buffer Md5Buffer) ! {
	reader := call('_reader', o(source))!
	blocks := call('iter', o(reader), o(bytes('')!)) or {
		failure := err
		activate(failure)!
		release(reader) or { return failure }
		activate(none)!
		return failure
	}
	release(reader)!
	items := iterator(blocks) or {
		failure := err
		activate(failure)!
		release(reader, blocks) or { return failure }
		activate(none)!
		return failure
	}
	release(blocks)!
	md5_loop(digest, items, mut buffer) or {
		failure := err
		activate(failure)!
		release(reader, blocks, items) or { return failure }
		activate(none)!
		return failure
	}
	release(reader, blocks, items)!
}

fn md5_loop(digest string, items string, mut buffer Md5Buffer) ! {
	for {
		block := next(items)!
		if block.done { return }
		release(buffer.last)!
		buffer.last = block.value
		updated := method(digest, 'update', [o(block.value)], {})!
		release(updated)!
	}
}

fn version() !string {
	manager := invoke('urllib.request.urlopen', [o(global('VERSION_URL')!)], {
		'timeout': v(ah.Value(60))
	})!
	response := enter(manager)!
	value := load_version(response) or {
		if !retire(manager, err)! { return err }
		return ''
	}
	retire(manager, none)!
	return value
}

fn load_version(response string) !string {
	return call('operator.getitem', o(call('json.load', o(response))!), v(ah.Value('clientVersionUpload')))!
}

fn fetch(work string, requested string) !string {
	loaded := if compare('is_', requested, null()!)! { version()! } else { requested }
	deployment := if loaded == '' { requested } else { loaded }
	if !truth(method(deployment, 'startswith', [v(ah.Value('version-'))], {})!)! || !truth(method(slice(deployment, value_int(8)!, null()!)!, 'isalnum', [], {})!)! {
		failed('SystemExit', 'Not a Roblox deployment name: ' + text(deployment)!, none)!
	}
	downloads := call('operator.truediv', o(join(work, 'downloads')!), o(deployment))!
	mkdir(downloads, true)!
	manifest := join(downloads, 'rbxPkgManifest.txt')!
	if !exists(manifest)! {
		public_host('download', [
			lit(text(global('CDN')!)! + '/' + text(deployment)! + '-rbxPkgManifest.txt')!,
			manifest,
		])!
	}
	lines := method(method(manifest, 'read_text', [], {})!, 'split', [], {})!
	if compare('ne', take(lines, 0)!, lit('v0')!)! || truth(call('operator.mod', o(call('operator.sub', o(length(lines)!), v(ah.Value(1)))!), v(ah.Value(4)))!)! {
		failed('SystemExit', 'Unknown package manifest format in ' + text(manifest)!, none)!
	}
	indices := iterator(call('range', v(ah.Value(1)), o(length(lines)!), v(ah.Value(4)))!)!
	for {
		index := next(indices)!
		if index.done { break }
		name := call('operator.getitem', o(lines), o(index.value))!
		checksum := call('operator.getitem', o(lines), o(call('operator.add', o(index.value), v(ah.Value(1)))!))!
		if truth(call('operator.contains', o(global('SKIPPED')!), o(name))!)! { continue }
		if !truth(call('operator.contains', o(global('PACKAGES')!), o(name))!)! {
			failed('SystemExit', 'Deployment ' + text(deployment)! + ' has a package this test cannot place: ' + text(name)!, none)!
		}
		package := call('operator.truediv', o(downloads), o(name))!
		if !exists(package)! {
			invoke('print', [v(ah.Value('Downloading ' + text(name)!))], {
				'flush': v(ah.Value(true))
			})!
			public_host('download', [
				lit(text(global('CDN')!)! + '/' + text(deployment)! + '-' + text(name)!)!,
				package,
			])!
		}
		if compare('ne', public_host('md5', [package])!, checksum)! {
			method(package, 'unlink', [], {})!
			failed('SystemExit', text(name)! + ' does not match its manifest checksum; run again to refetch it', none)!
		}
	}
	return tuple_pair(deployment, downloads)!
}

fn stage(downloads string, client string) ! {
	if exists(join(client, '.staged')!)! { return }
	if exists(client)! { call('shutil.rmtree', o(client))! }
	items := iterator(method(global('PACKAGES')!, 'items', [], {})!)!
	for {
		item := next(items)!
		if item.done { break }
		pair := callback('unpack_pair', {
			'owner': ah.Value(item.value)
		})!.items().map(it.text())
		package := call('operator.truediv', o(downloads), o(pair[0]))!
		if !exists(package)! { continue }
		manager := call('zipfile.ZipFile', o(package))!
		archive := enter(manager)!
		stage_archive(pair[0], pair[1], archive, client) or {
			if !retire(manager, err)! { return err }
			continue
		}
		retire(manager, none)!
	}
	method(join(client, 'AppSettings.xml')!, 'write_text', [o(global('APP_SETTINGS')!)], {})!
	method(join(client, '.staged')!, 'touch', [], {})!
}

fn stage_archive(name string, directory string, archive string, client string) ! {
	entries := iterator(method(archive, 'infolist', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { return }
		filename := attribute(entry.value, 'filename')!
		parts := method(method(filename, 'replace', [v(ah.Value('\\')), v(ah.Value('/'))], {})!, 'split', [v(ah.Value('/'))], {})!
		mut values := [o(directory)]
		iter := iterator(parts)!
		for {
			part := next(iter)!
			if part.done { break }
			if truth(part.value)! { values << o(part.value) }
		}
		relative := invoke('Path', values, {})!
		if truth(call('operator.contains', o(attribute(relative, 'parts')!), v(ah.Value('..')))!)! {
			failed('SystemExit', text(name)! + ' has an entry outside its directory: ' + text(filename)!, none)!
		}
		target := call('operator.truediv', o(client), o(relative))!
		if truth(method(filename, 'endswith', [o(collection('tuple', [lit('/')!, lit('\\')!])!)], {})!)! {
			mkdir(target, true)!
			continue
		}
		mkdir(attribute(target, 'parent')!, true)!
		manager := method(archive, 'open', [o(entry.value)], {})!
		source := enter(manager)!
		download_output(source, target) or {
			if !retire(manager, err)! { return err }
			continue
		}
		retire(manager, none)!
	}
}

fn copy_layer(source string, destination string, skip string, base_arg string) ! {
	base := if truth(base_arg)! { base_arg } else { source }
	mkdir(destination, true)!
	entries := iterator(method(source, 'iterdir', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { return }
		if truth(call('operator.contains', o(skip), o(call('str', o(method(entry.value, 'relative_to', [o(base)], {})!))!))!)! {
			continue
		}
		target := call('operator.truediv', o(destination), o(attribute(entry.value, 'name')!))!
		if truth(method(entry.value, 'is_symlink', [], {})!)! {
			if exists(target)! || truth(method(target, 'is_symlink', [], {})!)! {
				method(target, 'unlink', [], {})!
			}
			method(target, 'symlink_to', [o(call('os.readlink', o(entry.value))!)], {})!
		} else if is_dir(entry.value)! {
			public_host('copy_layer', [entry.value, target, skip, base])!
		} else {
			if exists(target)! || truth(method(target, 'is_symlink', [], {})!)! {
				method(target, 'unlink', [], {})!
			}
			call('shutil.copy2', o(entry.value), o(target))!
		}
	}
}
