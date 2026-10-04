#include "AudioRing.h"
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define CAPACITY 48000
struct DSMRing {
    _Atomic uint64_t written, read;
    _Atomic bool active;
    _Atomic unsigned long underruns, overflows;
    bool primed; // Audio render thread only.
    float data[CAPACITY];
};
DSMRing *dsm_create(void) { return calloc(1, sizeof(DSMRing)); }
void dsm_destroy(DSMRing *r) { free(r); }
void dsm_enable(DSMRing *r, bool active) { atomic_store(&r->active, active); }
size_t dsm_push(DSMRing *r, const float *samples, size_t count) {
    if (!atomic_load(&r->active)) return 0;
    uint64_t w=atomic_load_explicit(&r->written,memory_order_relaxed);
    uint64_t rd=atomic_load_explicit(&r->read,memory_order_acquire);
    if (count > CAPACITY || w-rd+count > CAPACITY) { atomic_fetch_add(&r->overflows,1); return 0; }
    for(size_t i=0;i<count;i++) r->data[(w+i)%CAPACITY]=samples[i];
    atomic_store_explicit(&r->written,w+count,memory_order_release);
    return count;
}
void dsm_render(DSMRing *r, float *out, size_t count) {
    memset(out,0,count*sizeof(float));
    uint64_t w=atomic_load_explicit(&r->written,memory_order_acquire);
    uint64_t rd=atomic_load_explicit(&r->read,memory_order_relaxed);
    if (!atomic_load(&r->active)) { r->primed=false; atomic_store(&r->read,w); return; }
    if (w-rd > 9600) { rd=w-4800; atomic_store(&r->read,rd); r->primed=false; }
    if (!r->primed) { if(w-rd<4800) return; r->primed=true; }
    if (w-rd<count) { r->primed=false; atomic_fetch_add(&r->underruns,1); return; }
    for(size_t i=0;i<count;i++) out[i]=r->data[(rd+i)%CAPACITY];
    atomic_store_explicit(&r->read,rd+count,memory_order_release);
}
unsigned long dsm_underruns(DSMRing *r) { return atomic_load(&r->underruns); }
unsigned long dsm_overflows(DSMRing *r) { return atomic_load(&r->overflows); }
