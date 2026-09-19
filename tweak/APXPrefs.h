/* 配置读写约定：tweak 与 prefs bundle 共用 */
#ifndef APX_PREFS_H
#define APX_PREFS_H

#define APX_DOMAIN      @"im.mjh.alipay2nfc"
/* Darwin 通知：prefs 改动后广播，tweak 收到即热更新（无需注销） */
#define APX_NOTIFY_NAME "im.mjh.alipay2nfc/prefsChanged"

#define APX_KEY_ENABLED  @"Enabled"              /* 总开关，默认 YES */
#define APX_KEY_ASK      @"AskBeforeJump"        /* 跳转前询问，默认 NO */
#define APX_KEY_TARGET   @"TargetCloneBundleID"  /* 指定多开包；空 = 自动 */
#define APX_KEY_DEBUG    @"Debug"                /* 详细日志，默认 NO */
/* tweak 在支付宝进程内枚举到的多开包清单：[{bid,name}]，供设置面板展示 */
#define APX_KEY_CLONES   @"DetectedClones"

#endif
