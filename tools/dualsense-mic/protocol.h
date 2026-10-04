#ifndef VIBEWAND_DUALSENSE_MIC_PROTOCOL_H
#define VIBEWAND_DUALSENSE_MIC_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

enum { DS_INPUT_BYTES = 78, DS_MIC_CONTROL_BYTES = 142, DS_OPUS_BYTES = 71 };
typedef enum { DS_OTHER, DS_STATE, DS_MIC, DS_INVALID } DSReportKind;

static inline uint32_t ds_crc(uint8_t prefix, const uint8_t *bytes, size_t count) {
    return (uint32_t)crc32(crc32(0, &prefix, 1), bytes, (uInt)count);
}
static inline void ds_store32(uint8_t *bytes, uint32_t value) {
    for (int i = 0; i < 4; ++i) bytes[i] = (uint8_t)(value >> (i * 8));
}
static inline uint32_t ds_load32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 |
        (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}
static inline void ds_mic_control(uint8_t packet[DS_MIC_CONTROL_BYTES], unsigned sequence, bool on) {
    memset(packet, 0, DS_MIC_CONTROL_BYTES);
    packet[0] = 0x32;
    packet[1] = (uint8_t)((sequence & 15) << 4);
    packet[2] = 0x91; packet[3] = 7; packet[4] = on ? 0xff : 0xfe;
    memset(packet + 5, 64, 5);
    ds_store32(packet + 138, ds_crc(0xa2, packet, 138));
}
static inline DSReportKind ds_classify(const uint8_t *bytes, size_t count) {
    if (!bytes || !count) return DS_INVALID;
    if (bytes[0] != 0x31) return DS_OTHER;
    if (count != DS_INPUT_BYTES || ds_load32(bytes + 74) != ds_crc(0xa1, bytes, 74)) return DS_INVALID;
    // Both bits can be set. Audio MUST take precedence over gamepad state.
    if (bytes[1] & 2) return DS_MIC;
    if (bytes[1] & 1) return DS_STATE;
    return DS_OTHER;
}
#endif
