#include "protocol.h"
#include <assert.h>
#include <opus/opus.h>
#include <stdio.h>

static void sign_input(uint8_t *packet) { ds_store32(packet + 74, ds_crc(0xa1, packet, 74)); }
int main(void) {
    uint8_t control[DS_MIC_CONTROL_BYTES];
    ds_mic_control(control, 0, true);
    // Independent golden values calculated with Python zlib, not the encoder under test.
    assert(ds_load32(control + 138) == 0x69f30dd7);
    ds_mic_control(control, 0, false);
    assert(ds_load32(control + 138) == 0x93e1fac1);
    ds_mic_control(control, 17, true); assert(control[1] == 0x10);

    uint8_t input[DS_INPUT_BYTES] = {0x31, 0x13, 255};
    int error;
    OpusEncoder *encoder = opus_encoder_create(48000, 1, OPUS_APPLICATION_AUDIO, &error);
    assert(encoder && error == OPUS_OK);
    assert(opus_encoder_ctl(encoder, OPUS_SET_VBR(0)) == OPUS_OK);
    assert(opus_encoder_ctl(encoder, OPUS_SET_BITRATE(56800)) == OPUS_OK);
    int16_t silence[480] = {0}, output[480];
    assert(opus_encode(encoder, silence, 480, input + 3, DS_OPUS_BYTES) == DS_OPUS_BYTES);
    sign_input(input);
    assert(ds_classify(input, sizeof(input)) == DS_MIC); // Both tag bits: never a joystick event.
    OpusDecoder *decoder = opus_decoder_create(48000, 1, &error);
    assert(decoder && error == OPUS_OK);
    assert(opus_decode(decoder, input + 3, DS_OPUS_BYTES, output, 480, 0) == 480);
    input[1] = 0x12; sign_input(input); assert(ds_classify(input, sizeof(input)) == DS_MIC);
    input[1] = 0x11; sign_input(input); assert(ds_classify(input, sizeof(input)) == DS_STATE);
    input[1] = 0x10; sign_input(input); assert(ds_classify(input, sizeof(input)) == DS_OTHER);
    input[1] = 0x12; sign_input(input); input[20] ^= 1;
    assert(ds_classify(input, sizeof(input)) == DS_INVALID);
    assert(ds_classify(input, 77) == DS_INVALID);
    assert(ds_classify(input, 79) == DS_INVALID); // Length checked before accessing any payload.
    assert(ds_classify(NULL, 0) == DS_INVALID);
    uint8_t shortReport[] = {1}; assert(ds_classify(shortReport, 1) == DS_OTHER);
    opus_decoder_destroy(decoder); opus_encoder_destroy(encoder);
    puts("PASS: golden CRC, sequence wrap, audio/state isolation, corrupt/truncated reports, Opus round trip");
}
