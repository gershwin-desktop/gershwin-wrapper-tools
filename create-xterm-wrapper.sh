#!/bin/sh
#
# create-xterm-wrapper.sh
# Creates a complete xterm GNUstep application wrapper for testing
#

set -e

APP_NAME="XTerm"
EXECUTABLE_PATH="/usr/local/bin/xterm"
SERVICE_NAME="ApplicationWrapper-XTerm"
WINDOW_SEARCH_STRING="xterm"
BUNDLE_ID="org.gnustep.xterm-wrapper"

WRAPPER_DIR="./xterm-wrapper"
BUILD_DIR="${WRAPPER_DIR}/obj"

echo "Creating XTerm GNUstep wrapper..."

# Check if xterm exists
if [ ! -x "${EXECUTABLE_PATH}" ]; then
    echo "ERROR: xterm not found at ${EXECUTABLE_PATH}"
    echo "Please install xterm: sudo pkg install xterm"
    exit 1
fi

# Create wrapper directory
rm -rf "${WRAPPER_DIR}"
mkdir -p "${WRAPPER_DIR}"
mkdir -p "${BUILD_DIR}"

echo "Setting up wrapper files..."

# Create GNUmakefile
cat > "${WRAPPER_DIR}/GNUmakefile" << 'EOF'
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = XTerm
XTerm_OBJC_FILES = ModernMain.m ModernApplicationWrapper.m
XTerm_RESOURCE_FILES = XTerm.png

ADDITIONAL_OBJCFLAGS = -fobjc-arc -fblocks

include $(GNUSTEP_MAKEFILES)/application.make

# Install to /Applications
install:: $(APP_NAME)$(APP_EXTENSION)
	sudo mkdir -p /Applications
	sudo cp -R ./$(APP_NAME)$(APP_EXTENSION) /Applications/
EOF

# Create Info-gnustep.plist
cat > "${WRAPPER_DIR}/Info-gnustep.plist" << EOF
{
    ApplicationDescription = "GNUstep Bash Terminal Shell";
    ApplicationName = "Bash";
    ApplicationRelease = "1.0";
    ApplicationVersion = "1.0";
    Authors = ("GNUstep Application Wrapper");
    CFBundleIdentifier = "${BUNDLE_ID}";
    CFBundleName = "Bash";
    CFBundleShortVersionString = "1.0";
    CFBundleVersion = "1.0";
    Copyright = "Copyright (c) 2024";
    CopyrightDescription = "GNUstep Application Wrapper";
    FullVersionID = "1.0";
    URL = "";
}
EOF

# Create the defines header
cat > "${WRAPPER_DIR}/WrapperDefines.h" << EOF
//
//  WrapperDefines.h
//  XTerm Wrapper Configuration
//

#ifndef WrapperDefines_h
#define WrapperDefines_h

#define APPLICATION_NAME @"${APP_NAME}"
#define EXECUTABLE_PATH @"${EXECUTABLE_PATH}"
#define SERVICE_NAME @"${SERVICE_NAME}"
#define WINDOW_SEARCH_STRING @"${WINDOW_SEARCH_STRING}"
#define BUNDLE_IDENTIFIER @"${BUNDLE_ID}"

#endif /* WrapperDefines_h */
EOF

# Copy the modern wrapper files
echo "Copying wrapper implementation..."
cp "/Network/Users/jmaloney/Documents/gershwin-wrapper-tools/Template/ModernApplicationWrapper.h" "${WRAPPER_DIR}/"
cp "/Network/Users/jmaloney/Documents/gershwin-wrapper-tools/Template/ModernApplicationWrapper.m" "${WRAPPER_DIR}/"

# Create main.m with proper includes
cat > "${WRAPPER_DIR}/ModernMain.m" << 'EOF'
//
//  ModernMain.m
//  XTerm GNUstep Application Wrapper
//

#import <AppKit/AppKit.h>
#import <sys/types.h>
#import <unistd.h>
#import <stdlib.h>
#import <signal.h>
#import "WrapperDefines.h"
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
    NSConnection *existingConnection = [NSConnection connectionWithRegisteredName:SERVICE_NAME host:nil];
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

        // Handle file arguments if any
        if ([launchArgs count] > 0) {
            // Store arguments for later use when launching xterm
        }

        return NSApplicationMain(argc, argv);
    }
}
EOF

# Update the wrapper implementation to include the defines
sed -i.bak '1i\
#import "WrapperDefines.h"
' "${WRAPPER_DIR}/ModernApplicationWrapper.m"

# Create a simple icon (placeholder)
echo "Creating application icon..."
cat > "${WRAPPER_DIR}/create_icon.sh" << 'EOF'
#!/bin/sh
# Create a simple PNG icon for XTerm wrapper
# This is a placeholder - you can replace with a proper icon

# Create a 48x48 black square as placeholder icon
convert -size 48x48 xc:black "XTerm.png" 2>/dev/null || {
    # If ImageMagick not available, create text file
    echo "Icon placeholder for XTerm wrapper" > "XTerm.png"
}
EOF

chmod +x "${WRAPPER_DIR}/create_icon.sh"
cd "${WRAPPER_DIR}" && ./create_icon.sh

echo ""
echo "XTerm wrapper created at: ${WRAPPER_DIR}"
echo ""
echo "To build and install:"
echo "  cd ${WRAPPER_DIR}"
echo "  . /System/Library/Makefiles/GNUstep.sh"
echo "  gmake"
echo "  gmake install"
echo ""
echo "To test:"
echo "  /Applications/XTerm.app/XTerm"
echo ""
echo "The wrapper will appear as a native GNUstep application in your dock"
echo "and will show proper menus when clicked in the window manager."

# Make the entire directory accessible
if [ -d "${WRAPPER_DIR}" ]; then
    chmod -R 755 "${WRAPPER_DIR}"
fi

echo "Done!"
EOF