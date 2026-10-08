// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import json2

fn test_exact_numeric_metadata() {
	assert equal(Value(Number{'493', true, ''}), Value(Number{'493', true, ''}))
	assert equal(Value(Number{'2.0', false, ''}), Value(Number{'2', true, ''}))
	assert equal(Value(true), Value(Number{'1', true, ''}))
	assert !equal(Value(Number{'inf', false, ''}), Value(Number{'1' + '0'.repeat(400), true, ''}))
	assert !equal(Value(Number{'nan', false, 'same'}), Value(Number{'nan', false, 'same'}))
	assert equal(Value({'x': Value(Number{'nan', false, 'same'})}), Value({'x': Value(Number{'nan', false, 'same'})}))
	assert !equal(Value({'x': Value(Number{'nan', false, 'a'})}), Value({'x': Value(Number{'nan', false, 'b'})}))
	assert equal(Value({'x': Value('abc'), 'n': Value(Number{'418', true, ''})}), Value({'n': Value(Number{'418', true, ''}), 'x': Value('abc')}))
	assert scalar_length('\xed\xa0\x80'.repeat(64)) == 64
	assert scalar_length('é'.repeat(64)) == 64
	assert !truth(Value(json2.Null{}))
}
