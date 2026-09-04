#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";
static BOOL pvEnabled = YES;

@interface SBVolumeControl : NSObject
@end

@interface PVOverlayController : NSObject
@property (nonatomic, strong) UIView *pillView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, weak) UIWindow *hostWindow;
@property (nonatomic, assign) NSInteger hideGeneration;
+ (instancetype)sharedInstance;
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

@implementation PVOverlayController

+ (instancetype)sharedInstance {
    static PVOverlayController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [PVOverlayController new];
    });
    return controller;
}

- (NSArray<UIWindow *> *)allSpringBoardWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.screen == UIScreen.mainScreen) {
                [windows addObject:window];
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.screen == UIScreen.mainScreen && ![windows containsObject:window]) {
            [windows addObject:window];
        }
    }
#pragma clang diagnostic pop

    return windows;
}

- (UIWindow *)bestHostWindow {
    UIWindow *best = nil;
    CGFloat bestLevel = -CGFLOAT_MAX;

    for (UIWindow *window in [self allSpringBoardWindows]) {
        if (window.hidden || window.alpha <= 0.01 || !window.rootViewController) continue;
        if (CGRectIsEmpty(window.bounds)) continue;

        CGFloat level = window.windowLevel;
        if (!best || level > bestLevel) {
            best = window;
            bestLevel = level;
        }
    }

    if (!best) {
        for (UIWindow *window in [self allSpringBoardWindows]) {
            if (!window.hidden && window.alpha > 0.01) {
                best = window;
                break;
            }
        }
    }

    return best;
}

- (void)buildPillIfNeeded {
    if (self.pillView) return;

    // XS Max / notched-iPhone proportions based on the original SVC3 Pill HUD.
    // This deliberately occupies the LEFT status-bar row beside the notch.
    const CGFloat width = 112.0;
    const CGFloat height = 38.0;

    self.pillView = [[UIView alloc] initWithFrame:CGRectMake(7.0, 3.0, width, height)];
    self.pillView.backgroundColor = [UIColor colorWithWhite:0.26 alpha:0.98];
    self.pillView.layer.cornerRadius = height / 2.0;
    if (@available(iOS 13.0, *)) self.pillView.layer.cornerCurve = kCACornerCurveContinuous;
    self.pillView.clipsToBounds = YES;
    self.pillView.userInteractionEnabled = NO;
    self.pillView.alpha = 0.0;

    self.fillView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, height)];
    self.fillView.backgroundColor = [UIColor colorWithRed:0.08 green:0.95 blue:0.10 alpha:1.0];
    self.fillView.userInteractionEnabled = NO;
    [self.pillView addSubview:self.fillView];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *speaker = [[UIImage systemImageNamed:@"speaker.wave.2.fill"] imageWithConfiguration:config];
    self.iconView = [[UIImageView alloc] initWithImage:speaker];
    self.iconView.tintColor = UIColor.whiteColor;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.frame = CGRectMake(42.0, 8.0, 24.0, 22.0);
    self.iconView.userInteractionEnabled = NO;
    [self.pillView addSubview:self.iconView];
}

- (void)attachToCurrentSystemWindow {
    [self buildPillIfNeeded];

    UIWindow *host = [self bestHostWindow];
    if (!host) return;

    if (self.pillView.superview != host) {
        [self.pillView removeFromSuperview];
        [host addSubview:self.pillView];
    }

    self.hostWindow = host;
    [host bringSubviewToFront:self.pillView];

    // Re-assert status-bar coordinates whenever SpringBoard changes windows
    // (home screen <-> lock screen <-> app transition).
    self.pillView.frame = CGRectMake(7.0, 3.0, 112.0, 38.0);
}

- (UIImage *)speakerImageForVolume:(float)volume {
    NSString *name = @"speaker.wave.2.fill";
    if (volume <= 0.001f) name = @"speaker.slash.fill";
    else if (volume < 0.34f) name = @"speaker.wave.1.fill";

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:name] imageWithConfiguration:config];
}

- (void)showVolume:(float)inputVolume {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!pvEnabled) return;

        [self attachToCurrentSystemWindow];
        if (!self.pillView.superview) return;

        float volume = fmaxf(0.0f, fminf(1.0f, inputVolume));
        CGFloat targetWidth = self.pillView.bounds.size.width * volume;

        CGRect fillFrame = self.fillView.frame;
        fillFrame.size.width = targetWidth;

        [UIView animateWithDuration:0.08
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.fillView.frame = fillFrame;
        } completion:nil];

        self.iconView.image = [self speakerImageForVolume:volume];
        [self.pillView.superview bringSubviewToFront:self.pillView];

        [UIView animateWithDuration:0.10
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.pillView.alpha = 1.0;
        } completion:nil];

        self.hideGeneration += 1;
        NSInteger generation = self.hideGeneration;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != self.hideGeneration) return;

            [UIView animateWithDuration:0.20
                                  delay:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                             animations:^{
                self.pillView.alpha = 0.0;
            } completion:nil];
        });
    });
}

@end

%hook SBVolumeControl

- (void)_presentVolumeHUDWithVolume:(float)volume {
    if (!pvEnabled) {
        %orig;
        return;
    }

    // Suppress Apple's stock HUD and show PillVolume instead.
    [[PVOverlayController sharedInstance] showVolume:volume];
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
            %init;
        }
    }
}
