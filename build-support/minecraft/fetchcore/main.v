// SPDX-License-Identifier: GPL-2.0-or-later
module fetchcore

import androidhost as ah

fn keywords(name string, args []ah.Value, values map[string]ah.Value) !ah.Value {
	return callback('public', {
		'name':     ah.Value(name)
		'args':     ah.Value(args)
		'keywords': ah.Value(values)
	})!
}

fn stage(options ah.Value) !ah.Value {
	resolved := public('resolve_version', [
		argument('value', item(options, ah.Value('version'))!),
		argument('value', item(options, ah.Value('max_java'))!),
	], false)!
	version_id := item(resolved, ah.Value(0))!
	version := item(resolved, ah.Value(1))!
	log('  Minecraft ' + stringify(version_id)! + ' (' + stringify(item(version, ah.Value('type'))!)! + '), Java ' +
		stringify(get(get(version, 'javaVersion', ah.Value(map[string]ah.Value{}))!, 'majorVersion', null())!)!)!
	game_root := item(options, ah.Value('game_root'))!
	root := join(item(options, ah.Value('staging'))!.text(), method('lstrip', [
		game_root,
		ah.Value('/'),
	])!)!
	mkdir(root)!
	client := item(item(version, ah.Value('downloads'))!, ah.Value('client'))!
	client_path := 'versions/' + stringify(version_id)! + '/' + stringify(version_id)! + '.jar'
	log('  client jar')!
	download_api(item(client, ah.Value('url'))!, join(root, ah.Value(client_path))!, item(client, ah.Value('sha1'))!)!
	selected := public('select_libraries', [argument('value', version)], false)!
	mojang := item(selected, ah.Value(0))!
	natives := item(selected, ah.Value(1))!
	jobs := item(options, ah.Value('jobs'))!
	libraries := join(root, ah.Value('libraries'))!
	public('download_all', [argument('value', mojang), argument('path', ah.Value(libraries)),
		argument('value', ah.Value('libraries')), argument('value', jobs)], false)!
	public('download_all', [argument('value', natives), argument('path', ah.Value(libraries)),
		argument('value', ah.Value('LWJGL ' + stringify(constant('NATIVES_CLASSIFIER')!)!)),
		argument('value', jobs)], false)!
	mut asset_index := null()
	if truth(item(options, ah.Value('no_assets'))!)! {
		asset_index = item(item(version, ah.Value('assetIndex'))!, ah.Value('id'))!
		index := item(version, ah.Value('assetIndex'))!
		target := join(join(join(root, ah.Value('assets'))!, ah.Value('indexes'))!, ah.Value(stringify(asset_index)! + '.json'))!
		download_api(item(index, ah.Value('url'))!, target, item(index, ah.Value('sha1'))!)!
		log('  assets: index only (--no-assets)')!
	} else {
		asset_index = public('download_assets', [argument('value', version),
			argument('path', ah.Value(root)), argument('value', jobs)], false)!
	}
	mut classpath := []ah.Value{}
	for group in [mojang, natives] {
		for entry in iterable(group)! {
			classpath << ah.Value('libraries/' + stringify(item(entry, ah.Value('path'))!)!)
		}
	}
	classpath << ah.Value(client_path)
	keywords('write_launch_env', [argument('path', ah.Value(join(root, ah.Value('launch.env'))!))],
		{
			'version_id':  version_id
			'version':     version
			'classpath':   ah.Value(classpath)
			'asset_index': asset_index
			'game_root':   game_root
		})!
	mut total := ah.Value(0)
	for item_path in callback('paths', {
		'path':    ah.Value(root)
		'pattern': ah.Value('*')
	})!.items() {
		if test('is_file', item_path.text())! {
			size := callback('stat_size', {
				'path': item_path
			})!
			total = callback('compare', {
				'name':      ah.Value('add')
				'arguments': ah.Value([total, size])
			})!
		}
	}
	mib := callback('compare', {
		'name':      ah.Value('truediv')
		'arguments': ah.Value([total, ah.Value(1 << 20)])
	})!
	amount := callback('format', {
		'arguments':     ah.Value([mib])
		'specification': ah.Value('.0f')
	})!.text()
	log('  staged ' + amount + ' MiB under ' + stringify(game_root)!)!
	return ah.Value(0)
}
