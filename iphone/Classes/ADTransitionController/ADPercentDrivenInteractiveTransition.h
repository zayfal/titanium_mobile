#import <Foundation/Foundation.h>

@interface ADPercentDrivenInteractiveTransition : NSObject <UIViewControllerInteractiveTransitioning, UIViewControllerAnimatedTransitioning>

// This is the non-interactive duration that was returned when the
// animators transitionDuration: method was called when the transition started.
@property (readonly) CGFloat duration;

// The last percentComplete value specified by updateInteractiveTransition:
@property (readonly) CGFloat percentComplete;

@property (nonatomic, weak) id<UIViewControllerContextTransitioning> transitionContext;

// These methods should be called by the gesture recognizer or some other logic
// to drive the interaction. This style of interaction controller should only be
// used with an animator that implements a CA style transition in the animator's
// animateTransition: method. If this type of interaction controller is
// specified, the animateTransition: method must ensure to call the
// UIViewControllerTransitionParameters completeTransition: method. The other
// interactive methods on UIViewControllerContextTransitioning should NOT be
// called.

- (void)updateInteractiveTransition:(CGFloat)percentComplete __attribute__((objc_requires_super));
- (void)cancelInteractiveTransition __attribute__((objc_requires_super));
- (void)finishInteractiveTransition __attribute__((objc_requires_super));

- (void)animationEnded:(BOOL)transitionCompleted __attribute__((objc_requires_super));

@end
