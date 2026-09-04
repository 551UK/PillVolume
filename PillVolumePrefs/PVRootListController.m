#import "PVRootListController.h"
#import <UIKit/UIKit.h>
#import <spawn.h>

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

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)openRepo {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/PillVolume"];
    if (!url) return;

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
    pid_t pid;
    const char *tool = "/var/jb/usr/bin/killall";
    const char *args[] = {tool, "-9", "SpringBoard", NULL};
    posix_spawn(&pid, tool, NULL, NULL, (char * const *)args, NULL);
}

@end
