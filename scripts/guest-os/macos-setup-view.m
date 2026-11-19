#import "macos-setup-view.h"
#include <math.h>

@interface CageDesktopWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation CageDesktopWindowDelegate
// The virtual machine runner is a background process. Once the desktop window
// is gone it must not keep a Dock or menu bar presence.
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
}
@end

@implementation CageGuestSetupView {
    NSWindow *_window;
    VZVirtualMachineView *_view;
    BOOL (^_authorized)(void);
    CageDesktopWindowDelegate *_desktopDelegate;
    BOOL _desktopSized;
}

- (instancetype)initWithMachine:(VZVirtualMachine *)machine
                            size:(NSSize)size
                 setupAuthorized:(BOOL (^)(void))setupAuthorized {
    if (!NSThread.isMainThread || !machine || !setupAuthorized || !setupAuthorized() ||
        !isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0) return nil;
    self = [super init];
    if (self) {
        _authorized = [setupAuthorized copy];
        NSRect rect = NSMakeRect(0, 0, size.width, size.height);
        _window = [[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered defer:NO];
        _window.excludedFromWindowsMenu = YES;
        _view = [[VZVirtualMachineView alloc] initWithFrame:rect];
        _view.virtualMachine = machine;
        _window.contentView = _view;
        [_window makeFirstResponder:_view];
    }
    return self;
}

- (BOOL)canUseView {
    if (!NSThread.isMainThread) return NO;
    if (!_view || !_authorized || !_authorized()) {
        [self close];
        return NO;
    }
    return YES;
}

- (NSData *)snapshotType:(NSBitmapImageFileType)type properties:(NSDictionary *)properties {
    if (![self canUseView]) return nil;
    NSBitmapImageRep *rep = [_view bitmapImageRepForCachingDisplayInRect:_view.bounds];
    if (!rep) return nil;
    [_view cacheDisplayInRect:_view.bounds toBitmapImageRep:rep];
    NSData *data = [rep representationUsingType:type properties:properties];
    return [self canUseView] ? data : nil;
}

- (NSData *)snapshotPNG { return [self snapshotType:NSBitmapImageFileTypePNG properties:@{}]; }
- (NSData *)snapshotJPEG {
    return [self snapshotType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.92}];
}

- (BOOL)sendKey:(NSEvent *)event {
    if (![self canUseView]) return NO;
    NSEventType kind = event.type;
    if (kind != NSEventTypeKeyDown && kind != NSEventTypeKeyUp && kind != NSEventTypeFlagsChanged) return NO;
    BOOL flagsOnly = kind == NSEventTypeFlagsChanged;
    NSEvent *target = [NSEvent keyEventWithType:kind location:NSZeroPoint modifierFlags:event.modifierFlags
                                      timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_window.windowNumber
                                        context:nil characters:flagsOnly ? @"" : event.characters ?: @""
                     charactersIgnoringModifiers:flagsOnly ? @"" : event.charactersIgnoringModifiers ?: @""
                                      isARepeat:!flagsOnly && event.isARepeat keyCode:event.keyCode];
    if (kind == NSEventTypeKeyDown) [_view keyDown:target];
    else if (kind == NSEventTypeKeyUp) [_view keyUp:target];
    else [_view flagsChanged:target];
    return YES;
}

- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y {
    if (![self canUseView]) return NO;
    NSRect rect = _view.bounds;
    if (!isfinite(x) || !isfinite(y) || x < 0 || y < 0 || x >= NSWidth(rect) || y >= NSHeight(rect)) return NO;
    NSPoint point = [_view convertPoint:NSMakePoint(x, NSHeight(rect) - y) toView:nil];
    for (NSNumber *type in @[@(NSEventTypeLeftMouseDown), @(NSEventTypeLeftMouseUp)]) {
        if (![self canUseView]) return NO;
        NSEvent *event = [NSEvent mouseEventWithType:type.unsignedIntegerValue location:point modifierFlags:0
                                          timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_window.windowNumber
                                            context:nil eventNumber:1 clickCount:1 pressure:1];
        if (event.type == NSEventTypeLeftMouseDown) [_view mouseDown:event];
        else [_view mouseUp:event];
    }
    return YES;
}

- (BOOL)scrollAtX:(CGFloat)x y:(CGFloat)y deltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    if (![self canUseView]) return NO;
    NSRect rect = _view.bounds;
    if (!isfinite(x) || !isfinite(y) || !isfinite(deltaX) || !isfinite(deltaY) ||
        x < 0 || y < 0 || x >= NSWidth(rect) || y >= NSHeight(rect) ||
        fabs(deltaX) > 4096 || fabs(deltaY) > 4096) return NO;
    NSPoint point = [_view convertPoint:NSMakePoint(x, NSHeight(rect) - y) toView:nil];
    NSEvent *move = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_window.windowNumber
        context:nil eventNumber:0 clickCount:0 pressure:0];
    [_view mouseMoved:move];
    CGEventRef wheel = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, (int32_t)deltaY, (int32_t)deltaX);
    if (!wheel) return NO;
    // A new CG event inherits the host pointer location. Retarget the hidden
    // window at the screen origin before the VZ view maps it into the guest.
    NSPoint screen = [_window convertPointToScreen:point];
    CGEventSetLocation(wheel, CGPointMake(screen.x, NSMaxY(NSScreen.screens.firstObject.frame) - screen.y));
    NSEvent *event = [NSEvent eventWithCGEvent:wheel];
    CFRelease(wheel);
    if (!event || ![self canUseView]) return NO;
    [_view scrollWheel:event];
    return YES;
}

- (void)close {
    NSAssert(NSThread.isMainThread, @"Close the setup view on the AppKit main thread.");
    _authorized = nil;
    _view.virtualMachine = nil;
    _window.contentView = nil;
    _view = nil;
    _window = nil;
    _desktopDelegate = nil;
}

- (void)showDesktop {
    if (![self canUseView]) return;
    if (!_desktopDelegate) _desktopDelegate = [CageDesktopWindowDelegate new];
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    if (_window.styleMask != style) {
        _window.styleMask = style;
        _window.title = @"Cage 客机桌面";
        _window.releasedWhenClosed = NO;
        _window.delegate = _desktopDelegate;
        [_window setContentMinSize:NSMakeSize(640, 400)];
    }
    if (!_desktopSized) {
        _desktopSized = YES;
        NSScreen *screen = NSScreen.mainScreen;
        NSRect visible = screen.visibleFrame, frame = _window.frame;
        if (!NSIsEmptyRect(visible) && frame.size.width > 0 && frame.size.height > 0) {
            CGFloat scale = fmin(1, fmin((NSWidth(visible) - 40) / NSWidth(frame),
                                         (NSHeight(visible) - 40) / NSHeight(frame)));
            if (scale > 0.2 && scale < 1) {
                frame.size = NSMakeSize(round(NSWidth(frame) * scale), round(NSHeight(frame) * scale));
                [_window setFrame:frame display:NO];
            }
        }
        [_window center];
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeFirstResponder:_view];
}

- (void)hideDesktop {
    if (!_window) return;
    [_window orderOut:nil];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
}

- (BOOL)desktopVisible {
    return _window != nil && _window.isVisible && self.canUseView;
}
@end
