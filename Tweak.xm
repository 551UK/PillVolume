#import <UIKit/UIKit.h>

@interface SBVolumeControl : NSObject
@end

@interface PVOverlayController : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *pillView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) dispatch_block_t pendingHideBlock;
+ (instancetype)sharedInstance;
- (void)showVolume:(float)volume;
@end

@implementation PVOverlayController

+ (instancetype)sharedInstance {
    static PVOverlayController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [PVOverlayController new];
    });
    return controller;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self buildOverlay];
    }
    return self;
}

- (void)buildOverlay {
    CGRect screenBounds = UIScreen.mainScreen.bounds;

    self.window = [[UIWindow alloc] initWithFrame:screenBounds];
    self.window.windowLevel = UIWindowLevelStatusBar + 1500.0;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.userInteractionEnabled = NO;
    self.window.hidden = YES;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = root;

    const CGFloat width = 125.0;
    const CGFloat height = 48.0;
    const CGFloat x = 10.0;

    CGFloat safeTop = 0.0;
    if (@available(iOS 11.0, *)) {
        safeTop = root.view.safeAreaInsets.top;
    }

    // On notched devices place the pill just below the status-bar area.
    // On older devices keep the original near-the-corner look.
    CGFloat y = safeTop >= 40.0 ? safeTop + 6.0 : 10.0;

    self.pillView = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    self.pillView.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.19 alpha:0.96];
    self.pillView.layer.cornerRadius = height / 2.0;
    self.pillView.layer.cornerCurve = kCACornerCurveContinuous;
    self.pillView.clipsToBounds = YES;
    self.pillView.alpha = 0.0;

    self.fillView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, height)];
    self.fillView.backgroundColor = [UIColor colorWithRed:0.04 green:0.76 blue:0.14 alpha:1.0];
    [self.pillView addSubview:self.fillView];

    UIImage *speaker = [UIImage systemImageNamed:@"speaker.wave.2.fill"];
    self.iconView = [[UIImageView alloc] initWithImage:speaker];
    self.iconView.tintColor = UIColor.whiteColor;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.frame = CGRectMake(58.0, 11.0, 31.0, 26.0);
    [self.pillView addSubview:self.iconView];

    [root.view addSubview:self.pillView];
}

- (UIImage *)speakerImageForVolume:(float)volume {
    NSString *name;
    if (volume <= 0.001f) {
        name = @"speaker.slash.fill";
    } else if (volume < 0.34f) {
        name = @"speaker.wave.1.fill";
    } else {
        name = @"speaker.wave.2.fill";
    }
    return [UIImage systemImageNamed:name];
}

- (void)showVolume:(float)volume {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.window || !self.pillView) {
            [self buildOverlay];
        }

        volume = fmaxf(0.0f, fminf(1.0f, volume));
        CGFloat width = self.pillView.bounds.size.width * volume;

        [UIView animateWithDuration:0.08
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            CGRect frame = self.fillView.frame;
            frame.size.width = width;
            self.fillView.frame = frame;
        } completion:nil];

        self.iconView.image = [self speakerImageForVolume:volume];

        self.window.hidden = NO;
        [UIView animateWithDuration:0.12
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.pillView.alpha = 1.0;
        } completion:nil];

        if (self.pendingHideBlock) {
            dispatch_block_cancel(self.pendingHideBlock);
            self.pendingHideBlock = nil;
        }

        __weak typeof(self) weakSelf = self;
        dispatch_block_t hideBlock = dispatch_block_create(0, ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            [UIView animateWithDuration:0.22
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                             animations:^{
                self.pillView.alpha = 0.0;
            } completion:^(BOOL finished) {
                if (finished && self.pillView.alpha <= 0.001) {
                    self.window.hidden = YES;
                }
            }];
        });

        self.pendingHideBlock = hideBlock;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), hideBlock);
    });
}

@end

%hook SBVolumeControl

// iOS 16 SpringBoard uses this method to present the stock volume HUD.
// We use the same volume value for the replacement and intentionally do not
// call %orig, which prevents Apple's volume HUD from appearing underneath it.
- (void)_presentVolumeHUDWithVolume:(float)volume {
    [[PVOverlayController sharedInstance] showVolume:volume];
}

%end

%ctor {
    @autoreleasepool {
        if (@available(iOS 16.0, *)) {
            %init;
        }
    }
}
