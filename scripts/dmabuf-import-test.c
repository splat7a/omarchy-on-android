// Standalone check of EGL dma-buf import on the KGSL Mesa path, mirroring what Hyprland does with
// Anland's buffers: allocate a linear RGBA buffer, export it, import it back with an explicit pitch.
// cc -O1 -o dmabuf-import-test dmabuf-import-test.c -lgbm -lEGL
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm_fourcc.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static PFNEGLCREATEIMAGEKHRPROC createImage;

static void try_import(EGLDisplay dpy, int fd, int w, int h, int pitch, unsigned long long mod, const char *label) {
    EGLint attrs[] = {
        EGL_WIDTH, w, EGL_HEIGHT, h, EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_ABGR8888,
        EGL_DMA_BUF_PLANE0_FD_EXT, fd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0, EGL_DMA_BUF_PLANE0_PITCH_EXT, pitch,
        EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLint)(mod & 0xffffffff), EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLint)(mod >> 32),
        EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    EGLImageKHR img = createImage(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attrs);
    printf("%-34s %dx%d pitch=%d mod=0x%llx -> %s (0x%x)\n", label, w, h, pitch, mod,
           img != EGL_NO_IMAGE_KHR ? "OK" : "FAILED", img != EGL_NO_IMAGE_KHR ? 0 : eglGetError());
}

int main(int argc, char **argv) {
    const char *node = argc > 1 ? argv[1] : "/dev/dri/renderD128";
    int w = 1440, h = 2953;
    int drm = open(node, O_RDWR | O_CLOEXEC);
    struct gbm_device *gbm = gbm_create_device(drm);
    if (!gbm) { printf("gbm_create_device failed\n"); return 1; }
    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplay = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay dpy = getPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    if (!eglInitialize(dpy, NULL, NULL)) { printf("eglInitialize failed 0x%x\n", eglGetError()); return 1; }
    createImage = (void *)eglGetProcAddress("eglCreateImageKHR");
    printf("EGL vendor: %s\n", eglQueryString(dpy, EGL_VENDOR));
    struct gbm_bo *bo = gbm_bo_create(gbm, w, h, GBM_FORMAT_ABGR8888, GBM_BO_USE_LINEAR | GBM_BO_USE_RENDERING);
    if (!bo) { printf("gbm_bo_create linear failed\n"); return 1; }
    int fd = gbm_bo_get_fd(bo);
    int gpitch = gbm_bo_get_stride(bo);
    printf("gbm linear bo: stride=%d modifier=0x%llx\n", gpitch, (unsigned long long)gbm_bo_get_modifier(bo));
    try_import(dpy, fd, w, h, gpitch, DRM_FORMAT_MOD_LINEAR, "gbm stride, LINEAR");
    try_import(dpy, fd, w, h, 1472 * 4, DRM_FORMAT_MOD_LINEAR, "Android stride 1472px, LINEAR");
    try_import(dpy, fd, w, h, 1472 * 4, DRM_FORMAT_MOD_INVALID, "Android stride 1472px, INVALID");
    try_import(dpy, fd, w, h, w * 4, DRM_FORMAT_MOD_LINEAR, "tight stride, LINEAR");
    return 0;
}
