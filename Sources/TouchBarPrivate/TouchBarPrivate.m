#import "TouchBarPrivate.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef void (*QBDFRPresenceFn)(NSTouchBarItemIdentifier, BOOL);
typedef void (*QBDFRCloseBoxFn)(BOOL);

static void *QBDFRHandle = NULL;
static QBDFRPresenceFn QBSetPresence = NULL;
static QBDFRCloseBoxFn QBSetCloseBox = NULL;
static BOOL QBLoaded = NO;

void QBTouchBarPrivateLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        QBDFRHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
        if (QBDFRHandle != NULL) {
            QBSetPresence = (QBDFRPresenceFn)dlsym(QBDFRHandle, "DFRElementSetControlStripPresenceForIdentifier");
            QBSetCloseBox = (QBDFRCloseBoxFn)dlsym(QBDFRHandle, "DFRSystemModalShowsCloseBoxWhenFrontMost");
        }
        Class touchBarClass = NSClassFromString(@"NSTouchBar");
        QBLoaded = (touchBarClass != Nil) && ([touchBarClass respondsToSelector:NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")]
            || [touchBarClass respondsToSelector:NSSelectorFromString(@"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:")]
            || [touchBarClass respondsToSelector:NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:")]);
    });
}

BOOL QBTouchBarPrivateAvailable(void) {
    QBTouchBarPrivateLoad();
    return QBLoaded;
}

void QBSetControlStripPresence(NSTouchBarItemIdentifier identifier, BOOL present) {
    QBTouchBarPrivateLoad();
    if (QBSetPresence != NULL && identifier != nil) {
        QBSetPresence(identifier, present);
    }
}

void QBSetSystemModalShowsCloseBoxWhenFrontMost(BOOL shows) {
    QBTouchBarPrivateLoad();
    if (QBSetCloseBox != NULL) {
        QBSetCloseBox(shows);
    }
}

void QBAddSystemTrayItem(NSTouchBarItem *item) {
    QBTouchBarPrivateLoad();
    Class itemClass = NSClassFromString(@"NSTouchBarItem");
    SEL selector = NSSelectorFromString(@"addSystemTrayItem:");
    if (itemClass != Nil && [itemClass respondsToSelector:selector]) {
        ((void (*)(Class, SEL, NSTouchBarItem *))objc_msgSend)(itemClass, selector, item);
    }
}

void QBRemoveSystemTrayItem(NSTouchBarItem *item) {
    QBTouchBarPrivateLoad();
    Class itemClass = NSClassFromString(@"NSTouchBarItem");
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    if (itemClass != Nil && [itemClass respondsToSelector:selector]) {
        ((void (*)(Class, SEL, NSTouchBarItem *))objc_msgSend)(itemClass, selector, item);
    }
}

BOOL QBPresentSystemModalTouchBar(NSTouchBar *touchBar, long long placement, NSTouchBarItemIdentifier trayIdentifier) {
    QBTouchBarPrivateLoad();
    if (touchBar == nil) {
        return NO;
    }
    Class touchBarClass = NSClassFromString(@"NSTouchBar");
    if (touchBarClass == Nil) {
        return NO;
    }

    SEL withPlacement = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    if ([touchBarClass respondsToSelector:withPlacement]) {
        ((void (*)(Class, SEL, NSTouchBar *, long long, NSTouchBarItemIdentifier))objc_msgSend)(touchBarClass, withPlacement, touchBar, placement, trayIdentifier);
        return YES;
    }

    SEL legacyPlacement = NSSelectorFromString(@"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:");
    if ([touchBarClass respondsToSelector:legacyPlacement]) {
        ((void (*)(Class, SEL, NSTouchBar *, long long, NSTouchBarItemIdentifier))objc_msgSend)(touchBarClass, legacyPlacement, touchBar, placement, trayIdentifier);
        return YES;
    }

    SEL withoutPlacement = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if ([touchBarClass respondsToSelector:withoutPlacement]) {
        ((void (*)(Class, SEL, NSTouchBar *, NSTouchBarItemIdentifier))objc_msgSend)(touchBarClass, withoutPlacement, touchBar, trayIdentifier);
        return YES;
    }

    SEL legacy = NSSelectorFromString(@"presentSystemModalFunctionBar:systemTrayItemIdentifier:");
    if ([touchBarClass respondsToSelector:legacy]) {
        ((void (*)(Class, SEL, NSTouchBar *, NSTouchBarItemIdentifier))objc_msgSend)(touchBarClass, legacy, touchBar, trayIdentifier);
        return YES;
    }

    return NO;
}

void QBDismissSystemModalTouchBar(NSTouchBar *touchBar) {
    QBTouchBarPrivateLoad();
    if (touchBar == nil) {
        return;
    }
    Class touchBarClass = NSClassFromString(@"NSTouchBar");
    SEL dismiss = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if (touchBarClass != Nil && [touchBarClass respondsToSelector:dismiss]) {
        ((void (*)(Class, SEL, NSTouchBar *))objc_msgSend)(touchBarClass, dismiss, touchBar);
        return;
    }
    SEL legacy = NSSelectorFromString(@"dismissSystemModalFunctionBar:");
    if (touchBarClass != Nil && [touchBarClass respondsToSelector:legacy]) {
        ((void (*)(Class, SEL, NSTouchBar *))objc_msgSend)(touchBarClass, legacy, touchBar);
    }
}
