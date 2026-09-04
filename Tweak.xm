#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";
static BOOL pvEnabled = YES;
static float pvLastVolume = -1.0f;
static NSString *pvLastVolumeCategory = @"Audio/Video";

@interface SBVolumeControl : NSObject
@end

@interface CSCoverSheetViewController : UIViewController
@end

@interface CSMainPageViewController : UIViewController
@end

@interface SBLockScreenViewController : UIViewController
@end

@interface CSCoverSheetView : UIView
@end

@interface PVOverlayController : NSObject
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, weak) UIView *coverSheetHostView;
@property (nonatomic, strong) UIView *pillView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, assign) NSInteger hideGeneration;
+ (instancetype)sharedInstance;
- (void)prepareOverlay;
- (void)prepareOverlayNow;
- (void)setLockScreenHostView:(UIView *)hostView;
- (BOOL)hasVisibleLockScreenHost;
- (void)hideImmediately;
- (void)showVolume:(float)volume;
@end

static void PVPerformOnMain(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static float PVClampVolume(float value) {
    return fmaxf(0.0f, fminf(1.0f, value));
}

static void PVStoreCategoryIfString(id category) {
    if ([category isKindOfClass:NSString.class] && [(NSString *)category length] > 0) {
        pvLastVolumeCategory = [(NSString *)category copy];
    }
}

static BOOL PVBoolFromSelector(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) return NO;

    BOOL (*msgSendBool)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    return msgSendBool(target, selector);
}

static id PVSharedInstanceForClass(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls) return nil;

    NSArray<NSString *> *sharedSelectors = @[@"sharedInstance", @"sharedInstanceIfExists"];
    for (NSString *selectorName in sharedSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([cls respondsToSelector:selector]) {
            id (*msgSendId)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            return msgSendId((id)cls, selector);
        }
    }

    return nil;
}

static BOOL PVLockScreenLooksActive(void) {
    NSArray<id> *managers = @[
        PVSharedInstanceForClass("SBLockScreenManager") ?: [NSNull null],
        PVSharedInstanceForClass("SBLockStateAggregator") ?: [NSNull null]
    ];

    NSArray<NSString *> *selectors = @[
        @"isUILocked",
        @"isLockScreenVisible",
        @"isShowingLockScreen",
        @"isScreenLocked",
        @"isLocked",
        @"hasAnyLockState"
    ];

    for (id manager in managers) {
        if (manager == (id)[NSNull null]) continue;
        for (NSString *selectorName in selectors) {
            if (PVBoolFromSelector(manager, selectorName)) return YES;
        }
    }

    return NO;
}

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
    if (!pvEnabled) {
        PVPerformOnMain(^{
            [[PVOverlayController sharedInstance] hideImmediately];
        });
    }
}

static float PVReadVolumeFromController(id controller, float fallback) {
    NSArray<NSString *> *selectors = @[@"_effectiveVolume", @"volume", @"_volume", @"currentVolume", @"volumeValue"];

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            float (*msgSendFloat)(id, SEL) = (float (*)(id, SEL))objc_msgSend;
            float value = msgSendFloat(controller, selector);
            if (isfinite(value)) return PVClampVolume(value);
        }
    }

    return PVClampVolume(fallback);
}

static id PVSharedAVSystemController(void) {
    Class cls = objc_getClass("AVSystemController");
    SEL sharedSelector = NSSelectorFromString(@"sharedAVSystemController");

    if (!cls || ![cls respondsToSelector:sharedSelector]) return nil;

    id (*msgSendId)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return msgSendId((id)cls, sharedSelector);
}

static BOOL PVGetVolumeForCategory(NSString *category, float *outVolume) {
    if (!category.length || !outVolume) return NO;

    id controller = PVSharedAVSystemController();
    SEL selector = NSSelectorFromString(@"getVolume:forCategory:");

    if (controller && [controller respondsToSelector:selector]) {
        float volume = 0.0f;
        BOOL (*msgSendGetVolume)(id, SEL, float *, NSString *) = (BOOL (*)(id, SEL, float *, NSString *))objc_msgSend;
        BOOL ok = msgSendGetVolume(controller, selector, &volume, category);
        if (ok && isfinite(volume)) {
            *outVolume = PVClampVolume(volume);
            return YES;
        }
    }

    return NO;
}

