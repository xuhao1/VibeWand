#ifndef DSM_AUDIO_RING_H
#define DSM_AUDIO_RING_H
#include <stddef.h>
#include <stdbool.h>
typedef struct DSMRing DSMRing;
DSMRing *dsm_create(void);
void dsm_destroy(DSMRing *ring);
void dsm_enable(DSMRing *ring, bool active);
size_t dsm_push(DSMRing *ring, const float *samples, size_t count);
void dsm_render(DSMRing *ring, float *samples, size_t count);
unsigned long dsm_underruns(DSMRing *ring);
unsigned long dsm_overflows(DSMRing *ring);
#endif
