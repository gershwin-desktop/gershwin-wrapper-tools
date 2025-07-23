# gershwin-wrapper-tools


The following should be run to install additional packages needed for this:
```
sudo pkg install -g 'GhostBSD*-dev'
sudo pkg install gershwin-developer
```

## Usage examples

It is important to specify the real binary for an application.  Do not use any shell wrappers or this will have less chance of working.  For example code-oss would be /usr/local/share/code-oss/code-oss.  


### Find an icon using XDG desktop file

```bash
./iconfinder.sh /usr/local/share/applications/code-oss.desktop
```

### Generate new wrappers

```bash
./generate-wrapper-code.sh Code /usr/local/share/code-oss/code-oss /usr/local/share/pixmaps/com.visualstudio.code.oss.png
```

### Install the wrappers in /Applications

```
cd code-app
gmake
sudo gmake install
```

### Known issues
List of applications not working properly yet:

* Telegram (Sometimes can no longer be activated when active)
* VirtualBox (Minimize Virtual machines and activate can cause lockups)