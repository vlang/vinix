// SPDX-License-Identifier: GPL-2.0-or-later
module iosui

import cachecli

pub const calculator_cases = [
	['7+5=', '12'],
	['3-9=', '-6'],
	['12*8=', '96'],
	['81/9=', '9'],
	['0.1+0.2=', '0.3'],
	['0002.50+0.25=', '2.75'],
	['2+3*4=', '20'],
	['5+*2=', '10'],
	['5+=', '10'],
	['2+3===', '11'],
	['2+3=7', '7'],
	['2+3=C', '0'],
	['200+10%=', '220'],
	['200-10%=', '180'],
	['200*10%=', '20'],
	['50%=', '0.5'],
	['2s+5=', '3'],
	['s2+5=', '3'],
	['2ss', '2'],
	['5+s2=', '3'],
	['1/0=', 'Error'],
	['1/0=+', 'Error'],
	['1/0=7+2=', '9'],
	['1/0=C', '0'],
	['0..25', '0.25'],
	['1234567890123456', '123456789012345'],
	['9' + '*='.repeat(12), 'Error'],
]

pub fn uikit(runner string, binary_path string) ! {
	mut client := client(runner, binary_path)!
	defer { client.child.close() or {} }
	mut tree := client.build()!
	assert tree.kind == 0 && tree.children.len == 20
	mut buttons := map[string]Element{}
	for child in tree.children { if child.kind == 4 { buttons[child.text] = child } }
	assert buttons.len == 19 && tree.children[0].text == '0'
	titles := {
		'C': 'AC'
		's': '±'
		'*': '×'
		'-': '−'
		'/': '÷'
	}
	for row in calculator_cases {
		client.send(2, buttons['AC'].id.bytes())!
		for key in row[0].runes() {
			title := titles[key.str()] or { key.str() }
			button := buttons[title] or { return error('calculator button is absent: ' + title) }
			client.send(2, button.id.bytes())!
		}
		actual := client.build()!.children[0].text
		assert actual == row[1], row[0] + ': expected ' + row[1] + ', got ' + actual
	}
	for dimensions in [[480, 800], [800, 480], [390, 680]] {
		tree = client.build_size(dimensions[0], dimensions[1])!
		for child in tree.children {
			x, y, width, height := child.frame[0], child.frame[1], child.frame[2], child.frame[3]
			assert x >= 0 && y >= 0 && width > 0 && height > 0
			assert x + width <= dimensions[0] + 0.001 && y + height <= dimensions[1] + 0.001
		}
	}
	client.send(3, 'C7+5='.bytes())!
	assert client.build()!.children[0].text == '12'
	for _ in 0 .. 1000 {
		cachecli.checkpoint()!
		client.send(3, 'C2+3='.bytes())!
		assert client.build()!.children[0].text == '5'
	}
	client.close()!
	println('UIKit Mach-O: 27 button cases, resize, keyboard and 1000 update cycles passed')
}
