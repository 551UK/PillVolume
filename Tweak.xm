#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";
static BOOL pvEnabled = YES;
static float pvLastVolume = -1.0f;

@interface SBVolumeControl : NSObject
@end

@interface AVSystemController : NSObject
+ (id)sharedAVSystemController;
- (BOOL)getActiveCategoryVolume:(float *)volumePointer andName:(NSString **)name;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)changeActiveCategoryVolumeBy:(float)volume;
@end

@interface PVOverlayController : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *pill;
@property(nonatomic,strong) UIView *fill;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,assign) NSInteger hideGeneration;
+ (instancetype)shared;
- (void)showVolume:(float)volume;
- (void)hideImmediately;
@end

static float PVClamp(float v) {
    return fmaxf(0.0f, fminf(1.0f, v));
}

static void PVLoadPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PVPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("Enabled"), (__bridge CFStringRef)PVPrefsDomain);
    pvEnabled = value ? CFBooleanGetValue((CFBooleanRef)value) : YES;
    if (value) CFRelease(value);
}

static id PVAV(void) {
    Class cls = objc_getClass("AVSystemController");
    SEL sel = NSSelectorFromString(@"sharedAVSystemController");
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)((id)cls, sel);
}

static float PVCurrentVolume(float fallback) {
    id av = PVAV();
    if (av) {
        SEL active = NSSelectorFromString(@"getActiveCategoryVolume:andName:");
        if ([av respondsToSelector:active]) {
            float v = 0.0f;
            NSString *name = nil;
            BOOL ok = ((BOOL(*)(id,SEL,float *,NSString **))objc_msgSend)(av, active, &v, &name);
            if (ok && isfinite(v)) return PVClamp(v);
        }

        SEL category = NSSelectorFromString(@"getVolume:forCategory:");
        if ([av respondsToSelector:category]) {
            float v = 0.0f;
            BOOL ok = ((BOOL(*)(id,SEL,float *,NSString *))objc_msgSend)(av, category, &v, @"Audio/Video");
            if (ok && isfinite(v)) return PVClamp(v);
        }
    }

    return pvLastVolume >= 0.0f ? PVClamp(pvLastVolume) : PVClamp(fallback);
}

@implementation PVOverlayController

+ (instancetype)shared {
    static PVOverlayController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [PVOverlayController new];
    });
    return controller;
}

- (UIWindowScene *)springBoardScene {
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

    return fallback;
}

- (CGRect)pillFrame {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat statusHeight = 44.0;
    UIWindowScene *scene = self.window.windowScene ?: [self springBoardScene];

    if (@available(iOS 13.0, *)) {
        CGFloat h = scene.statusBarManager.statusBarFrame.size.height;
        if (h >= 20.0) statusHeight = h;
    }

    // iPhone 12 Pro Max is 428pt wide. Make its pill a little smaller
    // and move it slightly to the right compared with the XS Max layout.
    BOOL is12ProMaxSize = fabs(screenWidth - 428.0) < 2.0;
    CGFloat width = is12ProMaxSize ? 88.0 : 88.0;
    CGFloat height = is12ProMaxSize ? 29.0 : 31.0;
    CGFloat x = is12ProMaxSize ? 16.0 : 10.0;
    CGFloat y = floor((statusHeight - height) / 2.0) - 0.5;
    y = fmax(is12ProMaxSize ? 7.0 : 6.5, y);

    return CGRectMake(x, y, width, height);
}

- (void)ensureWindow {
    UIWindowScene *scene = [self springBoardScene];
    if (!scene) return;

    if (!self.window || self.window.windowScene != scene) {
        self.window.hidden = YES;
        self.window = [[UIWindow alloc] initWithWindowScene:scene];
        self.window.rootViewController = [UIViewController new];
        self.window.backgroundColor = UIColor.clearColor;
        self.window.opaque = NO;
        self.window.userInteractionEnabled = NO;
    }

    self.window.frame = UIScreen.mainScreen.bounds;
    self.window.windowLevel = UIWindowLevelStatusBar + 10000.0;
    self.window.layer.zPosition = 1000000.0;
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.rootViewController.view.userInteractionEnabled = NO;
    self.window.hidden = NO;
}

