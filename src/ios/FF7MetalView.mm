#import "FF7MetalView.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include "ff7_platform.h"

@implementation FF7MetalView {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _queue;
  CADisplayLink *_link;
  CAMetalLayer *_metal;
}

/* The view's own layer is a replicator holding the game's CAMetalLayer, so the
 * iPhone Duo can show a second, mirrored copy below the picture (the screen
 * reflection). The copy is drawn by the render server: no extra GPU pass. */
+ (Class)layerClass {
  return [CAReplicatorLayer class];
}

- (void)setReflection:(BOOL)reflection {
  if (_reflection == reflection) {
    return;
  }
  _reflection = reflection;
  [self updateReplica];
}

- (void)updateReplica {
  CAReplicatorLayer *rep = (CAReplicatorLayer *)self.layer;
  CGFloat h = self.bounds.size.height;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  rep.instanceCount = _reflection ? 2 : 1;
  /* An opaque CAMetalLayer can go straight to the display, past the compositor;
   * replicated, the original then stays black on a device. Non-opaque keeps it
   * composited while the copy is shown. */
  _metal.opaque = !_reflection;
  /* flip about the bottom edge: y -> h - y around the layer's centre */
  rep.instanceTransform =
      CATransform3DScale(CATransform3DMakeTranslation(0, h, 0), 1, -1, 1);
  [CATransaction commit];
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) {
    return nil;
  }
  _device = MTLCreateSystemDefaultDevice();
  _metal = [CAMetalLayer layer];
  [self.layer addSublayer:_metal];
  CAMetalLayer *layer = _metal;
  layer.device = _device;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = YES;
  layer.opaque = YES;
  _queue = [_device newCommandQueue];
  self.backgroundColor = [UIColor blackColor];
  self.multipleTouchEnabled = YES;
  _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  /* up to the screen's own rate (120 Hz on ProMotion screens, Info.plist
   * CADisableMinimumFrameDurationOnPhone); FFNx's limiter sets the game's rate */
  _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);
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
  CAMetalLayer *layer = _metal;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.frame = self.layer.bounds;
  [CATransaction commit];
  [self updateReplica];
  CGFloat scale = self.traitCollection.displayScale;
  if (scale <= 0) {
    scale = self.window.screen.scale;
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
  CAMetalLayer *layer = _metal;
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