static float PVCurrentSystemVolume(float fallback) {
    NSMutableArray<NSString *> *categories = [NSMutableArray array];
    if (pvLastVolumeCategory.length > 0) [categories addObject:pvLastVolumeCategory];
    [categories addObjectsFromArray:@[@"Audio/Video", @"Ringtone", @"Ringtone/Alert", @"Alert"]];

    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *category in categories) {
        if ([seen containsObject:category]) continue;
        [seen addObject:category];

        float volume = 0.0f;
        if (PVGetVolumeForCategory(category, &volume)) return PVClampVolume(volume);
    }

    if (pvLastVolume >= 0.0f) return PVClampVolume(pvLastVolume);
    return PVClampVolume(fallback);
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

- (void)promoteOverlayWindow {
    if (!self.overlayWindow) return;

    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 9000.0;
    self.overlayWindow.layer.zPosition = 999999.0;
    self.overlayWindow.rootViewController.view.layer.zPosition = 999999.0;
    self.overlayWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.overlayWindow.rootViewController.view.userInteractionEnabled = NO;
    self.overlayWindow.hidden = NO;
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
        self.overlayWindow.hidden = NO;
    }

    self.overlayWindow.frame = UIScreen.mainScreen.bounds;
    [self promoteOverlayWindow];
}

- (UIView *)lockScreenContainerIfAvailable {
    UIView *host = self.coverSheetHostView;
    if (!host || !host.window || host.hidden || host.alpha <= 0.01) return nil;

    UIWindow *window = host.window;
    if (window.hidden || window.alpha <= 0.01) return nil;

    Class coverSheetClass = objc_getClass("CSCoverSheetView");
    NSString *windowClass = NSStringFromClass(window.class).lowercaseString;
    NSString *hostClass = NSStringFromClass(host.class).lowercaseString;
    BOOL looksLikeLockScreenHost = PVLockScreenLooksActive() ||
        [windowClass containsString:@"cover"] || [windowClass containsString:@"lock"] ||
        [hostClass containsString:@"cover"] || [hostClass containsString:@"lock"] ||
        (coverSheetClass && [host isKindOfClass:coverSheetClass]);

    if (!looksLikeLockScreenHost) return nil;

    window.clipsToBounds = NO;
    host.clipsToBounds = NO;
    return window;
}

- (BOOL)hasVisibleLockScreenHost {
    return [self lockScreenContainerIfAvailable] != nil;
}

- (UIView *)activeContainer {
    UIView *lockContainer = [self lockScreenContainerIfAvailable];
    if (lockContainer) {
        self.overlayWindow.hidden = YES;
        return lockContainer;
    }

    [self ensureOverlayWindow];
    return self.overlayWindow.rootViewController.view;
}

- (CGRect)pillFrame {
    UIWindowScene *scene = self.overlayWindow.windowScene ?: [self activeSpringBoardScene];
    CGFloat statusHeight = 44.0;
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;

    if (@available(iOS 13.0, *)) {
        CGFloat sceneStatusHeight = scene.statusBarManager.statusBarFrame.size.height;
        if (sceneStatusHeight >= 20.0) statusHeight = sceneStatusHeight;
    }

    CGFloat width = screenWidth >= 428.0 ? 94.0 : 88.0;
    CGFloat height = 31.0;
    CGFloat x = 10.0;
    CGFloat y = floor((statusHeight - height) / 2.0) - 0.5;
    y = fmax(6.5, y);

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
    self.pillView.layer.zPosition = 999999.0;

    self.fillView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, frame.size.height)];
    self.fillView.backgroundColor = [UIColor colorWithRed:0.04 green:0.82 blue:0.08 alpha:1.0];
    self.fillView.userInteractionEnabled = NO;
    [self.pillView addSubview:self.fillView];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15.5 weight:UIImageSymbolWeightBold];
    UIImage *speaker = [[UIImage systemImageNamed:@"speaker.wave.2.fill"] imageWithConfiguration:config];
    self.iconView = [[UIImageView alloc] initWithImage:speaker];
    self.iconView.tintColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.frame = CGRectMake(32.0, 6.0, 22.0, 19.0);
    self.iconView.userInteractionEnabled = NO;
    self.iconView.layer.zPosition = 1000000.0;
    [self.pillView addSubview:self.iconView];
}

