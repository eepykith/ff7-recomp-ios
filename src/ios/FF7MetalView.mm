#import "FF7MetalView.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include "ff7_platform.h"

@implementation FF7MetalView {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _queue;
  CADisplayLink *_link;
}

+ (Class)layerClass {
  return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) {
    return nil;
  }
  _device = MTLCreateSystemDefaultDevice();
  CAMetalLayer *layer = (CAMetalLayer *)self.layer;
  layer.device = _device;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = YES;
  layer.opaque = YES;
  _queue = [_device newCommandQueue];
  self.backgroundColor = [UIColor blackColor];
  self.multipleTouchEnabled = YES;
  _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
  [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  return self;
}

- (void)dealloc {
  [_link invalidate];
  ff7_platform_set_window(NULL, 0, 0);
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  _link.paused = (self.window == nil);
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CAMetalLayer *layer = (CAMetalLayer *)self.layer;
  CGFloat scale = self.window.screen.scale;
  if (scale <= 0) {
    scale = UIScreen.mainScreen.scale;
  }
  layer.contentsScale = scale;
  CGSize drawable = CGSizeMake(self.bounds.size.width * scale,
                               self.bounds.size.height * scale);
  if (drawable.width < 1 || drawable.height < 1) {
    return;
  }
  layer.drawableSize = drawable;
  ff7_platform_set_window((__bridge void *)layer, (int)drawable.width,
                          (int)drawable.height);
}

- (void)tick:(CADisplayLink *)link {
  (void)link;
  if (ff7_engine_owns_present()) {
    ff7_platform_note_present();
    return;
  }
  CAMetalLayer *layer = (CAMetalLayer *)self.layer;
  id<CAMetalDrawable> drawable = [layer nextDrawable];
  if (!drawable || !_queue) {
    return;
  }
  float r = 0, g = 0, b = 0, a = 1;
  ff7_platform_clear_color(&r, &g, &b, &a);
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = drawable.texture;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, a);
  id<MTLCommandBuffer> buffer = [_queue commandBuffer];
  id<MTLRenderCommandEncoder> encoder =
      [buffer renderCommandEncoderWithDescriptor:pass];
  [encoder endEncoding];
  [buffer presentDrawable:drawable];
  [buffer commit];
  ff7_platform_note_present();
}

@end
