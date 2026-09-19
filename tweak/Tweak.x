/*
 * Alipay2NFC — 碰一碰重定向
 *
 * ═══ 就三件事 ═══
 *   1) 官方支付宝收到碰一碰 URL（Universal Link / App Clip 投递）
 *   2) 官方包把 URL 写进剪贴板，然后按 bundle id 拉起多开包
 *   3) 多开包读剪贴板，把 URL 投给自己的 continueUserActivity
 *
 * ═══ 设计要点（每一条都是为了少写代码）═══
 *
 * ● 只挂 NSUserActivity 上的两个方法
 *   实测碰一碰无论冷启动还是热启动，URL 都经 NSUserActivity 传递：
 *     热启动 → 系统调 setWebpageURL: 塞进来
 *     冷启动 → App 启动后读 webpageURL
 *   一个管"写入时"、一个管"读取时"，覆盖两条路。
 *   其他入口（UIOpenURLContext / UIApplication openURL:）实测从未触发，不挂。
 *
 * ● 用剪贴板而不是 URL scheme
 *   多开包 bundle id 常含非法字符（emoji 等），iOS 只允许 [A-Za-z0-9.-]，
 *   LaunchServices 不会注册它声明的 scheme。剪贴板是唯一
 *   无需改 Info.plist、无需重签名、且天然跨沙盒的通道。
 *
 * ● 多开包 bundle id 用 enumerateApplicationsOfType:block: 自动发现
 *   这走 XPC 到 lsd，是沙盒 App 内唯一可用的枚举方式
 *   （实测 allInstalledApplications / allApplications 在沙盒里都返回 0）。
 *   不需要配置文件、不需要用户先打开多开包、不需要猜后缀。
 *
 * ● 纯 libobjc，不含 CydiaSubstrate
 *   避开 roothide 下弱链接符号为 NULL 导致的 pc=0 崩溃，
 *   同时天然兼容 rootful / rootless / roothide。
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "APXPrefs.h"

#define OFFICIAL_BID   @"com.alipay.iphoneclient"
#define TAP_MARK       @"ALIPAYNFC1:"      /* 碰一碰载荷 */

/* 枚举失败时的兜底（极少用到） */
#define CLONE_FALLBACK @"com.alipay.iphoneclient\U0001F621"

static void APXLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSLog(@"[Alipay2NFC] %@", [[NSString alloc] initWithFormat:fmt arguments:ap]);
    va_end(ap);
}

static IMP gSetWebpageURL = NULL, gWebpageURL = NULL;

static BOOL APXIsOfficial(void) {
    return [[NSBundle mainBundle].bundleIdentifier isEqualToString:OFFICIAL_BID];
}

/* 多开包 = 不是官方，但确实是支付宝 */
static BOOL APXIsClone(void) {
    NSBundle *b = [NSBundle mainBundle];
    if ([b.bundleIdentifier isEqualToString:OFFICIAL_BID]) return NO;
    NSDictionary *i = b.infoDictionary;
    if ([i[@"CFBundleExecutable"] isEqualToString:@"AlipayWallet"]) return YES;
    NSString *n = i[@"CFBundleDisplayName"] ?: i[@"CFBundleName"] ?: @"";
    return [n containsString:@"支付宝"] || [n containsString:@"Alipay"];
}

static NSString *APXPasteboard(void) {
    NSString *s = [UIPasteboard generalPasteboard].string;
    return [s isKindOfClass:[NSString class]] ? s : nil;
}

static void APXSetPasteboard(NSString *s) {
    @try { [UIPasteboard generalPasteboard].string = s; } @catch (__unused NSException *e) {}
}

/* 前置声明 */
static NSString *APXCloneBID(void);
static void APXInvalidateCloneCache(void);

/* ─────────────── 配置（支持热更新）─────────────── */

/*
 * 读配置。两条通道都试：
 *   1) CFPreferences —— 走 cfprefsd，是 tweak 的标准做法
 *   2) 直接读文件   —— 部分越狱/沙盒组合下 cfprefsd 不给读
 * 任一成功即可。
 */
static id APXPrefRaw(NSString *key) {
    CFStringRef k = (__bridge CFStringRef)key;
    CFStringRef d = (__bridge CFStringRef)APX_DOMAIN;

    CFPropertyListRef v = CFPreferencesCopyAppValue(k, d);
    if (v) return CFBridgingRelease(v);

    NSDictionary *f = [NSDictionary dictionaryWithContentsOfFile:
                       @"/var/mobile/Library/Preferences/" APX_DOMAIN ".plist"];
    return f[key];
}

static BOOL APXPrefBool(NSString *key, BOOL dflt) {
    id v = APXPrefRaw(key);
    return v ? [v boolValue] : dflt;
}

