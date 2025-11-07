//
//  ModernApplicationWrapper.m
//  GNUstep Application Wrapper - Modern ARC Version
//

#import "ModernApplicationWrapper.h"
#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/user.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>

static const NSTimeInterval kWindowListCacheTimeout = 1.0;
static const NSTimeInterval kMonitoringInterval = 2.0;

@implementation ModernApplicationWrapper

- (instancetype)init {
    NSDictionary *defaultConfig = @{
        @"applicationName": APPLICATION_NAME,
        @"executablePath": EXECUTABLE_PATH,
        @"serviceName": SERVICE_NAME,
        @"windowSearchString": WINDOW_SEARCH_STRING,
        @"bundleIdentifier": BUNDLE_IDENTIFIER
    };

    return [self initWithConfiguration:defaultConfig];
}

- (instancetype)initWithConfiguration:(NSDictionary *)config {
    self = [super init];
    if (self) {
        self.applicationName = config[@"applicationName"];
        self.executablePath = config[@"executablePath"];
        self.serviceName = config[@"serviceName"];
        self.windowSearchString = config[@"windowSearchString"];
        self.bundleIdentifier = config[@"bundleIdentifier"];

        self.trackedPIDs = [NSMutableSet set];
        self.primaryPID = 0;
        self.isRunning = NO;
        self.terminationInProgress = NO;

        self.monitoringQueue = [[NSOperationQueue alloc] init];
        self.monitoringQueue.name = [NSString stringWithFormat:@"monitoring.%@", self.serviceName];
        self.monitoringQueue.maxConcurrentOperationCount = 1;

        self.cachedWindowList = [NSMutableArray array];

        [self setupApplicationMenu];
        [self registerWithWorkspace];
    }
    return self;
}

#pragma mark - Application Lifecycle

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    if (![self establishGNUstepService]) {
        NSLog(@"Failed to establish GNUstep service for %@", self.applicationName);
        return;
    }

    // Set application icon if available
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:self.applicationName ofType:@"png"];
    if (iconPath && [[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        if (icon) {
            [NSApp setApplicationIconImage:icon];
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self performSelector:@selector(launchApplication) withObject:nil afterDelay:0.1];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
    if ([self isApplicationCurrentlyRunning]) {
        [self activateX11Windows];
    } else {
        [self launchApplication];
    }
    return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.terminationInProgress) {
        return NSTerminateNow;
    }

    if ([self isApplicationCurrentlyRunning]) {
        [self quitApplication:sender];
        return NSTerminateCancel;
    }

    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopX11WindowMonitoring];

    if (self.applicationTask) {
        [self.applicationTask terminate];
    }
}

#pragma mark - GNUstep Integration

- (BOOL)establishGNUstepService {
    NSConnection *connection = [NSConnection defaultConnection];
    [connection setRootObject:self];

    BOOL success = [connection registerName:self.serviceName];
    if (!success) {
        // Try to connect to existing instance
        NSConnection *existingConnection = [NSConnection connectionWithRegisteredName:self.serviceName host:nil];
        if (existingConnection) {
            id<ModernApplicationWrapperProtocol> existingWrapper = (id<ModernApplicationWrapperProtocol>)[existingConnection rootProxy];
            if (existingWrapper) {
                @try {
                    [existingWrapper activateIgnoringOtherApps:YES];
                    return NO; // Delegate to existing instance
                }
                @catch (NSException *exception) {
                    // Existing connection is stale, try to register again
                    success = [connection registerName:self.serviceName];
                }
            }
        }
    }

    return success;
}

