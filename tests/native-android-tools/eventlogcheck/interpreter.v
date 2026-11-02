// SPDX-License-Identifier: GPL-2.0-or-later
module main

import strconv

// A deliberately narrow evaluator for this fieldless class's generated code.
// Unknown instructions, external calls, uninitialized register reads and
// excessive work are errors. Register names are symbolic; exact source/layout
// checks and DEX assembly validate the physical ABI. This is not an encoder.
struct Item {
	kind  string
	units []u16
}

struct Cell {
	kind   string
	number int
	units  []u16
	items  []Item
	text   string
}

struct Evaluation {
	code    int
	thrown  string
	message string
}

fn integer(value string) !int {
	negative := value.starts_with('-')
	unsigned := value.trim_left('-')
	number := if unsigned.starts_with('0x') {
		int(strconv.parse_int(unsigned[2..], 16, 32)!)
	} else {
		int(strconv.parse_int(unsigned, 10, 32)!)
	}
	return if negative { -number } else { number }
}

fn register(registers map[string]Cell, name string) !Cell {
	if name !in registers { return error('uninitialized register: ' + name) }
	return registers[name]
}

fn zero(cell Cell) bool {
	return cell.kind == 'null' || (cell.kind == 'number' && cell.number == 0)
}

fn evaluate(surface map[string]string, signature string, arguments map[string]Cell, depth int) !Evaluation {
	if depth > 1 || signature !in surface { return error('unsupported method invocation') }
	lines := norm(surface[signature]).split_into_lines().filter(!it.starts_with('.'))
	mut labels := map[string]int{}
	for index, line in lines { if line.starts_with(':') { labels[line] = index } }
	mut registers := arguments.clone()
	mut last := Cell{ kind: 'number' }
	mut pc := 0
	mut steps := 0
	for pc < lines.len {
		steps++
		if steps > 200000 { return error('instruction budget exceeded') }
		line := lines[pc]
		pc++
		if line.starts_with(':') { continue }
		op := line.all_before(' ')
		args := line.all_after(' ').split(', ')
		if op in ['const/4', 'const/16', 'const'] {
			literal := integer(args[1])!
			registers[args[0]] = Cell{ kind: 'number', number: if op == 'const/16' {
				int(i16(literal))
			} else {
				literal
			} }
		} else if op == 'const-string' {
			registers[args[0]] = Cell{ kind: 'Ljava/lang/String;', text: args[1].trim('"') }
		} else if op in ['move', 'move-object'] {
			registers[args[0]] = register(registers, args[1])!
		} else if op in ['move-result', 'move-result-object'] {
			registers[args[0]] = last
		} else if op.starts_with('if-') {
			left := register(registers, args[0])!
			mut take := false
			if op in ['if-eqz', 'if-nez'] {
				take = if op == 'if-eqz' { zero(left) } else { !zero(left) }
			} else {
				right := register(registers, args[1])!
				if left.kind != 'number' || right.kind != 'number' {
					return error('numeric branch required')
				}
				take = match op {
					'if-ge' { left.number >= right.number }
					'if-gt' { left.number > right.number }
					'if-le' { left.number <= right.number }
					'if-lt' { left.number < right.number }
					else { return error('unsupported branch: ' + op) }
				}
			}
			if args.last() !in labels { return error('missing branch destination') }
			if take { pc = labels[args.last()] }
		} else if op == 'goto' {
			if args[0] !in labels { return error('missing goto destination') }
			pc = labels[args[0]]
		} else if op == 'array-length' {
			array := register(registers, args[1])!
			if array.kind != '[Ljava/lang/Object;' { return error('array receiver required') }
			registers[args[0]] = Cell{ kind: 'number', number: array.items.len }
		} else if op == 'aget-object' {
			array := register(registers, args[1])!
			index := register(registers, args[2])!
			if array.kind != '[Ljava/lang/Object;' || index.kind != 'number' || index.number < 0 || index.number >= array.items.len {
				return error('invalid array read')
			}
			item := array.items[index.number]
			registers[args[0]] = Cell{ kind: item.kind, units: item.units }
		} else if op == 'instance-of' {
			item := register(registers, args[1])!
			registers[args[0]] = Cell{ kind: 'number', number: if item.kind == args[2] {
				1
			} else {
				0
			} }
		} else if op == 'check-cast' {
			item := register(registers, args[0])!
			if item.kind !in [args[1], 'null'] { return error('invalid cast') }
		} else if op in ['add-int', 'add-int/lit8'] {
			left := register(registers, args[1])!
			right := if op == 'add-int' {
				register(registers, args[2])!
			} else {
				Cell{ kind: 'number', number: integer(args[2])! }
			}
			if left.kind != 'number' || right.kind != 'number' {
				return error('numeric arithmetic required')
			}
			registers[args[0]] = Cell{ kind: 'number', number: left.number + right.number }
		} else if op == 'new-instance' {
			registers[args[0]] = Cell{ kind: args[1] }
		} else if op.starts_with('invoke-') {
			invoked := line.all_after('}, ')
			operands := line.all_after('{').all_before('}').split(', ')
			if op == 'invoke-virtual' && invoked == 'Ljava/lang/String;->length()I' {
				value := register(registers, operands[0])!
				if value.kind != 'Ljava/lang/String;' { return error('String receiver required') }
				last = Cell{ kind: 'number', number: value.units.len }
			} else if op == 'invoke-virtual' && invoked == 'Ljava/lang/String;->charAt(I)C' {
				value := register(registers, operands[0])!
				index := register(registers, operands[1])!
				if value.kind != 'Ljava/lang/String;' || index.kind != 'number' || index.number < 0 || index.number >= value.units.len {
					return error('invalid UTF16 read')
				}
				last = Cell{ kind: 'number', number: int(value.units[index.number]) }
			} else if op == 'invoke-static' && invoked == 'Landroid/util/EventLog;->vinixUtf8Length(Ljava/lang/String;)I' {
				result := evaluate(surface, 'vinixUtf8Length(Ljava/lang/String;)I', {
					'p0': register(registers, operands[0])!
				}, depth + 1)!
				if result.thrown != '' { return result }
				last = Cell{ kind: 'number', number: result.code }
			} else if op == 'invoke-direct' && invoked == 'Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V' {
				value := register(registers, operands[0])!
				message := register(registers, operands[1])!
				if value.kind != 'Ljava/lang/IllegalArgumentException;' || message.kind != 'Ljava/lang/String;' {
					return error('invalid exception constructor')
				}
				registers[operands[0]] = Cell{ kind: value.kind, text: message.text }
			} else {
				return error('unsupported invocation: ' + line)
			}
		} else if op == 'throw' {
			value := register(registers, args[0])!
			if value.kind != 'Ljava/lang/IllegalArgumentException;' {
				return error('unsupported throwable')
			}
			return Evaluation{ thrown: value.kind, message: value.text }
		} else if op == 'return' {
			value := register(registers, args[0])!
			if value.kind != 'number' { return error('numeric return required') }
			return Evaluation{ code: value.number }
		} else {
			return error('unsupported opcode: ' + line)
		}
	}
	return error('method did not return')
}
