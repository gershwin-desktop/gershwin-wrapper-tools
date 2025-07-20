# gershwin-wrapper-tools

This now requires the following packages

```
libdispatch
wmctrl-fork
```

### Generate new wrappers

```bash
./generate-wrapper-code.sh Chromium /usr/local/bin/chromium /Users/jmaloney/Downloads/chrome.png
```

### Find icon using XDG

```bash
./iconfinder.sh /usr/local/share/applications/chromium-browser.desktop
