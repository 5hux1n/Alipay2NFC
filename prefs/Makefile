TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Alipay2NFCPrefs

Alipay2NFCPrefs_FILES = APXRootListController.m
Alipay2NFCPrefs_INSTALL_PATH = /Library/PreferenceBundles
Alipay2NFCPrefs_FRAMEWORKS = UIKit Foundation MobileCoreServices
Alipay2NFCPrefs_PRIVATE_FRAMEWORKS = Preferences
Alipay2NFCPrefs_CFLAGS = -fobjc-arc -Wno-error=deprecated-declarations
Alipay2NFCPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Alipay2NFC.plist$(ECHO_END)
