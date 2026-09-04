#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";
static BOOL pvEnabled = YES;

@interface SBVolumeControl : NSObject
@end

@interface PVOverlayController : NSObject
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIView *pillView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, assign) NSInteger hideGeneration;
+ (instancetype)sharedInstance;
- (void)prepareOverlay;
- (void)showVolume:(float)volume;
@end

static void PVLoadPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PVPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("Enabled"), (__bridge CFStringRef)PVPrefsDomain);
    pvEnabled = value ? CFBooleanGetValue((CFBooleanRef)value) : YES;
    if (value) CFRelease(value);
}

static void PVPrefsChangedCallback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    PVLoadPrefs();
}

static float PVReadVolumeFromController(id controller, float fallback) {
    NSArray<NSString *> *selectors = @[@"_effectiveVolume", @"volume", @"_volume", @"currentVolume"];

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            float (*msgSendFloat)(id, SEL) = (float (*)(id, SEL))objc_msgSend;
            float value = msgSendFloat(controller, selector);
            if (isfinite(value)) return fmaxf(0.0f, fminf(1.0f, value));
        }
    }

    return fmaxf(0.0f, fminf(1.0f, fallback));
}

@implementation PVOverlayController

+ (instancetype)sharedInstance {
    static PVOverlayController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [PVOverlayController new];
    });
    return controller;
}

- (UIWindowScene *)activeSpringBoardScene {
    UIWindowScene *fallback = nil;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (!fallback) fallback = windowScene;

        if (scene.activationState == UISceneActivationStateForegroundActive ||
            scene.activationState == UISceneActivationStateForegroundInactive) {
            return windowScene;
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop

    if ([keyWindow.windowScene isKindOfClass:UIWindowScene.class]) {
        return keyWindow.windowScene;
    }

    return fallback;
}

- (void)ensureOverlayWindow {
    UIWindowScene *scene = [self activeSpringBoardScene];
    if (!scene) return;

    if (!self.overlayWindow || self.overlayWindow.windowScene != scene) {
        self.overlayWindow.hidden = YES;

        self.overlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
        self.overlayWindow.frame = UIScreen.mainScreen.bounds;
        self.overlayWindow.backgroundColor = UIColor.clearColor;
        self.overlayWindow.opaque = NO;
        self.overlayWindow.userInteractionEnabled = NO;
        self.overlayWindow.rootViewController = [UIViewController new];

        // Keep this above Home Screen, apps, Control Centre and the Lock Screen cover sheet.
        self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 9000.0;
        self.overlayWindow.hidden = NO;
    }

    self.overlayWindow.frame = UIScreen.mainScreen.bounds;
    self.overlayWindow.hidden = NO;
}

- (CGRect)pillFrame {
    UIWindowScene *scene = self.overlayWindow.windowScene ?: [self activeSpringBoardScene];
    CGFloat statusHeight = 44.0;

    if (@available(iOS 13.0, *)) {
        CGFloat sceneStatusHeight = scene.statusBarManager.statusBarFrame.size.height;
        if (sceneStatusHeight >= 20.0) statusHeight = sceneStatusHeight;
    }

    // These numbers match the SVC-style pill in the LEFT status-bar/notch area.
    // Previous build was y=3 / h=38, which placed it too high and too chunky.
    const CGFloat width = 112.0;
    const CGFloat height = 34.0;
    const CGFloat x = 7.0;
    CGFloat y = floor((statusHeight - height) / 2.0) + 2.0;
    y = fmax(6.0, y);

    return CGRectMake(x, y, width, height);
}

- (void)buildPillIfNeeded {
    if (self.pillView) return;

    CGRect frame = [self pillFrame];

    self.pillView = [[UIView alloc] initWithFrame:frame];
    self.pillView.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.98];
    self.pillView.layer.cornerRadius = frame.size.height / 2.0;
    if (@available(iOS 13.0, *)) self.pillView.layer.cornerCurve = kCACornerCurveContinuous;
    self.pillView.clipsToBounds = YES;
    self.pillView.userInteractionEnabled = NO;
    self.pillView.alpha = 0.0;

    self.fillView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, frame.size.height)];
    self.fillView.backgroundColor = [UIColor colorWithRed:0.08 green:0.95 blue:0.10 alpha:1.0];
    self.fillView.userInteractionEnabled = NO;
    [self.pillView addSubview:self.fillView];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold];
    UIImage *speaker = [[UIImage systemImageNamed:@"speaker.wave.2.fill"] imageWithConfiguration:config];
    self.iconView = [[UIImageView alloc] initWithImage:speaker];
    self.iconView.tintColor = UIColor.whiteColor;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.frame = CGRectMake(42.0, 6.0, 23.0, 22.0);
    self.iconView.userInteractionEnabled = NO;
    [self.pillView addSubview:self.iconView];
}

