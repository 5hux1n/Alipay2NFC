ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Alipay2NFC
Alipay2NFC_FILES = Tweak.x
Alipay2NFC_CFLAGS = -fobjc-arc -Wno-unused-function \
                    -Wno-error=deprecated-declarations \
                    -Wno-error=unguarded-availability-new
Alipay2NFC_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

# 确保 filter 以 XML 落盘（roothide Patcher 只认 XML/二进制）
before-package::
	@find $(THEOS_STAGING_DIR) -path "*/DynamicLibraries/Alipay2NFC.plist" -exec cp Alipay2NFC.plist {} \;