static NSString *APXPrefString(NSString *key) {
    id v = APXPrefRaw(key);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

/* 配置变了：清掉缓存的目标多开包，下次直接用新值 */
static void APXPrefsChanged(CFNotificationCenterRef c, void *obs, CFStringRef name,
                            const void *obj, CFDictionaryRef info) {
    APXLog(@"收到设置变更通知，热更新");
    APXInvalidateCloneCache();
}

static void APXWatchPrefs(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, APXPrefsChanged,
                                    CFSTR(APX_NOTIFY_NAME), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

/* ─────────────── 跳转前询问 ─────────────── */

static void APXForward(NSURL *u, NSString *clone);

static void APXAskUser(NSURL *u) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *win = app.keyWindow;
        if (!win) {
            for (UIWindow *w in app.windows) { if (w.isKeyWindow) { win = w; break; } }
        }
        if (!win) { APXForward(u, APXCloneBID()); return; }   /* 没窗口就别问了，直接跳 */

        NSString *clone = APXCloneBID();
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"碰一碰"
                                                                  message:@"这次碰一碰要跳到多开客户端吗？"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"跳转到 %@", clone]
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *x) { APXForward(u, clone); }]];
        [a addAction:[UIAlertAction actionWithTitle:@"用官方支付宝支付"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
        [win.rootViewController presentViewController:a animated:YES completion:nil];
    });
}

/* ─────────────── 官方包：转发 ─────────────── */

static BOOL APXIsTapURL(NSURL *u) {
    NSString *h = u.host.lowercaseString ?: @"";
    NSString *s = u.scheme.lowercaseString ?: @"";
    if ([h isEqualToString:@"render.alipay.com"]) return YES;
    if ([h isEqualToString:@"nfc"] &&
        ([s isEqualToString:@"alipay"] || [s isEqualToString:@"alipays"])) return YES;
    NSString *a = u.absoluteString ?: @"";
    return [a containsString:@"/ulink/"] || [a containsString:@"nfc/app"];
}

/*
 * 自动发现多开包：枚举已安装 App，找 bundle id 以官方 id 为前缀者。
 *
 * 用 enumerateApplicationsOfType:block: —— 它走 XPC 到 lsd，
 * 是唯一在沙盒 App 内可用的枚举方式（实测 allInstalledApplications
 * 与 allApplications 在沙盒里都返回 0）。
 */
static NSString *gCloneCache = nil;

static void APXInvalidateCloneCache(void) { gCloneCache = nil; }

static NSString *APXCloneBID(void) {
    /* 用户指定优先 */
    NSString *target = APXPrefString(APX_KEY_TARGET);
    if (target.length) return target;

    if (gCloneCache) return gCloneCache;

    @try {
        Class wsCls = objc_getClass("LSApplicationWorkspace");
        id ws = ((id (*)(id, SEL))objc_msgSend)(wsCls, sel_registerName("defaultWorkspace"));
        SEL en = sel_registerName("enumerateApplicationsOfType:block:");

        if ([ws respondsToSelector:en]) {
            NSMutableArray *all = [NSMutableArray array];
            void (^collect)(id) = ^(id proxy) { if (proxy) [all addObject:proxy]; };
            ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(ws, en, 0, collect);
            ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(ws, en, 1, collect);

            for (id p in all) {
                NSString *b = ((id (*)(id, SEL))objc_msgSend)(p, sel_registerName("bundleIdentifier"));
                if (![b isKindOfClass:[NSString class]]) continue;
                if ([b isEqualToString:OFFICIAL_BID]) continue;
                if ([b hasPrefix:OFFICIAL_BID]) { gCloneCache = b; break; }
            }
            APXLog(@"枚举 %lu 个 App，多开包 = %@", (unsigned long)all.count, gCloneCache);

            /* 把检测到的多开包清单写进配置，供设置面板展示
             * （设置面板在 Settings 进程里，枚举能力不一定可用） */
            NSMutableArray *list = [NSMutableArray array];
            for (id p in all) {
                NSString *b = ((id (*)(id, SEL))objc_msgSend)(p, sel_registerName("bundleIdentifier"));
                if (![b isKindOfClass:[NSString class]]) continue;
                if ([b isEqualToString:OFFICIAL_BID] || ![b hasPrefix:OFFICIAL_BID]) continue;
                NSString *n = nil;
                @try { n = ((id (*)(id, SEL))objc_msgSend)(p, sel_registerName("localizedName")); } @catch (__unused NSException *e) {}
                [list addObject:@{@"bid": b, @"name": ([n isKindOfClass:[NSString class]] && n.length) ? n : b}];
            }
            if (list.count) {
                CFPreferencesSetAppValue((__bridge CFStringRef)APX_KEY_CLONES,
                                         (__bridge CFPropertyListRef)list,
                                         (__bridge CFStringRef)APX_DOMAIN);
                CFPreferencesAppSynchronize((__bridge CFStringRef)APX_DOMAIN);
                APXLog(@"已写入 %lu 个多开包到设置面板", (unsigned long)list.count);
            }
        }
    } @catch (__unused NSException *e) {}

    if (!gCloneCache) { gCloneCache = CLONE_FALLBACK; APXLog(@"未枚举到，使用兜底 %@", gCloneCache); }
    return gCloneCache;
}

