// SPDX-License-Identifier: GPL-2.0-or-later
module fetchcore

import androidhost as ah
import crypto.sha1
import encoding.hex
import json2

fn hash_payload(data string) !string { return sha1.sum(hex.decode(data)!).hex() }

fn sha1_of(value string) !string {
	owner := callback('open_read', {
		'path': ah.Value(value)
	})!
	mut hash := sha1.new()
	mut cause := ?IError(none)
	for {
		payload := callback('read_handle', {
			'id':   owner
			'size': ah.Value(1 << 20)
		}) or {
			cause = err
			break
		}
		data := hex.decode(payload.text()) or {
			cause = err
			break
		}
		if data.len == 0 { break }
		hash.write(data) or {
			cause = err
			break
		}
	}
	suppressed := retire(owner, cause)!
	if !suppressed {
		if failure := cause { return failure }
	}
	return hash.sum([]u8{}).hex()
}

fn fetch(url ah.Value, retries ah.Value) !ah.Value {
	mut last := 'None'
	for truth(callback('range_next', {
		'count': retries
	})!)! {
		mut cause := ?IError(none)
		data := callback('fetch_once', {
			'url':     url
			'timeout': ah.Value(120)
			'headers': ah.Value({
				'User-Agent': ah.Value('vinix-minecraft-builder/1')
			})
		}) or {
			cause = err
			null()
		}
		if failure := cause {
			if failure is BindingError && truth(ah.field(failure.value, 'retryable'))! {
				last = failure.msg()
				continue
			}
			return failure
		}
		if !truth(ah.field(data.object(), 'received'))! { continue }
		return ah.field(data.object(), 'data')
	}
	return failed('RuntimeError', 'failed to download ' + stringify(url)! + ': ' + last)
}

fn download(url ah.Value, destination string, expected ah.Value) !bool {
	if test('exists', destination)! {
		if expected is json2.Null || equal(public('sha1_of', [argument('path', ah.Value(destination))], false)!, expected)! {
			return false
		}
	}
	mkdir(path('parent', destination, []ah.Value{}, map[string]ah.Value{})!.text())!
	payload := fetch_api(url)!
	if expected !is json2.Null {
		actual := hash_payload(payload)!
		if !equal(ah.Value(actual), expected)! {
			return failed('RuntimeError', 'checksum mismatch for ' + stringify(url)! + ': expected ' + stringify(expected)! + ', got ' + actual)
		}
	}
	name := path('name', destination, []ah.Value{}, map[string]ah.Value{})!.text()
	temporary := path('with_name', destination, [ah.Value(name + '.part')], map[string]ah.Value{})!.text()
	callback('write_bytes', {
		'path': ah.Value(temporary)
		'data': ah.Value(payload)
	})!
	path('replace', temporary, [ah.Value(destination)], map[string]ah.Value{})!
	return true
}

fn download_all(entries ah.Value, root string, label ah.Value, jobs ah.Value) ! {
	count := callback('entry_length', map[string]ah.Value{})!
	log('  ' + stringify(label)! + ': ' + stringify(count)! + ' files')!
	owner := callback('pool_open', {
		'jobs': jobs
	})!
	mut transferred := TransferCount{}
	mut cause := ?IError(none)
	download_loop(owner, entries, root, mut transferred) or { cause = err }
	suppressed := retire(owner, cause)!
	if !suppressed {
		if failure := cause { return failure }
	}
	cached := callback('compare', {
		'name':      ah.Value('sub')
		'arguments': ah.Value([callback('entry_length', map[string]ah.Value{})!,
			ah.Value(transferred.value)])
	})!
	log('  ' + stringify(label)! + ': ${transferred.value} downloaded, ' + stringify(cached)! + ' cached')!
}

fn download_api(url ah.Value, path string, expected ah.Value) !ah.Value {
	return public('download_to', [argument('value', url), argument('path', ah.Value(path)),
		argument('value', expected)], false)!
}

fn assets(version ah.Value, root string, jobs ah.Value) !ah.Value {
	index := item(version, ah.Value('assetIndex'))!
	id := item(index, ah.Value('id'))!
	index_path := join(join(join(root, ah.Value('assets'))!, ah.Value('indexes'))!, ah.Value(stringify(id)! + '.json'))!
	download_api(item(index, ah.Value('url'))!, index_path, item(index, ah.Value('sha1'))!)!
	objects := item(json_load(path('read_text', index_path, []ah.Value{}, map[string]ah.Value{})!, false)!, ah.Value('objects'))!
	mut entries := []ah.Value{}
	mut positions := map[string]int{}
	for meta in iterable(method('values', [objects])!)! {
		digest := item(meta, ah.Value('hash'))!
		// The published hash is a string; the prefix operation is byte-exact for
		// ASCII hashes while the binding retains Python slicing errors/types.
		prefix := callback('slice', {
			'value': digest
			'end':   ah.Value(2)
		})!
		file := 'assets/objects/' + stringify(prefix)! + '/' + stringify(digest)!
		entry := ah.Value({
			'path': ah.Value(file)
			'url':  ah.Value(stringify(constant('ASSET_BASE')!)! + '/' + stringify(prefix)! + '/' + stringify(digest)!)
			'sha1': digest
		})
		if file in positions {
			entries[positions[file]] = entry
		} else {
			positions[file] = entries.len
			entries << entry
		}
	}
	public('download_all', [argument('value', ah.Value(entries)), argument('path', ah.Value(root)),
		argument('value', ah.Value('assets')), argument('value', jobs)], false)!
	return item(index, ah.Value('id'))!
}

fn download_loop(owner ah.Value, entries ah.Value, root string, mut transferred TransferCount) ! {
	callback('pool_start', {
		'id':      owner
		'entries': entries
		'root':    ah.Value(root)
	})!
	for {
		row := callback('pool_next', map[string]ah.Value{})!.object()
		if truth(ah.field(row, 'done'))! { break }
		if truth(ah.field(row, 'value'))! { transferred.value++ }
	}
}

struct TransferCount {
mut:
	value int
}
