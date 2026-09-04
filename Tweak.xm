#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";
static BOOL pvEnabled = YES;

@interface SBVolumeControl : NSObject
@end

@interface PVOverlayController : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *pillView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;
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

- (UIWindowScene *)activeWindowScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (CGFloat)topInsetForScene:(UIWindowScene *)scene {
    for (UIWindow *window in scene.windows) {
        if (window.safeAreaInsets.top > 0.0) return window.safeAreaInsets.top;
    }
    return 0.0;
}

- (void)buildOverlay {
    UIWindowScene *scene = [self activeWindowScene];
    CGRect bounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;

    self.window = [[UIWindow alloc] initWithFrame:bounds];
    if (scene) self.window.windowScene = scene;
    self.window.windowLevel = UIWindowLevelStatusBar + 1000.0;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.userInteractionEnabled = NO;
    self.window.hidden = YES;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = root;

    const CGFloat width = 126.0;
    const CGFloat height = 48.0;
    const CGFloat x = 10.0;

    CGFloat topInset = scene ? [self topInsetForScene:scene] : 0.0;
    CGFloat y = topInset >= 40.0 ? topInset + 7.0 : 10.0;

    self.pillView = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    self.pillView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.97];
    self.pillView.layer.cornerRadius = height / 2.0;
    if (@available(iOS 13.0, *)) self.pillView.layer.cornerCurve = kCACornerCurveContinuous;
    self.pillView.clipsToBounds = YES;
    self.pillView.alpha = 0.0;

    self.fillView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, height)];
    self.fillView.backgroundColor = [UIColor colorWithRed:0.08 green:0.78 blue:0.18 alpha:1.0];
    [self.pillView addSubview:self.fillView];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
    UIImage *speaker = [[UIImage systemImageNamed:@"speaker.wave.2.fill"] imageWithConfiguration:config];
    self.iconView = [[UIImageView alloc] initWithImage:speaker];
    self.iconView.tintColor = UIColor.whiteColor;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.frame = CGRectMake(50.0, 11.0, 26.0, 26.0);
    [self.pillView addSubview:self.iconView];

    [root.view addSubview:self.pillView];
}

- (UIImage *)speakerImageForVolume:(float)volume {
    NSString *name = @"speaker.wave.2.fill";
    if (volume <= 0.001f) name = @"speaker.slash.fill";
    else if (volume < 0.34f) name = @"speaker.wave.1.fill";

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:name] imageWithConfiguration:config];
}

- (void)showVolume:(float)inputVolume {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!pvEnabled) return;

        float volume = fmaxf(0.0f, fminf(1.0f, inputVolume));

        if (!self.window || !self.pillView) {
            [self buildOverlay];
        } else if (!self.window.windowScene) {
            UIWindowScene *scene = [self activeWindowScene];
            if (scene) self.window.windowScene = scene;
        }

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
        self.window.hidden = NO;

        [UIView animateWithDuration:0.12
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
            } completion:^(BOOL finished) {
                if (finished && generation == self.hideGeneration) {
                    self.window.hidden = YES;
                }
            }];
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