static void APXForward(NSURL *u, NSString *clone) {
    APXLog(@"碰一碰: %@  ->  %@", u, clone);
    NSString *payload = [TAP_MARK stringByAppendingString:u.absoluteString];

    dispatch_async(dispatch_get_main_queue(), ^{
        APXSetPasteboard(payload);
        @try {
            Class ws = objc_getClass("LSApplicationWorkspace");
            id w = ((id (*)(id, SEL))objc_msgSend)(ws, sel_registerName("defaultWorkspace"));
            BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(w, sel_registerName("openApplicationWithBundleID:"), clone);
            APXLog(@"拉起 %@ -> %d", clone, ok);
        } @catch (__unused NSException *e) {}
    });
}

/* 同一 URL 5 秒内只转一次：webpageURL 一次碰一碰会被读 20+ 次 */
static BOOL APXShouldHandle(NSURL *u) {
    static NSString *last = nil;
    static NSTimeInterval t0 = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([u.absoluteString isEqualToString:last] && now - t0 < 5.0) return NO;
    last = u.absoluteString; t0 = now;
    return YES;
}

static void APXTryForward(NSURL *u) {
    if (!APXIsOfficial()) return;
    if (!APXPrefBool(APX_KEY_ENABLED, YES)) return;   /* 总开关：关掉就用官方支付 */
    if (!APXIsTapURL(u)) return;
    if (!APXShouldHandle(u)) return;

    if (APXPrefBool(APX_KEY_ASK, NO)) APXAskUser(u);
    else                              APXForward(u, APXCloneBID());
}

/* 入口 1：系统写入时 */
static void APXHookedSetWebpageURL(id self, SEL _cmd, NSURL *u) {
    APXTryForward(u);
    if (gSetWebpageURL) ((void (*)(id, SEL, NSURL *))gSetWebpageURL)(self, _cmd, u);
}

/* 入口 2：App 读取时（冷启动走这条） */
static NSURL *APXHookedWebpageURL(id self, SEL _cmd) {
    NSURL *u = gWebpageURL ? ((NSURL *(*)(id, SEL))gWebpageURL)(self, _cmd) : nil;
    APXTryForward(u);
    return u;
}

/* ─────────────── 多开包：接收 ─────────────── */

static void APXDeliver(NSURL *u) {
    NSUserActivity *act = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    act.webpageURL = u;
    UIApplication *app = [UIApplication sharedApplication];

    /* Scene delegate（iOS 13+，支付宝是 DFSceneDelegate） */
    if ([app respondsToSelector:@selector(connectedScenes)]) {
        for (UIScene *sc in app.connectedScenes) {
            if ([sc.delegate respondsToSelector:@selector(scene:continueUserActivity:)]) {
                APXLog(@"投递给 %@", NSStringFromClass([sc.delegate class]));
                ((void (*)(id, SEL, id, id))objc_msgSend)(sc.delegate,
                    @selector(scene:continueUserActivity:), sc, act);
                return;
            }
        }
    }
    /* 老版本 App delegate */
    if ([app.delegate respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
        APXLog(@"投递给 %@", NSStringFromClass([app.delegate class]));
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(app.delegate,
            @selector(application:continueUserActivity:restorationHandler:), app, act, nil);
    }
}

/* 多开包被激活：若剪贴板里是碰一碰载荷，取走并投递 */
static void APXOnActivate(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *s = APXPasteboard();
        if (![s hasPrefix:TAP_MARK]) return;

        APXSetPasteboard(@"");
        NSString *us = [s substringFromIndex:TAP_MARK.length];
        APXLog(@"收到载荷: %@", us);
        NSURL *u = [NSURL URLWithString:us];
        if (u) APXDeliver(u);
    });
}

/* ─────────────── 装载 ─────────────── */

static void APXHook(Class c, const char *sel, IMP imp, IMP *orig) {
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(sel));
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, imp);
}

__attribute__((constructor))
static void APXInit(void) {
    @autoreleasepool {
        APXLog(@"加载到 %@", [NSBundle mainBundle].bundleIdentifier);

        if (APXIsOfficial()) {
            APXWatchPrefs();
            Class a = objc_getClass("NSUserActivity");
            APXHook(a, "setWebpageURL:", (IMP)APXHookedSetWebpageURL, &gSetWebpageURL);
            APXHook(a, "webpageURL",     (IMP)APXHookedWebpageURL,    &gWebpageURL);
        } else if (APXIsClone()) {
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *n) { APXOnActivate(); }];
            APXOnActivate();   /* 冷启动也走一次 */
        }
    }
}
