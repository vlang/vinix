#pragma once

#include <stdint.h>

uint8_t inb(uint16_t port);
void outb(uint16_t port, uint8_t value);
