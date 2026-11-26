#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Load undocumented Control Strip symbols if they exist. Safe to call more than once.
void QBTouchBarPrivateLoad(void);

/// YES when the system-modal / Control Strip entry points are present.
BOOL QBTouchBarPrivateAvailable(void);

void QBSetControlStripPresence(NSTouchBarItemIdentifier identifier, BOOL present);
void QBSetSystemModalShowsCloseBoxWhenFrontMost(BOOL shows);
void QBAddSystemTrayItem(NSTouchBarItem *item);
void QBRemoveSystemTrayItem(NSTouchBarItem *item);

/// placement 0 presents a system-modal function row that can stay up across app switches.
BOOL QBPresentSystemModalTouchBar(NSTouchBar *touchBar, long long placement, NSTouchBarItemIdentifier trayIdentifier);
void QBDismissSystemModalTouchBar(NSTouchBar *touchBar);

NS_ASSUME_NONNULL_END
