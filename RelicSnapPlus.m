#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void (*origPresent)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));
static BOOL launchWindow = YES;

static BOOL NoAdsEnabled(void) {
    Class shadow = NSClassFromString(@"ShadowData");
    SEL enabledSel = NSSelectorFromString(@"enabled:");
    if (!shadow || ![shadow respondsToSelector:enabledSel]) return NO;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)((id)shadow, enabledSel, @"noads");
}

static BOOL StringLooksLikeSnapPlus(NSString *s) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return NO;
    NSString *v = s.lowercaseString;
    return [v containsString:@"snapchat+"] || [v containsString:@"snapchat plus"];
}

static BOOL ViewContainsSnapPlus(UIView *view, NSInteger depth, NSInteger *budget) {
    if (!view || depth > 8 || !budget || *budget <= 0) return NO;
    (*budget)--;

    if ([view respondsToSelector:@selector(accessibilityLabel)] &&
        StringLooksLikeSnapPlus(view.accessibilityLabel)) return YES;
    if ([view respondsToSelector:@selector(accessibilityIdentifier)] &&
        StringLooksLikeSnapPlus(view.accessibilityIdentifier)) return YES;

    if ([view isKindOfClass:[UILabel class]] &&
        StringLooksLikeSnapPlus(((UILabel *)view).text)) return YES;

    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)view;
        if (StringLooksLikeSnapPlus([b titleForState:UIControlStateNormal])) return YES;
    }

    for (UIView *child in view.subviews) {
        if (ViewContainsSnapPlus(child, depth + 1, budget)) return YES;
        if (*budget <= 0) break;
    }
    return NO;
}

static BOOL ClassLooksLikeSnapPlus(id obj) {
    if (!obj) return NO;
    NSString *name = NSStringFromClass([obj class]).lowercaseString;
    NSArray<NSString *> *strongMatches = @[
        @"snapchatplus", @"snapchat_plus", @"plusupsell",
        @"pluspaywall", @"pluspurchase", @"scplus"
    ];
    for (NSString *token in strongMatches) {
        if ([name containsString:token]) return YES;
    }
    return NO;
}

static BOOL ControllerLooksLikeSnapPlus(UIViewController *vc, NSInteger depth) {
    if (!vc || depth > 4) return NO;

    if (ClassLooksLikeSnapPlus(vc)) return YES;
    if (StringLooksLikeSnapPlus(vc.title)) return YES;

    NSInteger budget = 180;
    if (ViewContainsSnapPlus(vc.view, 0, &budget)) return YES;

    if ([vc isKindOfClass:[UINavigationController class]]) {
        UIViewController *top = ((UINavigationController *)vc).topViewController;
        if (top && top != vc && ControllerLooksLikeSnapPlus(top, depth + 1)) return YES;
    }

    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
        if (selected && selected != vc && ControllerLooksLikeSnapPlus(selected, depth + 1)) return YES;
    }

    for (UIViewController *child in vc.childViewControllers) {
        if (child && child != vc && ControllerLooksLikeSnapPlus(child, depth + 1)) return YES;
    }

    return NO;
}

static void RelicPresent(UIViewController *self, SEL _cmd, UIViewController *presented,
                         BOOL animated, void (^completion)(void)) {
    if (launchWindow && NoAdsEnabled() && ControllerLooksLikeSnapPlus(presented, 0)) {
        if (completion) completion();
        return;
    }
    if (origPresent) origPresent(self, _cmd, presented, animated, completion);
}

__attribute__((constructor))
static void RelicSnapPlusInit(void) {
    @autoreleasepool {
        Method method = class_getInstanceMethod([UIViewController class],
            @selector(presentViewController:animated:completion:));
        if (method) {
            origPresent = (void *)method_setImplementation(method, (IMP)RelicPresent);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            launchWindow = NO;
        });
    }
}
