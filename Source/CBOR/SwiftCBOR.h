/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdint.h>

// https://stackoverflow.com/questions/32959278/convert-half-precision-float-bytes-to-float-in-swift
static inline float loadFromF16(const uint16_t *pointer) { return *(const __fp16 *)pointer; }
static inline void storeAsF16(float value, uint16_t *pointer) { *(__fp16 *)pointer = value; }
