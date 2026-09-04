ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PillVolume
PillVolume_FILES = Tweak.xm
PillVolume_FRAMEWORKS = UIKit QuartzCore
PillVolume_CFLAGS = -fobjc-arc

SUBPROJECTS += PillVolumePrefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
