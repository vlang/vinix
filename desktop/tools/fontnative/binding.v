// SPDX-License-Identifier: GPL-2.0-or-later
module fontnative

import cachecli
import encoding.hex
import json2
import os
import sourcecommand

struct OwnedFont {
mut:
	font   Font
	owners map[string]bool
	glyphs map[int]Glyph
}

pub struct Context {
mut:
	library   Library
	fonts     map[int]&OwnedFont
	masks     map[int]Glyph
	next_font int
	next_mask int
	tt        map[int]&Ttf
	next_tt   int
}

pub fn context() !Context { return Context{ library: library()! } }

pub fn (mut ctx Context) close() {
	for _, mut item in ctx.fonts { item.font.close() }
	ctx.fonts.clear()
	ctx.masks.clear()
	for _, mut item in ctx.tt { item.close() }
	ctx.tt.clear()
	ctx.library.close()
}

fn (mut ctx Context) glyph(id int, point int) !Glyph {
	mut item := ctx.fonts[id] or { return error('unknown font identity') }
	if point !in item.glyphs { item.glyphs[point] = item.font.raster(point)! }
	return item.glyphs[point]
}

fn field(row map[string]json2.Any, name string) !json2.Any {
	return row[name] or { return error('missing font argument: ' + name) }
}

fn integer(row map[string]json2.Any, name string) !int { return field(row, name)!.int() }

pub fn callback(operation string, row map[string]json2.Any, pointer voidptr) !json2.Any {
	if pointer == unsafe { nil } { return error('font context is absent') }
	mut ctx := unsafe { &Context(pointer) }
	cachecli.checkpoint()!
	match operation {
		'print' {
			println(field(row, 'text')!.str())
			flush_stdout()
			return json2.Null{}
		}
		'fetch' {
			work := sourcecommand.temporary('vinix-font-fetch')!
			defer { os.rmdir_all(work) or {} }
			limit := integer(row, 'timeout')!.str()
			result := sourcecommand.capture_full(['curl', '--fail', '--location', '--silent',
				'--show-error', '--connect-timeout', limit, '--speed-limit', '1', '--speed-time',
				limit, '--output', work + '/data', field(row, 'url')!.str()], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
			if result.status != 0 { return error(result.stderr.trim_space()) }
			return json2.Any(os.read_bytes(work + '/data')!.hex())
		}
		'open' {
			font := ctx.library.open(hex.decode(field(row, 'path')!.str())!.bytestr(), integer(row, 'size')!)!
			ctx.next_font++
			ctx.fonts[ctx.next_font] = &OwnedFont{ font: font, owners: {
				field(row, 'owner')!.str(): true
			} }
			return json2.Any(ctx.next_font)
		}
		'pin' {
			id := integer(row, 'font')!
			mut item := ctx.fonts[id] or { return error('unknown font identity') }
			item.owners[field(row, 'owner')!.str()] = true
			return json2.Null{}
		}
		'release' {
			owner := field(row, 'owner')!.str()
			for value in field(row, 'fonts')!.as_array() {
				id := value.int()
				mut item := ctx.fonts[id] or { continue }
				item.owners.delete(owner)
				if item.owners.len == 0 {
					item.font.close()
					ctx.fonts.delete(id)
				}
			}
			return json2.Null{}
		}
		'metrics' {
			item := ctx.fonts[integer(row, 'font')!] or { return error('unknown font identity') }
			return json2.Any(item.font.metrics()!.map(json2.Any(it)))
		}
		'bbox', 'length', 'mask' {
			glyph := ctx.glyph(integer(row, 'font')!, integer(row, 'code_point')!)!
			if operation == 'bbox' {
				return json2.Any([glyph.bx, glyph.by, glyph.bx + glyph.width, glyph.by + glyph.height].map(json2.Any(it)))
			}
			if operation == 'length' {
				return json2.Any({
					'float': json2.Any((f64(glyph.advance64) / 64).str())
				})
			}
			ctx.next_mask++
			ctx.masks[ctx.next_mask] = glyph
			return json2.Any({
				'width':  json2.Any(glyph.width)
				'height': json2.Any(glyph.height)
				'mask':   json2.Any(ctx.next_mask)
			})
		}
		'pixels' {
			glyph := ctx.masks[integer(row, 'mask')!] or { return error('unknown glyph mask identity') }
			return json2.Any(glyph.pixels.hex())
		}
		'mask_release' {
			ctx.masks.delete(integer(row, 'mask')!)
			return json2.Null{}
		}
		'fonttools_import' { return json2.Null{} }
		'tt_open' {
			font := ttf(hex.decode(field(row, 'data')!.str())!)!
			ctx.next_tt++
			ctx.tt[ctx.next_tt] = &Ttf{ ...font }
			return json2.Any(ctx.next_tt)
		}
		'tt_close' {
			id := integer(row, 'font')!
			if mut item := ctx.tt[id] {
				item.close()
				ctx.tt.delete(id)
			}
			return json2.Null{}
		}
		'tt_cmap', 'tt_subset', 'tt_instantiate', 'tt_records', 'tt_set_name', 'tt_save' {
			mut font := ctx.tt[integer(row, 'font')!] or { return error('unknown SFNT identity') }
			match operation {
				'tt_cmap' { return json2.Any(font.cmap()!.map(json2.Any(it))) }
				'tt_subset' {
					if field(row, 'layout_features')!.as_array().len != 0 {
						return error('native Japanese subset expects empty layout features')
					}
					font.subset(field(row, 'runes')!.as_array().map(it.int()), field(row, 'name_ids')!.as_array().map(it.int()))!
					return json2.Null{}
				}
				'tt_instantiate' {
					if field(row, 'inplace')!.bool() {
						return error('native subset instantiation requires a new owner')
					}
					static_font := font.instantiate(integer(row, 'weight')!)!
					ctx.next_tt++
					ctx.tt[ctx.next_tt] = &Ttf{ ...static_font }
					return json2.Any(ctx.next_tt)
				}
				'tt_records' {
					return json2.Any(font.records()!.map(json2.Any([it.id, it.platform, it.encoding,
						it.language].map(json2.Any(it)))))
				}
				'tt_set_name' {
					record := field(row, 'record')!.as_array().map(it.int())
					if record.len != 4 { return error('invalid font name record') }
					font.renamed[record.map(it.str()).join(':')] = field(row, 'name')!.str()
					return json2.Null{}
				}
				'tt_save' {
					os.write_file_array(hex.decode(field(row, 'path')!.str())!.bytestr(), font.publication()!)!
					return json2.Null{}
				}
				else { return error('unknown SFNT operation') }
			}
		}
		else { return error('unknown native font callback: ' + operation) }
	}
}
