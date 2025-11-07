//
//  ModernApplicationWrapper.h
//  GNUstep Application Wrapper - Modern ARC Version
//
//  True GNUstep application that coordinates with X11 child processes
//

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@protocol ModernApplicationWrapperProtocol <NSObject>
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)hide:(id)sender;
- (void)unhideWithoutActivation;
- (BOOL)isHidden;
- (void)terminate:(id)sender;
- (BOOL)isRunning;
- (NSNumber *)processIdentifier;
- (NSString *)applicationName;
- (NSMenu *)applicationMenu;
- (void)showMenuAtPoint:(NSPoint)point;
@end

@interface ModernApplicationWrapper : NSObject <ModernApplicationWrapperProtocol, NSApplicationDelegate>

@property (nonatomic, strong) NSString *applicationName;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *bundleIdentifier;
@property (nonatomic, strong) NSString *windowSearchString;

@property (nonatomic, strong) NSTask *applicationTask;
@property (nonatomic, strong) NSMenu *applicationMenu;

@property (nonatomic, strong) NSMutableSet<NSNumber *> *trackedPIDs;
@property (nonatomic, assign) pid_t primaryPID;

@property (nonatomic, strong) NSOperationQueue *monitoringQueue;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL terminationInProgress;

@property (nonatomic, strong) NSTimer *windowMonitorTimer;
@property (nonatomic, strong) NSMutableArray<NSString *> *cachedWindowList;
@property (nonatomic, strong) NSDate *lastWindowListUpdate;

- (instancetype)initWithConfiguration:(NSDictionary *)config;

// Application Lifecycle
- (void)launchApplication;
- (void)launchApplicationWithArgs:(NSArray<NSString *> *)arguments;
- (BOOL)isApplicationCurrentlyRunning;
- (void)handleApplicationTermination;

// GNUstep Integration
- (BOOL)establishGNUstepService;
- (void)setupApplicationMenu;
- (void)registerWithWorkspace;

// X11 Coordination
- (void)startX11WindowMonitoring;
- (void)stopX11WindowMonitoring;
- (void)activateX11Windows;
- (void)hideX11Windows;
- (NSArray<NSString *> *)getX11WindowIDs;

// Menu Management
- (void)showApplicationMenuAtPoint:(NSPoint)point;

// Menu Actions
- (void)showAbout:(id)sender;
- (void)showServices:(id)sender;
- (void)hideApplication:(id)sender;
- (void)quitApplication:(id)sender;

// Process Management (ARC-compatible)
- (void)trackPID:(pid_t)pid;
- (void)untrackPID:(pid_t)pid;
- (NSArray<NSNumber *> *)getChildProcesses:(pid_t)parentPID;
- (void)monitorProcessLifecycle;

@end