- (void)setupApplicationMenu {
    self.applicationMenu = [[NSMenu alloc] initWithTitle:self.applicationName];

    // About
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"About %@", self.applicationName]
                                                       action:@selector(showAbout:)
                                                keyEquivalent:@""];
    [aboutItem setTarget:self];
    [self.applicationMenu addItem:aboutItem];

    [self.applicationMenu addItem:[NSMenuItem separatorItem]];

    // Services submenu
    NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Services"
                                                          action:nil
                                                   keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    [servicesItem setSubmenu:servicesMenu];
    [NSApp setServicesMenu:servicesMenu];
    [self.applicationMenu addItem:servicesItem];

    [self.applicationMenu addItem:[NSMenuItem separatorItem]];

    // Hide
    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Hide %@", self.applicationName]
                                                      action:@selector(hideApplication:)
                                               keyEquivalent:@"h"];
    [hideItem setTarget:self];
    [self.applicationMenu addItem:hideItem];

    [self.applicationMenu addItem:[NSMenuItem separatorItem]];

    // Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", self.applicationName]
                                                      action:@selector(quitApplication:)
                                               keyEquivalent:@"q"];
    [quitItem setTarget:self];
    [self.applicationMenu addItem:quitItem];

    // Set this as the application's main menu
    [NSApp setMainMenu:self.applicationMenu];
}

- (void)registerWithWorkspace {
    // Register for workspace notifications
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
        selector:@selector(handleWorkspaceChange:)
        name:NSWorkspaceDidLaunchApplicationNotification
        object:nil];

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
        selector:@selector(handleWorkspaceChange:)
        name:NSWorkspaceDidTerminateApplicationNotification
        object:nil];
}

- (void)handleWorkspaceChange:(NSNotification *)notification {
    // Handle workspace notifications if needed
}

#pragma mark - Application Management

- (void)launchApplication {
    [self launchApplicationWithArgs:@[]];
}

- (void)launchApplicationWithArgs:(NSArray<NSString *> *)arguments {
    if ([self isApplicationCurrentlyRunning]) {
        [self activateX11Windows];
        return;
    }

    if (self.applicationTask && [self.applicationTask isRunning]) {
        [self activateX11Windows];
        return;
    }

    [self.trackedPIDs removeAllObjects];
    self.primaryPID = 0;

    self.applicationTask = [[NSTask alloc] init];
    [self.applicationTask setLaunchPath:self.executablePath];
    [self.applicationTask setArguments:arguments];

    NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    [self.applicationTask setEnvironment:environment];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
        selector:@selector(handleApplicationTermination)
        name:NSTaskDidTerminateNotification
        object:self.applicationTask];

    @try {
        [self.applicationTask launch];
        self.primaryPID = [self.applicationTask processIdentifier];
        [self trackPID:self.primaryPID];
        self.isRunning = YES;

        [self startX11WindowMonitoring];
        [self monitorProcessLifecycle];

        // Discover child processes after a delay
        [self performSelector:@selector(discoverChildProcesses) withObject:nil afterDelay:2.0];

    }
    @catch (NSException *exception) {
        self.primaryPID = 0;
        self.isRunning = NO;

        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSTaskDidTerminateNotification
                                                      object:self.applicationTask];
        self.applicationTask = nil;

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithFormat:@"%@ Launch Error", self.applicationName]];
        [alert setInformativeText:[NSString stringWithFormat:@"Could not launch %@ from %@",
                                   self.applicationName, self.executablePath]];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];

        [NSApp terminate:self];
    }
}

- (BOOL)isApplicationCurrentlyRunning {
    if (self.primaryPID > 0) {
        if (kill(self.primaryPID, 0) == 0) {
            return YES;
        } else {
            [self untrackPID:self.primaryPID];
            self.primaryPID = 0;
        }
    }
    return NO;
}

- (void)handleApplicationTermination {
    self.isRunning = NO;

    if (self.applicationTask) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSTaskDidTerminateNotification
                                                      object:self.applicationTask];
        self.applicationTask = nil;
    }

    [self stopX11WindowMonitoring];

    if (!self.terminationInProgress) {
        self.terminationInProgress = YES;
        [NSApp terminate:self];
    }
}

#pragma mark - Process Management

- (void)trackPID:(pid_t)pid {
    [self.trackedPIDs addObject:@(pid)];
}

- (void)untrackPID:(pid_t)pid {
    [self.trackedPIDs removeObject:@(pid)];
}

