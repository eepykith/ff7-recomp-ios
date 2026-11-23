/* Offscreen-capable CAMetalLayer for Darwin ff7_metal_boot (Rosetta/native). */
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include "ff7_platform.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static NSWindow *g_win;
static CAMetalLayer *g_layer;

extern "C" int ff7_mac_metal_window_create(int width, int height) {
  @autoreleasepool {
    if (width <= 0) width = 1280;
    if (height <= 0) height = 720;

    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
      fprintf(stderr, "[mac] MTLCreateSystemDefaultDevice failed\n");
      return -1;
    }

    g_layer = [CAMetalLayer layer];
    g_layer.device = device;
    g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    g_layer.framebufferOnly = YES;
    g_layer.drawableSize = CGSizeMake(width, height);
    g_layer.contentsScale = 1.0;

    NSRect frame = NSMakeRect(80, 80, width, height);
    g_win = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    g_win.title = @"ff7_metal_boot";
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    view.wantsLayer = YES;
    view.layer = g_layer;
    g_win.contentView = view;
    [g_win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if (getenv("FF7_SNAPSHOT")) {
      /* Capture self-test: one red frame before the engine owns the layer. */
      id<CAMetalDrawable> d = [g_layer nextDrawable];
      MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
      rp.colorAttachments[0].texture = d.texture;
      rp.colorAttachments[0].loadAction = MTLLoadActionClear;
      rp.colorAttachments[0].storeAction = MTLStoreActionStore;
      rp.colorAttachments[0].clearColor = MTLClearColorMake(0.8, 0.1, 0.1, 1.0);
      id<MTLCommandQueue> q = [device newCommandQueue];
      id<MTLCommandBuffer> cb = [q commandBuffer];
      [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
      [cb presentDrawable:d];
      [cb commit];
    }
    ff7_platform_set_window((__bridge void *)g_layer, width, height);
    fprintf(stderr, "[mac] CAMetalLayer %p %dx%d device=%s\n",
            (__bridge void *)g_layer, width, height,
            [[device name] UTF8String] ?: "?");
    return 0;
  }
}

/* Dev aid: FF7_SNAPSHOT=/path/shot.png writes the window to a PNG every 5 s. Capturing a
 * window of this process needs no Screen Recording grant. CGWindowListCreateImage is
 * obsoleted in the macOS 15 SDK headers but still exported, so it is looked up at runtime. */
static void ff7_mac_snapshot_tick(void) {
  static const char *path;
  static int checked;
  static time_t last;
  if (!checked) { checked = 1; path = getenv("FF7_SNAPSHOT"); }
  if (!path || !g_win) return;
  time_t now = time(NULL);
  if (now - last < 5) return;
  last = now;
  typedef CGImageRef (*cap_fn)(CGRect, uint32_t, uint32_t, uint32_t);
  static cap_fn cap;
  if (!cap) cap = (cap_fn)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
  if (!cap) return;
  /* kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1 */
  CGImageRef img = cap(CGRectNull, 8, (uint32_t)g_win.windowNumber, 1);
  if (!img) return;
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
  NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  [png writeToFile:[NSString stringWithUTF8String:path] atomically:YES];
  CGImageRelease(img);
}

extern "C" void ff7_mac_metal_window_pump(void) {
  @autoreleasepool {
    ff7_mac_snapshot_tick();
    NSEvent *ev;
    while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                    untilDate:[NSDate distantPast]
                                       inMode:NSDefaultRunLoopMode
                                      dequeue:YES])) {
      [NSApp sendEvent:ev];
    }
  }
}
