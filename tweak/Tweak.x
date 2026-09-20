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
#import <os/lock.h>
#import "APXPrefs.h"

/* roothide / rootless 的 jbroot 解析：老版 Theos 没有 roothide.h，用 __has_include 兜底 */
#if __has_include(<roothide.h>)
#include <roothide.h>
#define APX_JBROOT(p) jbroot(p)
#else
#define APX_JBROOT(p) ([@"/var/jb" stringByAppendingPathComponent:(p)])
#endif

static inline NSString *APXJBP(NSString *path) {
    NSString *abs = [path hasPrefix:@"/"] ? path : [@"/" stringByAppendingString:path];
    return APX_JBROOT(abs);
}

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

/* ─────────────── 配置（支持热更新）─────────────── */

/*
 * 读配置。
 *
 * ── 为什么直接读 plist 文件，而不是 CFPreferencesCopyAppValue ──
 * CFPreferences 走 cfprefsd 的 XPC。在 App 早期初始化阶段调用时，
 * cfprefsd 可能正在等同一把锁，导致递归锁死并被 watchdog 杀掉。
 * 直接读文件是零 IPC 的，社区通用做法。
 *
 * 路径两条都试：真实路径 + jbroot 前缀（roothide / rootless）。
 */
/*
 * 读配置。
 *
 * 直接读 plist 文件，每次现读，不做缓存 —— 碰一碰是低频操作，文件读取极便宜，
 * 而缓存会让「改完设置立即生效」依赖通知链路，任何一环不可靠就退化成要重启。
 *
 * 为什么不调 CFPreferencesCopyAppValue：它走 cfprefsd 的 XPC，
 * 在 App 早期初始化阶段调用会与 cfprefsd 争同一把锁导致死锁（watchdog 杀进程）。
 *
 * 路径两条都试：真实路径 + jbroot 前缀（roothide / rootless）。
 */
static NSDictionary *APXAllPrefs(void) {
    static NSString *rel = nil;
    if (!rel) rel = [NSString stringWithFormat:@"var/mobile/Library/Preferences/%@.plist", APX_DOMAIN];

    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:
                       [@"/" stringByAppendingPathComponent:rel]];
    if (![p isKindOfClass:[NSDictionary class]])
        p = [NSDictionary dictionaryWithContentsOfFile:APXJBP(rel)];
    if (![p isKindOfClass:[NSDictionary class]]) p = @{};
    return p;
}

static BOOL APXPrefBool(NSString *key, BOOL dflt) {
    id v = APXAllPrefs()[key];
    return v ? [v boolValue] : dflt;
}

static NSString *APXPrefString(NSString *key) {
    id v = APXAllPrefs()[key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

/* ─────────────── 跳转前询问 ─────────────── */

static void APXForward(NSURL *u, NSString *clone);

static void APXAskUser(NSURL *u, NSString *clone) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *win = app.keyWindow;
        if (!win) {
            for (UIWindow *w in app.windows) { if (w.isKeyWindow) { win = w; break; } }
        }
        if (!win) { APXForward(u, clone); return; }   /* 没窗口就别问了，直接跳 */

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

/*
 * 处理一次碰一碰。
 * 返回 YES 表示已被我们接管 —— 调用方要把 URL 置空，官方就不会再处理它。
 *
 * 两种模式：
 *   直接跳转：接管，官方不进付款页，直接转给多开客户端
 *   跳转前询问：**不接管**，让官方正常进入付款页；等界面起来再弹窗。
 *              选「跳转」才转给多开客户端，选「用官方」就直接留在已经打开的付款页
 *              —— 这样"不跳转"也能正常付款。
 */
static BOOL APXTryHandle(NSURL *u) {
    if (!APXIsOfficial()) return NO;
    if (!APXPrefBool(APX_KEY_ENABLED, YES)) return NO;   /* 总开关：关掉就完全走官方 */
    if (!APXIsTapURL(u)) return NO;
    if (!APXShouldHandle(u)) return NO;

    NSString *clone = APXCloneBID();

    if (APXPrefBool(APX_KEY_ASK, NO)) {
        APXLog(@"询问模式：先让官方进付款页，稍后弹窗");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ APXAskUser(u, clone); });
        return NO;
    }

    APXForward(u, clone);
    return YES;
}

/* 入口 1：系统写入时 */
static void APXHookedSetWebpageURL(id self, SEL _cmd, NSURL *u) {
    BOOL taken = APXTryHandle(u);
    if (gSetWebpageURL) ((void (*)(id, SEL, NSURL *))gSetWebpageURL)(self, _cmd, taken ? nil : u);
}

/* 入口 2：App 读取时（冷启动走这条） */
static NSURL *APXHookedWebpageURL(id self, SEL _cmd) {
    NSURL *u = gWebpageURL ? ((NSURL *(*)(id, SEL))gWebpageURL)(self, _cmd) : nil;
    BOOL taken = APXTryHandle(u);
    return taken ? nil : u;
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
