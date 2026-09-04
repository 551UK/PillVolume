#import "PVRootListController.h"
#import <UIKit/UIKit.h>
#import <spawn.h>

@implementation PVRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    pid_t pid;
    const char *tool = "/var/jb/usr/bin/killall";
    const char *args[] = {tool, "-9", "SpringBoard", NULL};
    posix_spawn(&pid, tool, NULL, NULL, (char * const *)args, NULL);
}

@end