- (NSArray<NSNumber *> *)getChildProcesses:(pid_t)parentPID {
    int mib[4];
    size_t size;
    struct kinfo_proc *procs;
    int nprocs;
    NSMutableArray *children = [NSMutableArray array];

    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PROC;
    mib[3] = 0;

    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) {
        return children;
    }

    procs = malloc(size);
    if (procs == NULL) {
        return children;
    }

    if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
        free(procs);
        return children;
    }

    nprocs = size / sizeof(struct kinfo_proc);

    for (int i = 0; i < nprocs; i++) {
        if (procs[i].ki_ppid == parentPID) {
            [children addObject:@(procs[i].ki_pid)];
        }
    }

    free(procs);
    return children;
}

- (void)discoverChildProcesses {
    if (self.primaryPID > 0) {
        NSArray *children = [self getChildProcesses:self.primaryPID];
        for (NSNumber *childPID in children) {
            [self trackPID:[childPID intValue]];
        }
    }
}

- (void)monitorProcessLifecycle {
    NSBlockOperation *monitorOperation = [NSBlockOperation blockOperationWithBlock:^{
        while (self.isRunning && !self.terminationInProgress) {
            [NSThread sleepForTimeInterval:kMonitoringInterval];

            if (![self isApplicationCurrentlyRunning]) {
                [self performSelectorOnMainThread:@selector(handleApplicationTermination)
                                       withObject:nil
                                    waitUntilDone:NO];
                break;
            }
        }
    }];

    [self.monitoringQueue addOperation:monitorOperation];
}

#pragma mark - X11 Window Coordination

- (void)startX11WindowMonitoring {
    self.windowMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                               target:self
                                                             selector:@selector(refreshWindowList)
                                                             userInfo:nil
                                                              repeats:YES];
}

- (void)stopX11WindowMonitoring {
    [self.windowMonitorTimer invalidate];
    self.windowMonitorTimer = nil;
}

