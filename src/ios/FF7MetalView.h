#import <UIKit/UIKit.h>

/* CAMetalLayer host. bgfx will take this layer via ff7_platform_window().
 * Until FFNx is linked, the view clears the drawable itself. */
@interface FF7MetalView : UIView
@end
