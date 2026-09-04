#import "PVRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";

static BOOL PVSpawnTool(const char *tool, char * const argv[]) {
    if (!tool || access(tool, X_OK) != 0) return NO;

    pid_t pid = 0;
    return posix_spawn(&pid, tool, NULL, NULL, argv, environ) == 0;
}

@implementation PVRootListController

- (void)viewDidLoad {
    [super viewDidLoad];

    UIImage *image = [UIImage systemImageNamed:@"speaker.wave.2.fill"];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:image];
    iconView.tintColor = UIColor.labelColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"PillVolume";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.textColor = UIColor.labelColor;

    UIStackView *titleView = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, titleLabel]];
    titleView.axis = UILayoutConstraintAxisHorizontal;
    titleView.alignment = UIStackViewAlignmentCenter;
    titleView.spacing = 6.0;

    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor constraintEqualToConstant:19.0],
        [iconView.heightAnchor constraintEqualToConstant:19.0]
    ]];

    self.navigationItem.titleView = titleView;
}

- (NSArray *)manualSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *mainGroup = [PSSpecifier groupSpecifierWithName:@"PillVolume"];
    [mainGroup setProperty:@"Compact pill-style volume HUD for iOS 16. Lock Screen injection has been removed to keep stock iOS behaviour stable." forKey:@"footerText"];
    [specifiers addObject:mainGroup];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"Master Enabled"
                                                          target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:nil
                                                            cell:PSSwitchCell
                                                            edit:nil];
    [enabled setProperty:PVPrefsDomain forKey:@"defaults"];
    [enabled setProperty:@"Enabled" forKey:@"key"];
    [enabled setProperty:@YES forKey:@"default"];
    [enabled setProperty:PVPrefsChanged forKey:@"PostNotification"];
    [specifiers addObject:enabled];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Links"]];

    PSSpecifier *repo = [PSSpecifier buttonSpecifierWithTitle:@"GitHub Repo"
                                                       target:self
                                                       action:@selector(openRepo)
                                             confirmationInfo:nil];
    [specifiers addObject:repo];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Actions"]];

    PSSpecifier *respring = [PSSpecifier buttonSpecifierWithTitle:@"Respring"
                                                           target:self
                                                           action:@selector(respring)
                                                 confirmationInfo:nil];
    [specifiers addObject:respring];

    return specifiers;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self manualSpecifiers] copy];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *defaults = [specifier propertyForKey:@"defaults"] ?: PVPrefsDomain;
    NSString *key = [specifier propertyForKey:@"key"];
    id defaultValue = [specifier propertyForKey:@"default"];

    if (!key) return defaultValue;

    CFPreferencesAppSynchronize((__bridge CFStringRef)defaults);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)defaults);
    if (value) return CFBridgingRelease(value);

    return defaultValue;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *defaults = [specifier propertyForKey:@"defaults"] ?: PVPrefsDomain;
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *notification = [specifier propertyForKey:@"PostNotification"];

    if (!key) return;

    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)defaults);
    CFPreferencesAppSynchronize((__bridge CFStringRef)defaults);

    if (notification.length > 0) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             (__bridge CFStringRef)notification,
                                             NULL,
                                             NULL,
                                             true);
    }
}

- (void)openRepo {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/PillVolume"];
    if (!url) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = UIApplication.sharedApplication;
        if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
            [application openURL:url options:@{} completionHandler:nil];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [application openURL:url];
#pragma clang diagnostic pop
        }
    });
}

- (void)openRepo:(id)sender {
    [self openRepo];
}

- (void)respring {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        const char *sbreload = "/var/jb/usr/bin/sbreload";
        if (access(sbreload, X_OK) == 0) {
            char *args[] = {(char *)sbreload, NULL};
            if (PVSpawnTool(sbreload, args)) return;
        }

        const char *rootlessKillall = "/var/jb/usr/bin/killall";
        if (access(rootlessKillall, X_OK) == 0) {
            char *args[] = {(char *)rootlessKillall, (char *)"-9", (char *)"SpringBoard", NULL};
            if (PVSpawnTool(rootlessKillall, args)) return;
        }

        const char *systemKillall = "/usr/bin/killall";
        char *args[] = {(char *)systemKillall, (char *)"-9", (char *)"SpringBoard", NULL};
        PVSpawnTool(systemKillall, args);
    });
}

- (void)respring:(id)sender {
    [self respring];
}

@end
