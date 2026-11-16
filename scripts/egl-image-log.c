// LD_PRELOAD shim: log every eglCreateImageKHR dma-buf import (attributes + result) to stderr.
// cc -O1 -shared -fPIC -o egl-image-log.so egl-image-log.c -ldl
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static PFNEGLCREATEIMAGEKHRPROC real_create;
typedef void *(*gpa_t)(const char *);
static gpa_t real_gpa;

static EGLImageKHR logged_create(EGLDisplay d, EGLContext c, EGLenum target, EGLClientBuffer b, const EGLint *a) {
    EGLImageKHR img = real_create(d, c, target, b, a);
    if (target == EGL_LINUX_DMA_BUF_EXT) {
        fprintf(stderr, "[egl-image-log] import ->%s err=0x%x attrs:", img ? "OK" : "FAIL", img ? 0 : eglGetError());
        for (int i = 0; a && a[i] != EGL_NONE && i < 64; i += 2) fprintf(stderr, " %x=%d", a[i], a[i + 1]);
        fprintf(stderr, "\n");
    }
    return img;
}

__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name) {
    if (!real_gpa) real_gpa = (gpa_t)dlsym(RTLD_NEXT, "eglGetProcAddress");
    void *f = real_gpa(name);
    if (name && !strcmp(name, "eglCreateImageKHR")) {
        real_create = (PFNEGLCREATEIMAGEKHRPROC)f;
        return (__eglMustCastToProperFunctionPointerType)logged_create;
    }
    return (__eglMustCastToProperFunctionPointerType)f;
}