- (void)layoutPill {
    CGRect frame = [self pillFrame];
    self.pillView.frame = frame;
    self.pillView.layer.cornerRadius = frame.size.height / 2.0;
    self.pillView.layer.zPosition = 999999.0;

    CGRect fillFrame = self.fillView.frame;
    fillFrame.origin = CGPointZero;
    fillFrame.size.height = frame.size.height;
    self.fillView.frame = fillFrame;

    self.iconView.frame = CGRectMake(32.0, 6.0, 22.0, 19.0);
    self.iconView.layer.zPosition = 1000000.0;
}

- (void)prepareOverlayNow {
    UIView *container = [self activeContainer];
    if (!container) return;

    [self buildPillIfNeeded];
    [self layoutPill];

    if (self.pillView.superview != container) {
        [self.pillView removeFromSuperview];
        [container addSubview:self.pillView];
    }

    container.clipsToBounds = NO;
    self.pillView.layer.zPosition = 999999.0;
    [container bringSubviewToFront:self.pillView];
}

- (void)prepareOverlay {
    PVPerformOnMain(^{
        [self prepareOverlayNow];
    });
}

- (void)setLockScreenHostView:(UIView *)hostView {
    if (!hostView) return;

    PVPerformOnMain(^{
        self.coverSheetHostView = hostView;
        hostView.clipsToBounds = NO;
        hostView.window.clipsToBounds = NO;
    });
}

- (void)hideImmediately {
    PVPerformOnMain(^{
        self.hideGeneration += 1;
        self.pillView.alpha = 0.0;
        self.overlayWindow.hidden = YES;
    });
}

- (UIImage *)speakerImageForVolume:(float)volume {
    NSString *name = @"speaker.wave.2.fill";
    if (volume <= 0.001f) name = @"speaker.slash.fill";
    else if (volume < 0.34f) name = @"speaker.wave.1.fill";

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15.5 weight:UIImageSymbolWeightBold];
    return [[UIImage systemImageNamed:name] imageWithConfiguration:config];
}

