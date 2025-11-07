//
//  ModernMain.m
//  GNUstep Application Wrapper - Modern ARC Version
//

#import <AppKit/AppKit.h>
#import <sys/types.h>
#import <unistd.h>
#import <stdlib.h>
#import <signal.h>
#import "ModernApplicationWrapper.h"

void signalHandler(int sig) {
    (void)sig;
    exit(0);
}

@interface ModernApplicationWrapper (InstanceDetection)
+ (BOOL)checkForExistingInstance;
@end

@implementation ModernApplicationWrapper (InstanceDetection)

+ (BOOL)checkForExistingInstance {
    NSConnection *existingConnection = [NSConnection connectionWithRegisteredName:@SERVICE_NAME host:nil];
    if (existingConnection) {
        id<ModernApplicationWrapperProtocol> existingWrapper = (id<ModernApplicationWrapperProtocol>)[existingConnection rootProxy];
        if (existingWrapper) {
            @try {
                BOOL isRunning = [existingWrapper isRunning];
                (void)isRunning;

                [existingWrapper activateIgnoringOtherApps:YES];
                return YES;
            }
            @catch (NSException *exception) {
                // Connection is stale, continue with new instance
            }
        }
    }

    return NO;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGTERM, signalHandler);
        signal(SIGINT, signalHandler);
        signal(SIGHUP, signalHandler);
        signal(SIGPIPE, SIG_IGN);

        NSApplication *app = [NSApplication sharedApplication];

        if ([ModernApplicationWrapper checkForExistingInstance]) {
            return 0;
        }

        NSMutableArray *launchArgs = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            [launchArgs addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        ModernApplicationWrapper *wrapper = [[ModernApplicationWrapper alloc] init];
        [app setDelegate:wrapper];

        // Handle file arguments
        if ([launchArgs count] > 0) {
            // Pass arguments to the wrapped application when it launches
            // This will be handled by launchApplicationWithArgs:
        }

        return NSApplicationMain(argc, argv);
    }
}