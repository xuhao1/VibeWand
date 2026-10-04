#include "AudioRing.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
 DSMRing *r=dsm_create(); assert(r);
 float in[4800],out[480]; for(int i=0;i<4800;i++)in[i]=(float)i/4800;
 dsm_render(r,out,480); for(int i=0;i<480;i++)assert(out[i]==0);
 dsm_enable(r,true); assert(dsm_push(r,in,480)==480);
 dsm_render(r,out,480);for(int i=0;i<480;i++)assert(out[i]==0); // prebuffer
 assert(dsm_push(r,in+480,4320)==4320);dsm_render(r,out,480);
 for(int i=0;i<480;i++)assert(out[i]==in[i]);
 dsm_enable(r,false);dsm_render(r,out,480);for(int i=0;i<480;i++)assert(out[i]==0);
 dsm_enable(r,true);dsm_render(r,out,480);for(int i=0;i<480;i++)assert(out[i]==0); // no old speech
 for(int n=0;n<10;n++)assert(dsm_push(r,in,4800)==4800);
 assert(dsm_push(r,in,480)==0);assert(dsm_overflows(r)==1);
 dsm_render(r,out,480); // consumer trims stale queue and plays newest 100ms
 for(int i=0;i<480;i++)assert(out[i]==in[i]);
 dsm_destroy(r);puts("PASS: silence, prebuffer, mute flush, bounded overflow and stale-audio trim");
}
