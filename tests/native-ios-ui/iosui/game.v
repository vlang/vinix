// SPDX-License-Identifier: GPL-2.0-or-later
module iosui

import encoding.binary
import gamehost
import strconv

pub fn elements(tree Element) []Element {
	mut result := [tree]
	for child in tree.children { result << elements(child) }
	return result
}

pub fn board(tree Element) !(int, []int) {
	all := elements(tree)
	scores := all.filter(it.text.starts_with('SCORE: '))
	if scores.len != 1 { return error('expected one score label') }
	score := strconv.common_parse_int(scores[0].text[7..], 10, 32, true, true)!
	mut tiles := []int{}
	for item in all {
		if item.kind == 2 && item.text.len > 0 && item.text.bytes().all(it.is_digit()) {
			value := int(strconv.common_parse_int(item.text, 10, 32, true, true)!)
			if value < 2 || (value & (value - 1)) != 0 {
				return error('invalid tile: ' + item.text)
			}
			tiles << value
		}
	}
	if tiles.len > 16 { return error('too many tiles') }
	return int(score), tiles
}

fn pointer_payload(values []int) []u8 {
	mut result := []u8{len: values.len * 4}
	for index, value in values {
		binary.little_endian_put_u32(mut result[index * 4..index * 4 + 4], u32(i32(value)))
	}
	return result
}

fn (mut connection Client) settle() !Element {
	gamehost.pause(0.32)!
	connection.send(4, [])!
	return connection.build()!
}

pub fn game2048(runner string, binary_path string, cycles int) ! {
	mut connection := client(runner, binary_path)!
	defer { connection.close() or { connection.child.close() or {} } }
	mut tree := connection.build()!
	play := elements(tree).filter(it.text == 'Play Game')
	if play.len != 1 || play[0].kind != 4 { return error('expected Play Game button') }
	connection.send(2, play[0].id.bytes())!
	mut score, mut tiles := board(connection.build()!)!
	if score != 0 || tiles != [2, 2] { return error('unexpected initial 2048 board') }
	mut saw_merge := false
	mut last_score := score
	directions := [[310, 340, 90, 340], [195, 450, 195, 220], [90, 340, 310, 340],
		[195, 220, 195, 450]]
	for index := 0; index < cycles; index++ {
		direction := directions[index % 4]
		connection.send(5, pointer_payload([1, 1, 0, direction[0], direction[1], 390, 680]))!
		connection.send(5, pointer_payload([2, 1, 0, direction[2], direction[3], 390, 680]))!
		tree = connection.settle()!
		score, tiles = board(tree)!
		if score < last_score { return error('2048 score decreased') }
		saw_merge = saw_merge || (score > last_score && tiles.any(it >= 4))
		last_score = score
		if elements(tree).any(it.text in ['Defeat!', 'Victory!']) {
			ok := elements(tree).filter(it.text == 'OK')
			if ok.len != 1 { return error('expected alert OK button') }
			connection.send(2, ok[0].id.bytes())!
			break
		}
	}
	if !saw_merge || last_score <= 0 { return error('2048 swipes did not merge tiles') }
	connection.send(3, '\x1b[D'.bytes())!
	connection.settle()!
	connection.close()!
	println('iOS-2048: upstream launch, presentation, swipes, merges, score=${last_score}, timers and keyboard passed')
}
