ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PillVolume
PillVolume_FILES = Tweak.xm
PillVolume_FRAMEWORKS = UIKit QuartzCore
PillVolume_CFLAGS = -fobjc-arc -Wno-unused-function

SUBPROJECTS += PillVolumePrefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 Preferences || true"
	install.exec "killall -9 SpringBoard"
