# gershwin-wrapper-template
Integrated Application wrapper for Gershwin

## Why This Wrapper?

Traditional application wrappers suffer from several critical limitations:

- **Polling overhead**: Continuous process checking wastes CPU cycles
- **Delayed termination**: Slow detection when the wrapped application exits
- **Resource waste**: Background monitoring even when nothing is happening
- **Poor integration**: Limited interaction with desktop environment features

This event-driven wrapper solves these problems by:

- **Zero polling**: Uses FreeBSD kernel events (kqueue) for instant process state changes
- **Immediate response**: Sub-millisecond termination detection
- **Zero idle CPU**: Completely passive monitoring when Firefox is running
- **Full integration**: Native Workspace support with proper application lifecycle events

## How It Works

### Multi-Layer Event System

The wrapper employs a sophisticated three-tier monitoring system:

1. **Primary**: NSTask termination notifications - immediate detection when Firefox exits
2. **Secondary**: kqueue child process tracking - FreeBSD native event system

### Single Instance Management

Uses NSConnection distributed objects instead of fragile PID files:
- Automatic delegation to existing instances
- Clean connection testing with fallback recovery
- No orphaned lock files or race conditions

### Dynamic Dock Integration

- Smart dock icon visibility management
- Seamless transformation between background and foreground modes
- Window activation via wmctrl integration