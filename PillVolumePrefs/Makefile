ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PillVolumePrefs
PillVolumePrefs_FILES = PVRootListController.m
PillVolumePrefs_FRAMEWORKS = Foundation CoreFoundation UIKit
PillVolumePrefs_PRIVATE_FRAMEWORKS = Preferences
PillVolumePrefs_INSTALL_PATH = /Library/PreferenceBundles
PillVolumePrefs_RESOURCE_DIRS = Resources
PillVolumePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
