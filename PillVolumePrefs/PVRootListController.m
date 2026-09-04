#import "PVRootListController.h"
#import <UIKit/UIKit.h>

@implementation PVRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    pid_t pid;
    const char *args[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, args[0], NULL, NULL, (char * const *)args, NULL);
}

@end
