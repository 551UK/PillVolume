#import "PVRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static NSString * const PVPrefsDomain = @"com.551.pillvolume";
static NSString * const PVPrefsChanged = @"com.551.pillvolume/preferences.changed";

static void PVSpawnTool(const char *tool, char * const argv[]) {
    if (!tool || access(tool, X_OK) != 0) return;

    pid_t pid = 0;
    posix_spawn(&pid, tool, NULL, NULL, argv, environ);
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
    [mainGroup setProperty:@"Compact pill-style volume HUD for iOS 16. Use the master switch to enable or disable the tweak without uninstalling." forKey:@"footerText"];
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

    PSSpecifier *repo = [PSSpecifier preferenceSpecifierNamed:@"GitHub Repo"
                                                       target:self
                                                          set:nil
                                                          get:nil
                                                       detail:nil
                                                         cell:PSButtonCell
                                                         edit:nil];
    repo.buttonAction = @selector(openRepo);
    repo.identifier = @"repo";
    [repo setProperty:@"repo" forKey:@"id"];
    [repo setButtonAction:@selector(openRepo)];
    [repo setProperty:NSStringFromSelector(@selector(openRepo)) forKey:@"action"];
    [specifiers addObject:repo];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Actions"]];

    PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Respring"
                                                          target:self
                                                             set:nil
                                                             get:nil
                                                          detail:nil
                                                            cell:PSButtonCell
                                                            edit:nil];
    respring.buttonAction = @selector(respring);
    respring.identifier = @"respring";
    [respring setProperty:@"respring" forKey:@"id"];
    [respring setButtonAction:@selector(respring)];
    [respring setProperty:NSStringFromSelector(@selector(respring)) forKey:@"action"];
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = nil;
    if ([self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        specifier = [self specifierAtIndexPath:indexPath];
    }

    NSString *identifier = [specifier propertyForKey:@"id"] ?: specifier.identifier;
    if ([identifier isEqualToString:@"repo"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self openRepo];
        return;
    }

    if ([identifier isEqualToString:@"respring"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self respring];
        return;
    }

    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)openRepo {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/PillVolume"];
    if (!url) return;

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (workspaceClass && [workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        id (*msgSendId)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        id workspace = msgSendId((id)workspaceClass, @selector(defaultWorkspace));

        SEL sensitiveSelector = NSSelectorFromString(@"openSensitiveURL:withOptions:");
        if (workspace && [workspace respondsToSelector:sensitiveSelector]) {
            BOOL (*msgSendOpen)(id, SEL, NSURL *, NSDictionary *) = (BOOL (*)(id, SEL, NSURL *, NSDictionary *))objc_msgSend;
            if (msgSendOpen(workspace, sensitiveSelector, url, @{})) return;
        }

        SEL openSelector = NSSelectorFromString(@"openURL:withOptions:");
        if (workspace && [workspace respondsToSelector:openSelector]) {
            BOOL (*msgSendOpen)(id, SEL, NSURL *, NSDictionary *) = (BOOL (*)(id, SEL, NSURL *, NSDictionary *))objc_msgSend;
            if (msgSendOpen(workspace, openSelector, url, @{})) return;
        }
    }

    UIApplication *application = UIApplication.sharedApplication;
    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [application openURL:url];
#pragma clang diagnostic pop
    }
}

- (void)respring {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        const char *sbreload = "/var/jb/usr/bin/sbreload";
        if (access(sbreload, X_OK) == 0) {
            char *args[] = {(char *)sbreload, NULL};
            PVSpawnTool(sbreload, args);
            return;
        }

        const char *rootlessKillall = "/var/jb/usr/bin/killall";
        if (access(rootlessKillall, X_OK) == 0) {
            char *args[] = {(char *)rootlessKillall, (char *)"-9", (char *)"SpringBoard", NULL};
            PVSpawnTool(rootlessKillall, args);
            return;
        }

        const char *systemKillall = "/usr/bin/killall";
        char *args[] = {(char *)systemKillall, (char *)"-9", (char *)"SpringBoard", NULL};
        PVSpawnTool(systemKillall, args);
    });
}

@end
