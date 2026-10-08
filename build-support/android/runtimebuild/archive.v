module runtimebuild

import androidhost as ah

fn join_object(path ah.Value, name ah.Value) !ah.Value {
	return method('acquire', path, '__truediv__', [object(name)], {})!
}

fn is_none(value ah.Value) !bool {
	return truth(callback('is_none', {
		'id': value
	})!)
}

fn setattr(value ah.Value, name string, content ah.Value) ! {
	callback('setattr', {
		'id':    value
		'name':  ah.Value(name)
		'value': object(content)
	})!
}

fn copy_output(contents ah.Value, destination ah.Value) ! {
	output := method('enter', destination, 'open', [ordinary(ah.Value('wb'))], {})!
	mut failed := false
	mut cause := IError(none)
	call('invoke', 'shutil', 'copyfileobj', [object(contents), object(output)], {}) or {
		failed = true
		cause = err
		null()
	}
	suppressed := exit_context(output, failed, cause)!
	if failed && !suppressed { return cause }
}

fn copy_contents(contents ah.Value, destination ah.Value) ! {
	input := callback('enter_existing', {
		'id': contents
	})!
	mut failed := false
	mut cause := IError(none)
	copy_output(input, destination) or {
		failed = true
		cause = err
	}
	suppressed := exit_context(input, failed, cause)!
	if failed && !suppressed { return cause }
}

fn member_name(member ah.Value) !ah.Value { return attribute(member, 'name', true)! }

fn link_name(member ah.Value) !ah.Value { return attribute(member, 'linkname', true)! }

fn extract_body(source ah.Value, target ah.Value) ! {
	iterator := call('acquire', 'builtins', 'iter', [object(source)], {})!
	for {
		member := next(iterator)!
		if member == null() { break }
		name := member_name(member)!
		pure := api('PurePosixPath', [object(name)], {}, true)!
		parts := attribute(pure, 'parts', true)!
		if !truth(call('invoke', 'builtins', 'bool', [object(parts)], {})!) { continue }
		first := method('acquire', parts, '__getitem__', [ordinary(ah.Value(0))], {})!
		if truth(method('invoke', first, 'startswith', [ordinary(ah.Value('.'))], {})!) { continue }
		if test(pure, 'is_absolute')! || truth(call('invoke', 'operator', 'contains', [
			object(parts),
			ordinary(ah.Value('..')),
		], {})!) {
			return fail('unsafe APK payload path: ' + str(name)!)
		}
		if !(test(member, 'isdir')! || test(member, 'isfile')! || test(member, 'issym')! || test(member, 'islnk')!) {
			continue
		}
		if test(member, 'issym')! {
			if truth(method('invoke', link_name(member)!, 'startswith', [ordinary(ah.Value('/'))], {})!) {
				stripped := method('acquire', link_name(member)!, 'lstrip', [ordinary(ah.Value('/'))], {})!
				absolute := join_object(target, stripped)!
				parent := attribute(join_object(target, name)!, 'parent', true)!
				relative := call('acquire', 'os.path', 'relpath', [object(absolute), object(parent)], {})!
				setattr(member, 'linkname', relative)!
			}
			destination := join_object(attribute(join_object(target, name)!, 'parent', true)!, link_name(member)!)!
			absolute := call('acquire', 'os.path', 'abspath', [object(destination)], {})!
			path := api('Path', [object(absolute)], {}, true)!
			if !truth(method('invoke', path, 'is_relative_to', [object(target)], {})!) {
				return fail('unsafe APK symlink: ' + str(name)!)
			}
		}
		if test(member, 'islnk')! {
			link := link_name(member)!
			mut unsafe_link := truth(method('invoke', link, 'startswith', [ordinary(ah.Value('/'))], {})!)
			if !unsafe_link {
				link_pure := api('PurePosixPath', [object(link)], {}, true)!
				link_parts := attribute(link_pure, 'parts', true)!
				unsafe_link = truth(call('invoke', 'operator', 'contains', [
					object(link_parts),
					ordinary(ah.Value('..')),
				], {})!)
			}
			if unsafe_link { return fail('unsafe APK hardlink: ' + str(name)!) }
		}
		destination := join_object(target, name)!
		parent := attribute(destination, 'parent', true)!
		method('invoke', parent, 'mkdir', [], {
			'parents':  ah.Value(true)
			'exist_ok': ah.Value(true)
		})!
		resolved := method('acquire', parent, 'resolve', [], {})!
		if !truth(method('invoke', resolved, 'is_relative_to', [object(target)], {})!) {
			return fail('APK payload parent escapes prefix: ' + str(name)!)
		}
		if test(member, 'isdir')! {
			method('invoke', destination, 'mkdir', [], {
				'exist_ok': ah.Value(true)
			})!
		} else {
			if test(destination, 'exists')! || test(destination, 'is_symlink')! {
				unlink(destination, false)!
			}
			if test(member, 'issym')! {
				method('invoke', destination, 'symlink_to', [object(link_name(member)!)], {})!
			} else if test(member, 'islnk')! {
				existing := method('acquire', join_object(target, link_name(member)!)!, 'resolve', [], {
					'strict': ah.Value(true)
				})!
				if !truth(method('invoke', existing, 'is_relative_to', [object(target)], {})!) {
					return fail('APK hardlink escapes prefix: ' + str(name)!)
				}
				call('invoke', 'os', 'link', [object(existing), object(destination)], {})!
			} else {
				contents := method('acquire', source, 'extractfile', [object(member)], {})!
				if is_none(contents)! { return fail('APK file has no payload: ' + str(name)!) }
				copy_contents(contents, destination)!
				mode := call('acquire', 'operator', 'and_', [
					object(attribute(member, 'mode', true)!),
					ordinary(ah.Value(0o777)),
				], {})!
				method('invoke', destination, 'chmod', [object(mode)], {})!
			}
		}
	}
}

fn extract(archive ah.Value, target ah.Value) ! {
	owner := call('enter', 'tarfile', 'open', [object(archive)], {
		'mode':         ah.Value('r:gz')
		'ignore_zeros': ah.Value(true)
	})!
	mut failed := false
	mut cause := IError(none)
	extract_body(owner, target) or {
		failed = true
		cause = err
	}
	suppressed := exit_context(owner, failed, cause)!
	if failed && !suppressed { return cause }
}