- (void)showVolume:(float)inputVolume {
    PVPerformOnMain(^{
        if (!pvEnabled) return;

        [self prepareOverlayNow];
        if (!self.pillView) return;

        UIView *container = self.pillView.superview ?: [self activeContainer];
        [self layoutPill];
        if (container) {
            container.clipsToBounds = NO;
            [container bringSubviewToFront:self.pillView];
        }

        if (container == self.overlayWindow.rootViewController.view) {
            [self promoteOverlayWindow];
        } else {
            self.overlayWindow.hidden = YES;
        }

        float volume = PVClampVolume(inputVolume);
        pvLastVolume = volume;
        CGFloat targetWidth = self.pillView.bounds.size.width * volume;

        CGRect fillFrame = self.fillView.frame;
        fillFrame.size.width = targetWidth;

        [UIView animateWithDuration:0.04
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear
                         animations:^{
            self.fillView.frame = fillFrame;
        } completion:nil];

        self.iconView.image = [self speakerImageForVolume:volume];

        [UIView animateWithDuration:0.05
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

static void PVShowCurrentVolumeAfterNative(id controller, float fallback) {
    float firstFallback = PVReadVolumeFromController(controller, fallback);
    [[PVOverlayController sharedInstance] showVolume:firstFallback];

    NSArray<NSNumber *> *delays = @[@0.02, @0.06, @0.12, @0.20];
    for (NSNumber *delayNumber in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayNumber.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            float controllerVolume = PVReadVolumeFromController(controller, firstFallback);
            BOOL lockOrCover = PVLockScreenLooksActive() || [[PVOverlayController sharedInstance] hasVisibleLockScreenHost];
            float volume = lockOrCover ? controllerVolume : PVCurrentSystemVolume(controllerVolume);
            [[PVOverlayController sharedInstance] showVolume:volume];
        });
    }
}

static void PVInstallSystemObservers(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;

    [center addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [[PVOverlayController sharedInstance] prepareOverlay];
    }];

    [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [[PVOverlayController sharedInstance] prepareOverlay];
    }];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [[PVOverlayController sharedInstance] prepareOverlay];
    }];

    [center addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (!pvEnabled) return;

        PVStoreCategoryIfString(note.userInfo[@"AVSystemController_AudioCategoryNotificationParameter"]);

        NSString *reason = note.userInfo[@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"];
        BOOL lockOrCover = PVLockScreenLooksActive() || [[PVOverlayController sharedInstance] hasVisibleLockScreenHost];
        if (reason && ![reason isEqualToString:@"ExplicitVolumeChange"] && !lockOrCover) return;

        NSNumber *volumeNumber = note.userInfo[@"AVSystemController_AudioVolumeNotificationParameter"];
        if ([volumeNumber respondsToSelector:@selector(floatValue)]) {
            [[PVOverlayController sharedInstance] showVolume:PVClampVolume(volumeNumber.floatValue)];
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

    if (PVLockScreenLooksActive() || [[PVOverlayController sharedInstance] hasVisibleLockScreenHost]) {
        %orig;
        PVShowCurrentVolumeAfterNative(self, volume);
        return;
    }

    [[PVOverlayController sharedInstance] showVolume:volume];
}

- (void)increaseVolume {
    %orig;
    if (pvEnabled) {
        float fallback = PVReadVolumeFromController(self, pvLastVolume >= 0.0f ? pvLastVolume : 1.0f);
        PVShowCurrentVolumeAfterNative(self, fallback);
    }
}

- (void)decreaseVolume {
    %orig;
    if (pvEnabled) {
        float fallback = PVReadVolumeFromController(self, pvLastVolume >= 0.0f ? pvLastVolume : 0.0f);
        PVShowCurrentVolumeAfterNative(self, fallback);
    }
}

- (void)changeVolumeByDelta:(float)delta {
    %orig;
    if (pvEnabled) {
        float fallback = PVReadVolumeFromController(self, pvLastVolume >= 0.0f ? pvLastVolume : 0.5f);
        PVShowCurrentVolumeAfterNative(self, fallback);
    }
}

- (void)handleVolumeButtonWithType:(long long)type down:(BOOL)down {
    %orig;
    if (pvEnabled && down) {
        float fallback = PVReadVolumeFromController(self, pvLastVolume >= 0.0f ? pvLastVolume : 0.5f);
        PVShowCurrentVolumeAfterNative(self, fallback);
    }
}

- (void)_updateEffectiveVolume:(float)volume {
    %orig;
    if (pvEnabled && isfinite(volume)) {
        [[PVOverlayController sharedInstance] showVolume:PVClampVolume(volume)];
    }
}

- (void)setActiveCategoryVolume:(float)volume {
    %orig;
    if (pvEnabled && isfinite(volume)) {
        [[PVOverlayController sharedInstance] showVolume:PVClampVolume(volume)];
        PVShowCurrentVolumeAfterNative(self, volume);
    }
}

- (void)setVolume:(float)volume forCategory:(id)category {
    PVStoreCategoryIfString(category);
    %orig;
    if (pvEnabled && isfinite(volume)) {
        [[PVOverlayController sharedInstance] showVolume:PVClampVolume(volume)];
        PVShowCurrentVolumeAfterNative(self, volume);
    }
}

%end

%hook CSCoverSheetViewController

- (void)viewDidLoad {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

%end

%hook CSMainPageViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

%end

%hook SBLockScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [[PVOverlayController sharedInstance] setLockScreenHostView:((UIViewController *)self).view];
}

%end

%hook CSCoverSheetView

- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (view.window) {
        [[PVOverlayController sharedInstance] setLockScreenHostView:view];
    }
}

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    if (view.window) {
        [[PVOverlayController sharedInstance] setLockScreenHostView:view];
    }
}

%end

%ctor {
    @autoreleasepool {
        if (@available(iOS 16.0, *)) {
            PVLoadPrefs();
            CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterAddObserver(darwinCenter,
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