- (void)ensurePill {
    CGRect frame = [self pillFrame];

    if (!self.pill) {
        self.pill = [[UIView alloc] initWithFrame:frame];
        self.pill.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.98];
        self.pill.clipsToBounds = YES;
        self.pill.alpha = 0.0;
        self.pill.userInteractionEnabled = NO;

        self.fill = [[UIView alloc] initWithFrame:CGRectZero];
        self.fill.backgroundColor = [UIColor colorWithRed:0.04 green:0.82 blue:0.08 alpha:1.0];
        [self.pill addSubview:self.fill];

        self.icon = [[UIImageView alloc] init];
        self.icon.tintColor = UIColor.whiteColor;
        self.icon.contentMode = UIViewContentModeScaleAspectFit;
        [self.pill addSubview:self.icon];
    }

    self.pill.frame = frame;
    self.pill.layer.cornerRadius = frame.size.height / 2.0;
    if (@available(iOS 13.0, *)) {
        self.pill.layer.cornerCurve = kCACornerCurveContinuous;
    }

    CGFloat iconW = frame.size.height <= 29.0 ? 20.0 : 22.0;
    CGFloat iconH = frame.size.height <= 29.0 ? 17.0 : 19.0;
    CGFloat iconX = floor((frame.size.width - iconW) * 0.43);
    CGFloat iconY = floor((frame.size.height - iconH) / 2.0);
    self.icon.frame = CGRectMake(iconX, iconY, iconW, iconH);

    if (self.pill.superview != self.window.rootViewController.view) {
        [self.pill removeFromSuperview];
        [self.window.rootViewController.view addSubview:self.pill];
    }

    [self.window.rootViewController.view bringSubviewToFront:self.pill];
}

- (UIImage *)speakerFor:(float)volume {
    NSString *name;
    if (volume <= 0.001f) {
        name = @"speaker.slash.fill";
    } else if (volume < 0.34f) {
        name = @"speaker.wave.1.fill";
    } else {
        name = @"speaker.wave.2.fill";
    }

    CGFloat size = [self pillFrame].size.height <= 29.0 ? 14.5 : 15.5;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold];
    return [[UIImage systemImageNamed:name] imageWithConfiguration:config];
}

- (void)showVolume:(float)input {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!pvEnabled) return;

        [self ensureWindow];
        [self ensurePill];
        if (!self.window || !self.pill) return;

        float volume = PVClamp(input);
        pvLastVolume = volume;

        CGRect fillFrame = self.fill.frame;
        fillFrame.origin = CGPointZero;
        fillFrame.size.height = self.pill.bounds.size.height;
        fillFrame.size.width = self.pill.bounds.size.width * volume;

        [UIView animateWithDuration:0.12
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            self.fill.frame = fillFrame;
        } completion:nil];

        self.icon.image = [self speakerFor:volume];
        self.window.hidden = NO;
        [self.window.rootViewController.view bringSubviewToFront:self.pill];

        [UIView animateWithDuration:0.10 animations:^{
            self.pill.alpha = 1.0;
        }];

        NSInteger generation = ++self.hideGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != self.hideGeneration) return;

            [UIView animateWithDuration:0.28 animations:^{
                self.pill.alpha = 0.0;
            } completion:^(BOOL finished) {
                if (finished && generation == self.hideGeneration) {
                    self.window.hidden = YES;
                }
            }];
        });
    });
}

- (void)hideImmediately {
    dispatch_async(dispatch_get_main_queue(), ^{
        ++self.hideGeneration;
        self.pill.alpha = 0.0;
        self.window.hidden = YES;
    });
}

@end

static void PVShow(float fallback) {
    [[PVOverlayController shared] showVolume:PVCurrentVolume(fallback)];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[PVOverlayController shared] showVolume:PVCurrentVolume(fallback)];
    });
}

static void PVPrefsChangedCallback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    PVLoadPrefs();
    if (!pvEnabled) {
        [[PVOverlayController shared] hideImmediately];
    }
}

static void PVInstallObservers(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                     object:nil
                                                      queue:NSOperationQueue.mainQueue
                                                 usingBlock:^(NSNotification *note) {
        if (!pvEnabled) return;

        NSNumber *number = note.userInfo[@"AVSystemController_AudioVolumeNotificationParameter"];
        float fallback = [number respondsToSelector:@selector(floatValue)]
            ? number.floatValue
            : (pvLastVolume >= 0.0f ? pvLastVolume : 0.5f);
        PVShow(fallback);
    }];
}

%hook SBVolumeControl

- (void)_presentVolumeHUDWithVolume:(float)volume {
    if (!pvEnabled) {
        %orig;
        return;
    }

    [[PVOverlayController shared] showVolume:PVCurrentVolume(volume)];
}

- (void)increaseVolume {
    %orig;

    if (pvEnabled) {
        float fallback = pvLastVolume >= 0.0f ? pvLastVolume : 1.0f;
        PVShow(fallback);
    }
}

- (void)decreaseVolume {
    %orig;

    if (pvEnabled) {
        float fallback = pvLastVolume >= 0.0f ? pvLastVolume : 0.0f;
        PVShow(fallback);
    }
}

%end

%hook AVSystemController

- (BOOL)changeActiveCategoryVolumeBy:(float)volume {
    BOOL result = %orig;

    if (pvEnabled) {
        float fallback = pvLastVolume >= 0.0f ? pvLastVolume : 0.5f;
        PVShow(fallback);
    }

    return result;
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
            PVInstallObservers();
            %init;
        }
    }
}