- (void)refreshWindowList {
    NSDate *now = [NSDate date];

    if (self.lastWindowListUpdate &&
        [now timeIntervalSinceDate:self.lastWindowListUpdate] < kWindowListCacheTimeout &&
        [self.cachedWindowList count] > 0) {
        return;
    }

    [self.cachedWindowList removeAllObjects];

    NSTask *listTask = [[NSTask alloc] init];
    [listTask setLaunchPath:@"/usr/local/bin/wmctrl"];
    [listTask setArguments:@[@"-l"]];

    NSPipe *listPipe = [NSPipe pipe];
    [listTask setStandardOutput:listPipe];
    [listTask setStandardError:[NSPipe pipe]];

    @try {
        [listTask launch];
        [listTask waitUntilExit];

        if ([listTask terminationStatus] == 0) {
            NSData *data = [[listPipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            [self.cachedWindowList addObjectsFromArray:lines];

            self.lastWindowListUpdate = now;
        }
    }
    @catch (NSException *exception) {
        // wmctrl failed, ignore
    }
}

- (NSArray<NSString *> *)getX11WindowIDs {
    [self refreshWindowList];
    NSMutableArray *applicationWindowIDs = [NSMutableArray array];

    for (NSString *line in self.cachedWindowList) {
        if ([line length] > 0) {
            NSRange appRange = [line rangeOfString:self.windowSearchString options:NSCaseInsensitiveSearch];

            if (appRange.location != NSNotFound) {
                NSArray *components = [line componentsSeparatedByString:@" "];
                if ([components count] > 0) {
                    NSString *windowID = components[0];
                    [applicationWindowIDs addObject:windowID];
                }
            }
        }
    }

    return applicationWindowIDs;
}

- (void)activateX11Windows {
    NSArray *windowIDs = [self getX11WindowIDs];

    for (NSString *windowID in windowIDs) {
        NSTask *activateTask = [[NSTask alloc] init];
        [activateTask setLaunchPath:@"/usr/local/bin/wmctrl"];
        [activateTask setArguments:@[@"-i", @"-a", windowID]];
        [activateTask setStandardOutput:[NSPipe pipe]];
        [activateTask setStandardError:[NSPipe pipe]];

        @try {
            [activateTask launch];
            [activateTask waitUntilExit];
        }
        @catch (NSException *exception) {
            // Ignore wmctrl errors
        }
    }
}

- (void)hideX11Windows {
    NSArray *windowIDs = [self getX11WindowIDs];

    for (NSString *windowID in windowIDs) {
        NSTask *minimizeTask = [[NSTask alloc] init];
        [minimizeTask setLaunchPath:@"/usr/local/bin/wmctrl"];
        [minimizeTask setArguments:@[@"-i", @"-b", @"add,shaded", windowID]];
        [minimizeTask setStandardOutput:[NSPipe pipe]];
        [minimizeTask setStandardError:[NSPipe pipe]];

        @try {
            [minimizeTask launch];
            [minimizeTask waitUntilExit];
        }
        @catch (NSException *exception) {
            // Ignore wmctrl errors
        }
    }
}

#pragma mark - Menu Management

- (void)showApplicationMenuAtPoint:(NSPoint)point {
    // This will be called by the window manager
    [NSMenu popUpContextMenu:self.applicationMenu withEvent:[NSApp currentEvent] forView:nil];
}

- (void)showMenuAtPoint:(NSPoint)point {
    [self showApplicationMenuAtPoint:point];
}

#pragma mark - Menu Actions

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:self.applicationName];
    [alert setInformativeText:[NSString stringWithFormat:@"GNUstep Application Wrapper\n\nWrapped Application: %@", self.executablePath]];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showServices:(id)sender {
    // Services are handled automatically by GNUstep
}

- (void)hideApplication:(id)sender {
    [self hideX11Windows];
    [NSApp hide:sender];
}

- (void)forceTerminateIfNeeded {
    if (self.applicationTask && [self.applicationTask isRunning]) {
        [self.applicationTask terminate];
    }
}

- (void)quitApplication:(id)sender {
    if ([self isApplicationCurrentlyRunning]) {
        // Try graceful shutdown first
        NSArray *windowIDs = [self getX11WindowIDs];
        for (NSString *windowID in windowIDs) {
            NSTask *closeTask = [[NSTask alloc] init];
            [closeTask setLaunchPath:@"/usr/local/bin/wmctrl"];
            [closeTask setArguments:@[@"-i", @"-c", windowID]];
            [closeTask setStandardOutput:[NSPipe pipe]];
            [closeTask setStandardError:[NSPipe pipe]];

            @try {
                [closeTask launch];
                [closeTask waitUntilExit];
            }
            @catch (NSException *exception) {
                // Ignore wmctrl errors
            }
        }

        // Force terminate the application task and then quit wrapper
        if (self.applicationTask && [self.applicationTask isRunning]) {
            [self.applicationTask terminate];
        }
    }

    // Always quit the wrapper application
    [NSApp terminate:self];
}

#pragma mark - Protocol Methods

- (void)activateIgnoringOtherApps:(BOOL)flag {
    if ([self isApplicationCurrentlyRunning]) {
        [self activateX11Windows];
    } else {
        [self launchApplication];
    }

    if (flag) {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)hide:(id)sender {
    [self hideApplication:sender];
}

- (void)unhideWithoutActivation {
    // Unhide X11 windows
    NSArray *windowIDs = [self getX11WindowIDs];

    for (NSString *windowID in windowIDs) {
        NSTask *unhideTask = [[NSTask alloc] init];
        [unhideTask setLaunchPath:@"/usr/local/bin/wmctrl"];
        [unhideTask setArguments:@[@"-i", @"-b", @"remove,shaded", windowID]];
        [unhideTask setStandardOutput:[NSPipe pipe]];
        [unhideTask setStandardError:[NSPipe pipe]];

        @try {
            [unhideTask launch];
            [unhideTask waitUntilExit];
        }
        @catch (NSException *exception) {
            // Ignore wmctrl errors
        }
    }
}

- (BOOL)isHidden {
    return [NSApp isHidden];
}

- (void)terminate:(id)sender {
    [self quitApplication:sender];
}

- (BOOL)isRunning {
    return self.isRunning;
}

- (NSNumber *)processIdentifier {
    if (self.applicationTask && [self.applicationTask isRunning]) {
        return @([self.applicationTask processIdentifier]);
    }
    return nil;
}

- (NSString *)applicationName {
    return _applicationName;
}

- (NSMenu *)applicationMenu {
    return _applicationMenu;
}

- (void)activateIgnoringOtherApps:(BOOL)flag {
    [NSApp activateIgnoringOtherApps:flag];
}

@end