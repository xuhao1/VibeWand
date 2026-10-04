// Bounded transport experiment. No virtual audio device, playback or speech upload.
#include "protocol.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <opus/opus.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static IOHIDDeviceRef device;
static OpusDecoder *decoder;
static volatile sig_atomic_t interrupted;
static atomic_bool stopWriter;
static atomic_uint receivedReports;
static unsigned intervalMS = 500, writeErrors, cleanupErrors;
static bool fullInitialization;
static bool quietSensors;
static int requestedReportUS;
static unsigned captureSeconds = 6;
static unsigned reports, normalReports, audio, decoded, invalid, decodeErrors;
static unsigned micDeltas[256], reportDeltas[16];
static int previousMic = -1, previousReport = -1, peak;
static unsigned long samples;
static double energy, firstAudio, lastAudio;
static uint8_t input[4096];

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
static void on_signal(int signalValue) { (void)signalValue; interrupted = 1; }
static void receive(void *context, IOReturn result, void *sender, IOHIDReportType type,
                    uint32_t reportID, uint8_t *bytes, CFIndex count) {
    (void)context; (void)sender; (void)type; (void)reportID;
    if (result || count <= 0) return;
    reports++; atomic_fetch_add(&receivedReports, 1);
    DSReportKind kind = ds_classify(bytes, (size_t)count);
    if (kind == DS_INVALID) { invalid++; return; }
    if (kind == DS_OTHER) return;
    int sequence = bytes[1] >> 4;
    if (previousReport >= 0) reportDeltas[(sequence - previousReport) & 15]++;
    previousReport = sequence;
    if (kind == DS_STATE) { normalReports++; return; }
    audio++;
    if (previousMic >= 0) micDeltas[(bytes[2] - previousMic) & 255]++;
    previousMic = bytes[2];
    lastAudio = now(); if (!firstAudio) firstAudio = lastAudio;
    int16_t pcm[5760];
    int countPCM = opus_decode(decoder, bytes + 3, DS_OPUS_BYTES, pcm, 5760, 0);
    if (countPCM < 0) { decodeErrors++; return; }
    decoded++; samples += countPCM;
    for (int i = 0; i < countPCM; ++i) {
        int v = abs((int)pcm[i]); if (v > peak) peak = v;
        energy += (double)pcm[i] * pcm[i];
    }
}
static IOReturn write_mic(unsigned sequence, bool on) {
    uint8_t packet[DS_MIC_CONTROL_BYTES]; ds_mic_control(packet, sequence, on);
    if (fullInitialization) {
        packet[10] = sequence & 15;
        packet[11] = 0x92; packet[12] = 0x40;
        ds_store32(packet + 138, ds_crc(0xa2, packet, 138));
    }
    IOReturn result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, packet[0], packet, sizeof(packet));
    if (result) { writeErrors++; if (!on) cleanupErrors++; }
    if (result || !on || sequence == 0) {
        printf("write on=%d sequence=%u result=0x%08x\n", on, sequence, result); fflush(stdout);
    }
    return result;
}
static IOReturn write_audio_state(bool on) {
    uint8_t packet[78] = {0x31, 0, 0x10};
    packet[3] = 0xc0; packet[4] = 0x82; // Volume, route, power and audio control 2; preserve LED.
    packet[9] = on ? 8 : 0; packet[10] = 9; packet[12] = on ? (quietSensors ? 3 : 0) : 0x10;
    packet[40] = 1;
    ds_store32(packet + 74, ds_crc(0xa2, packet, 74));
    IOReturn result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, packet[0], packet, sizeof(packet));
    if (result) { writeErrors++; if (!on) cleanupErrors++; }
    printf("audioState on=%d result=0x%08x\n", on, result); fflush(stdout);
    return result;
}
static void *writer(void *context) {
    (void)context; unsigned sequence = 0;
    // Refuse to enable audio on a connected-but-stalled controller.
    double deadline = now() + 1;
    while (now() < deadline && !interrupted && !atomic_load(&stopWriter)) usleep(10000);
    if (interrupted || atomic_load(&stopWriter) || !atomic_load(&receivedReports)) {
        fprintf(stderr, "No live baseline or interrupted; no microphone commands sent.\n"); return NULL;
    }
    if (fullInitialization && write_audio_state(true)) return NULL;
    deadline = now() + captureSeconds;
    while (!interrupted && !atomic_load(&stopWriter) && now() < deadline) {
        if (write_mic(sequence++, true)) break;
        double next = now() + intervalMS / 1000.0;
        while (!interrupted && !atomic_load(&stopWriter) && now() < next) usleep(1000);
    }
    // One writer owns both enable and disable, preventing a late enable after shutdown.
    for (int i = 0; i < 3; ++i) { write_mic(sequence++, false); usleep(100000); }
    if (fullInitialization) write_audio_state(false);
    return NULL;
}
int main(int argc, char **argv) {
    bool enable = false, exclusive = false;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--enable")) enable = true;
        else if (!strcmp(argv[i], "--exclusive")) exclusive = true;
        else if (!strcmp(argv[i], "--full-init")) fullInitialization = true;
        else if (!strcmp(argv[i], "--quiet-sensors")) { quietSensors = true; fullInitialization = true; }
        else if (!strcmp(argv[i], "--report-us") && i + 1 < argc) {
            char *end; long value = strtol(argv[++i], &end, 10);
            if (!argv[i][0] || *end || value < 1000 || value > 16000) return 2;
            requestedReportUS = (int)value;
        }
        else if (!strcmp(argv[i], "--seconds") && i + 1 < argc) {
            char *end; unsigned long value = strtoul(argv[++i], &end, 10);
            if (!argv[i][0] || *end || value < 1 || value > 120) return 2;
            captureSeconds = (unsigned)value;
        }
        else if (!strcmp(argv[i], "--interval-ms") && i + 1 < argc) {
            char *end; unsigned long value = strtoul(argv[++i], &end, 10);
            if (!argv[i][0] || *end || value < 10 || value > 500) return 2;
            intervalMS = (unsigned)value;
        } else {
            fprintf(stderr, "usage: %s [--enable --exclusive] [--full-init] [--quiet-sensors] [--interval-ms 10..500] [--report-us 1000..16000] [--seconds 1..120]\n", argv[0]); return 2;
        }
    }
    if (enable && !exclusive) { fprintf(stderr, "--enable requires --exclusive to isolate audio from gamepad input.\n"); return 2; }
    signal(SIGINT, on_signal); signal(SIGTERM, on_signal);
    int exitCode = 0, opusError;
    bool opened = false, scheduled = false, writerStarted = false;
    pthread_t thread;
    CFSetRef devices = NULL;
    CFTypeRef originalReportInterval = NULL;
    decoder = opus_decoder_create(48000, 1, &opusError);
    if (!decoder || opusError) return 3;
    IOHIDManagerRef manager = IOHIDManagerCreate(NULL, kIOHIDManagerOptionIndependentDevices);
    int vid = 0x054c, pid = 0x0ce6;
    CFNumberRef vendor = CFNumberCreate(NULL, kCFNumberIntType, &vid);
    CFNumberRef product = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *keys[] = {CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey), CFSTR(kIOHIDTransportKey)};
    const void *values[] = {vendor, product, CFSTR("Bluetooth")};
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);
    devices = IOHIDManagerCopyDevices(manager);
    if (!devices || CFSetGetCount(devices) != 1) {
        fprintf(stderr, "Expected one Bluetooth DualSense, found %ld.\n", devices ? CFSetGetCount(devices) : 0); exitCode = 4; goto cleanup;
    }
    CFSetGetValues(devices, (const void **)&device);
    IOReturn result = IOHIDDeviceOpen(device, exclusive ? kIOHIDOptionsTypeSeizeDevice : 0);
    printf("open exclusive=%d result=0x%08x\n", exclusive, result); fflush(stdout);
    if (result) { exitCode = 5; goto cleanup; }
    opened = true;
    if (requestedReportUS) {
        originalReportInterval = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDReportIntervalKey));
        if (!originalReportInterval) { exitCode=6; goto cleanup; }
        CFRetain(originalReportInterval);
        CFNumberRef value = CFNumberCreate(NULL, kCFNumberIntType, &requestedReportUS);
        printf("setReportIntervalUS=%d accepted=%d\n", requestedReportUS, IOHIDDeviceSetProperty(device, CFSTR(kIOHIDReportIntervalKey), value));
        CFRelease(value);
    }
    IOHIDDeviceRegisterInputReportCallback(device, input, sizeof(input), receive, NULL);
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode); scheduled = true;
    if (enable) {
        if (pthread_create(&thread, NULL, writer, NULL)) { exitCode = 6; goto cleanup; }
        writerStarted = true;
    }
    double started = now(), deadline = started + (enable ? captureSeconds + 4 : 4);
    while (!interrupted && now() < deadline) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    atomic_store(&stopWriter, true);
    if (writerStarted) { pthread_join(thread, NULL); writerStarted = false; }
    // Drain queued input so the summary includes evidence after disable.
    if (enable && !interrupted) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    unsigned missing = 0, ambiguous = 0;
    for (int delta = 2; delta < 128; ++delta) missing += micDeltas[delta] * (delta - 1);
    for (int delta = 128; delta < 256; ++delta) ambiguous += micDeltas[delta];
    double missingFraction = audio + missing ? (double)missing / (audio + missing) : 0;
    printf("reports=%u normal=%u audio=%u decoded=%u invalid=%u decodeErrors=%u samples=%lu peak=%d meanSquare=%.4f\n", reports, normalReports, audio, decoded, invalid, decodeErrors, samples, peak, samples ? energy/samples : 0);
    printf("wallSeconds=%.6f audioWallSeconds=%.6f decodedSeconds=%.6f missingSequenceFrames=%u missingFraction=%.4f ambiguousSequenceJumps=%u writeErrors=%u cleanupErrors=%u\n", now()-started, lastAudio-firstAudio, samples/48000.0, missing, missingFraction, ambiguous, writeErrors, cleanupErrors);
    for (int i=0;i<256;++i) if (micDeltas[i]) printf("micSequenceDelta[%d]=%u\n",i,micDeltas[i]);
    for (int i=0;i<16;++i) if (reportDeltas[i]) printf("reportSequenceDelta[%d]=%u\n",i,reportDeltas[i]);
    if (writeErrors || cleanupErrors) exitCode = 9;
    else if (!reports || (enable && !decoded)) exitCode = 7;
    else if (invalid || decodeErrors || ambiguous || (enable && missingFraction > 0.05)) exitCode = 8;
cleanup:
    atomic_store(&stopWriter, true);
    if (writerStarted) pthread_join(thread, NULL);
    if (scheduled) IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    if (originalReportInterval) {
        printf("restoreReportInterval accepted=%d\n", IOHIDDeviceSetProperty(device, CFSTR(kIOHIDReportIntervalKey), originalReportInterval));
        CFRelease(originalReportInterval);
    }
    if (opened) IOHIDDeviceClose(device, 0);
    if (devices) CFRelease(devices);
    CFRelease(match); CFRelease(vendor); CFRelease(product); CFRelease(manager);
    opus_decoder_destroy(decoder);
    return exitCode;
}
