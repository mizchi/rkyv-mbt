// SPDX-License-Identifier: Apache-2.0

#include <moonbit.h>
#include <stdint.h>
#include <string.h>

// The MoonBit caller has already checked both source and destination spans.
// `UInt` is a 32-bit scalar. The common native path copies little-endian
// archived words in bulk; a big-endian host decodes explicitly instead.
MOONBIT_FFI_EXPORT void rkyv_copy_validated_u32s(
    const uint8_t *source, int32_t source_offset, uint32_t *destination,
    int32_t length) {
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  for (int32_t index = 0; index < length; ++index) {
    const uint8_t *input = source + source_offset + index * 4;
    destination[index] = (uint32_t)input[0] | ((uint32_t)input[1] << 8) |
                         ((uint32_t)input[2] << 16) |
                         ((uint32_t)input[3] << 24);
  }
#else
  memcpy(destination, source + source_offset, (size_t)length * sizeof(uint32_t));
#endif
}