- (void)layoutPill {
    CGRect frame = [self pillFrame];
    self.pillView.frame = frame;
    self.pillView.layer.cornerRadius = frame.size.height / 2.0;

    CGRect fillFrame = self.fillView.frame;
    fillFrame.origin = CGPointZero;
    fillFrame.size.height = frame.size.height;
    self.fillView.frame = fillFrame;

    self.iconView.frame = CGRectMake(42.0, 6.0, 23.0, 22.0);
}

- (void)prepareOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureOverlayWindow];
        [self buildPillIfNeeded];
        [self layoutPill];

        UIView *container = self.overlayWindow.rootViewController.view;
        if (container && self.pillView.superview != container) {
            [self.pillView removeFromSuperview];
            [container addSubview:self.pillView];
        }

        [container bringSubviewToFront:self.pillView];
    });
}

- (UIImage *)speakerImageForVolume:(float)volume {
    NSString *name = @"speaker.wave.2.fill";
    if (volume <= 0.001f) name = @"speaker.slash.fill";
    else if (volume < 0.34f) name = @"speaker.wave.1.fill";

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:name] imageWithConfiguration:config];
}

- (void)showVolume:(float)inputVolume {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!pvEnabled) return;

        [self prepareOverlay];
        if (!self.overlayWindow || !self.pillView) return;

        UIView *container = self.overlayWindow.rootViewController.view;
        if (container && self.pillView.superview != container) {
            [self.pillView removeFromSuperview];
            [container addSubview:self.pillView];
        }

        [self layoutPill];
        self.overlayWindow.hidden = NO;
        [container bringSubviewToFront:self.pillView];

        float volume = fmaxf(0.0f, fminf(1.0f, inputVolume));
        CGFloat targetWidth = self.pillView.bounds.size.width * volume;

        CGRect fillFrame = self.fillView.frame;
        fillFrame.size.width = targetWidth;

        [UIView animateWithDuration:0.06
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.fillView.frame = fillFrame;
        } completion:nil];

        self.iconView.image = [self speakerImageForVolume:volume];

        [UIView animateWithDuration:0.08
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.pillView.alpha = 1.0;
        } completion:nil];

        self.hideGeneration += 1;
        NSInteger generation = self.hideGeneration;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != self.hideGeneration) return;

            [UIView animateWithDuration:0.18
                                  delay:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                             animations:^{
                self.pillView.alpha = 0.0;
            } completion:nil];
        });
    });
}

@end

static void PVInstallSystemObservers(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;

    [center addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [[PVOverlayController sharedInstance] prepareOverlay];
    }];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [[PVOverlayController sharedInstance] prepareOverlay];
    }];

    [center addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (!pvEnabled) return;

        NSString *reason = note.userInfo[@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"];
        if (reason && ![reason isEqualToString:@"ExplicitVolumeChange"]) return;

        NSNumber *volumeNumber = note.userInfo[@"AVSystemController_AudioVolumeNotificationParameter"];
        if ([volumeNumber respondsToSelector:@selector(floatValue)]) {
            [[PVOverlayController sharedInstance] showVolume:volumeNumber.floatValue];
        }
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[PVOverlayController sharedInstance] prepareOverlay];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[PVOverlayController sharedInstance] prepareOverlay];
    });
}

%hook SBVolumeControl

- (void)_presentVolumeHUDWithVolume:(float)volume {
    if (!pvEnabled) {
        %orig;
        return;
    }

    // Suppress Apple's stock HUD and show PillVolume instead.
    [[PVOverlayController sharedInstance] showVolume:volume];
}

- (void)increaseVolume {
    %orig;
    if (pvEnabled) {
        [[PVOverlayController sharedInstance] showVolume:PVReadVolumeFromController(self, 1.0f)];
    }
}

- (void)decreaseVolume {
    %orig;
    if (pvEnabled) {
        [[PVOverlayController sharedInstance] showVolume:PVReadVolumeFromController(self, 0.0f)];
    }
}

%end

%ctor {
    @autoreleasepool {
        if (@available(iOS 16.0, *)) {
            PVLoadPrefs();
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            NULL,
                                            PVPrefsChangedCallback,
                                            (__bridge CFStringRef)PVPrefsChanged,
                                            NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
            PVInstallSystemObservers();
            %init;
        }
    }
}
