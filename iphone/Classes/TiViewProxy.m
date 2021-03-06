/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2014 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiViewProxy.h"
#import "LayoutConstraint.h"
#import "TiApp.h"
#import "TiBlob.h"
#import "TiLayoutQueue.h"
#import "TiAction.h"
#import "TiStylesheet.h"
#import "TiLocale.h"
#import "TiUIView.h"
#import "TiTransition.h"
#import "TiApp.h"
#import "TiViewAnimation+Friend.h"
#import "TiViewAnimationStep.h"
#import "TiTransitionAnimation+Friend.h"
#import "TiTransitionAnimationStep.h"

#import <QuartzCore/QuartzCore.h>
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import "TiViewController.h"
#import "TiWindowProxy.h"


@interface TiFakeAnimation : TiViewAnimationStep

@end

@implementation TiFakeAnimation

@end

@interface TiViewProxy()
{
    BOOL needsContentChange;
    BOOL allowContentChange;
	unsigned int animationDelayGuard;
    BOOL _transitioning;
    id _pendingTransition;
}
@end

#define IGNORE_IF_NOT_OPENED if ([self viewAttached]==NO) {dirtyflags=0;return;}

@implementation TiViewProxy

@synthesize controller = controller;

static NSArray* layoutProps = nil;
static NSSet* transferableProps = nil;

#pragma mark public API

@synthesize vzIndex, parentVisible, preventListViewSelection;
-(void)setVzIndex:(int)newZindex
{
	if(newZindex == vzIndex)
	{
		return;
	}

	vzIndex = newZindex;
	[self replaceValue:NUMINT(vzIndex) forKey:@"vzIndex" notification:NO];
	[self willChangeZIndex];
}

-(NSString*)apiName
{
    return @"Ti.View";
}

-(void)runBlockOnMainThread:(void (^)(TiViewProxy* proxy))block onlyVisible:(BOOL)onlyVisible recursive:(BOOL)recursive
{
    if ([NSThread isMainThread])
	{
        [self runBlock:block onlyVisible:onlyVisible recursive:recursive];
    }
    else
    {
        TiThreadPerformOnMainThread(^{
            [self runBlock:block onlyVisible:onlyVisible recursive:recursive];
        }, NO);
    }
}

-(void)runBlock:(void (^)(TiViewProxy* proxy))block onlyVisible:(BOOL)onlyVisible recursive:(BOOL)recursive
{
    if (recursive)
    {
        pthread_rwlock_rdlock(&childrenLock);
        NSArray* subproxies = onlyVisible?[self visibleChildren]:[self viewChildren];
        for (TiViewProxy * thisChildProxy in subproxies)
        {
            block(thisChildProxy);
            [thisChildProxy runBlock:block onlyVisible:onlyVisible recursive:recursive];
        }
        pthread_rwlock_unlock(&childrenLock);
    }
//    block(self);
}

-(void)makeChildrenPerformSelector:(SEL)selector withObject:(id)object
{
    [[self viewChildren] makeObjectsPerformSelector:selector withObject:object];
}

-(void)makeVisibleChildrenPerformSelector:(SEL)selector withObject:(id)object
{
    [[self visibleChildren] makeObjectsPerformSelector:selector withObject:object];
}

-(void)setVisible:(NSNumber *)newVisible
{
	[self setHidden:![TiUtils boolValue:newVisible def:YES] withArgs:nil];
	[self replaceValue:newVisible forKey:@"visible" notification:YES];
}

-(void)setTempProperty:(id)propVal forKey:(id)propName {
    if (layoutPropDictionary == nil) {
        layoutPropDictionary = [[NSMutableDictionary alloc] init];
    }
    
    if (propVal != nil && propName != nil) {
        [layoutPropDictionary setObject:propVal forKey:propName];
    }
}

-(void)setProxyObserver:(id)arg
{
    observer = arg;
}

-(void)processTempProperties:(NSDictionary*)arg
{
    //arg will be non nil when called from updateLayout
    if (arg != nil) {
        NSEnumerator *enumerator = [arg keyEnumerator];
        id key;
        while ((key = [enumerator nextObject])) {
            [self setTempProperty:[arg objectForKey:key] forKey:key];
        }
    }
    
    if (layoutPropDictionary != nil) {
        [self setValuesForKeysWithDictionary:layoutPropDictionary];
        RELEASE_TO_NIL(layoutPropDictionary);
    }
}

-(void)applyProperties:(id)args
{
    ENSURE_UI_THREAD_1_ARG(args)
    [self configurationStart];
    [super applyProperties:args];
    [self configurationSet];
    [self refreshViewOrParent];
}

-(void)startLayout:(id)arg
{
    DebugLog(@"startLayout() method is deprecated since 3.0.0 .");
    updateStarted = YES;
    allowLayoutUpdate = NO;
}
-(void)finishLayout:(id)arg
{
    DebugLog(@"finishLayout() method is deprecated since 3.0.0 .");
    updateStarted = NO;
    allowLayoutUpdate = YES;
    [self processTempProperties:nil];
    allowLayoutUpdate = NO;
}
-(void)updateLayout:(id)arg
{
    DebugLog(@"updateLayout() method is deprecated since 3.0.0, use applyProperties() instead.");
    id val = nil;
    if ([arg isKindOfClass:[NSArray class]]) {
        val = [arg objectAtIndex:0];
    }
    else
    {
        val = arg;
    }
    updateStarted = NO;
    allowLayoutUpdate = YES;
    ENSURE_TYPE_OR_NIL(val, NSDictionary);
    [self processTempProperties:val];
    allowLayoutUpdate = NO;
    
}

-(BOOL) belongsToContext:(id<TiEvaluator>) context
{
    id<TiEvaluator> myContext = ([self executionContext]==nil)?[self pageContext]:[self executionContext];
    return (context == myContext);
}

-(void)show:(id)arg
{
	TiThreadPerformOnMainThread(^{
        [self setHidden:NO withArgs:arg];
        [self replaceValue:NUMBOOL(YES) forKey:@"visible" notification:YES];
    }, NO);
}
 
-(void)hide:(id)arg
{
    TiThreadPerformOnMainThread(^{
        [self setHidden:YES withArgs:arg];
        [self replaceValue:NUMBOOL(NO) forKey:@"visible" notification:YES];
    }, NO);
}

#pragma Animations

-(id)animationDelegate
{
    if (parent)
        return [[self viewParent] animationDelegate];
    return nil;
}

-(void)handlePendingAnimation
{
    if (![self viewInitialized] || !allowContentChange)return;
    [super handlePendingAnimation];
}

-(void)handlePendingAnimation:(TiAnimation*)pendingAnimation
{
    if ([self viewReady]==NO &&  ![pendingAnimation isTransitionAnimation])
	{
		DebugLog(@"[DEBUG] Ti.UI.View.animate() called before view %@ was ready: Will re-attempt", self);
		if (animationDelayGuard++ > 5)
		{
			DebugLog(@"[DEBUG] Animation guard triggered, exceeded timeout to perform animation.");
            [pendingAnimation simulateFinish:self];
            [self handlePendingAnimation];
            animationDelayGuard = 0;
			return;
		}
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performSelector:@selector(handlePendingAnimation:) withObject:pendingAnimation afterDelay:0.01];
        });
		return;
	}
	animationDelayGuard = 0;
    [super handlePendingAnimation:pendingAnimation];
}

-(void)aboutToBeAnimated
{
    if ([view superview]==nil)
    {
        VerboseLog(@"Entering animation without a superview Parent is %@, props are %@",parent,dynprops);
        [self windowWillOpen]; // we need to manually attach the window if you're animating
        [[self viewParent] childWillResize:self];
    }
    
}

-(HLSAnimation*)animationForAnimation:(TiAnimation*)animation
{
    TiHLSAnimationStep* step;
    if (animation.isTransitionAnimation) {
        TiTransitionAnimation * hlsAnimation = [TiTransitionAnimation animation];
        hlsAnimation.animatedProxy = self;
        hlsAnimation.animationProxy = animation;
        hlsAnimation.transition = animation.transition;
        hlsAnimation.transitionViewProxy = animation.view;
        step = [TiTransitionAnimationStep animationStep];
        step.duration = [animation getAnimationDuration];
        step.curve = [animation curve];
        [(TiTransitionAnimationStep*)step addTransitionAnimation:hlsAnimation insideHolder:[self getOrCreateView]];
    }
    else {
        TiViewAnimation * hlsAnimation = [TiViewAnimation animation];
        hlsAnimation.animatedProxy = self;
        hlsAnimation.tiViewProxy = self;
        hlsAnimation.animationProxy = animation;
        step = [TiViewAnimationStep animationStep];
        step.duration = [animation getAnimationDuration];
        step.curve = [animation curve];
       [(TiViewAnimationStep*)step addViewAnimation:hlsAnimation forView:self.view];
    }
    
    return [HLSAnimation animationWithAnimationStep:step];
}

-(void)playAnimation:(HLSAnimation*)animation withRepeatCount:(NSUInteger)repeatCount afterDelay:(double)delay
{
    TiThreadPerformOnMainThread(^{
        [self aboutToBeAnimated];
        [animation playWithRepeatCount:repeatCount afterDelay:delay];
	}, YES);
}

//override
-(void)animationDidComplete:(TiAnimation *)animation
{
	OSAtomicTestAndClearBarrier(TiRefreshViewEnqueued, &dirtyflags);
	[self willEnqueue];
    [super animationDidComplete:animation];
}

-(void)resetProxyPropertiesForAnimation:(TiAnimation*)animation
{
    TiThreadPerformOnMainThread(^{
        [super resetProxyPropertiesForAnimation:animation];
		[[self viewParent] layoutChildren:NO];
    }, YES);
}

#define CHECK_LAYOUT_UPDATE(layoutName,value) \
if (ENFORCE_BATCH_UPDATE) { \
    if (updateStarted) { \
        [self setTempProperty:value forKey:@#layoutName]; \
        return; \
    } \
    else if(!allowLayoutUpdate){ \
        return; \
    } \
}

#define LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(methodName,layoutName,converter,postaction)	\
-(void)methodName:(id)value	\
{	\
    CHECK_LAYOUT_UPDATE(layoutName,value) \
    TiDimension result = converter(value);\
    if ( TiDimensionIsDip(result) || TiDimensionIsPercent(result) ) {\
        layoutProperties.layoutName = result;\
    }\
    else {\
        if (!TiDimensionIsUndefined(result)) {\
            DebugLog(@"[WARN] Invalid value %@ specified for property %@",[TiUtils stringValue:value],@#layoutName); \
        } \
        layoutProperties.layoutName = TiDimensionUndefined;\
    }\
    [self replaceValue:value forKey:@#layoutName notification:YES];	\
    postaction; \
}

#define LAYOUTPROPERTIES_SETTER(methodName,layoutName,converter,postaction)	\
-(void)methodName:(id)value	\
{	\
    CHECK_LAYOUT_UPDATE(layoutName,value) \
    layoutProperties.layoutName = converter(value);	\
    [self replaceValue:value forKey:@#layoutName notification:YES];	\
    postaction; \
}

#define LAYOUTFLAGS_SETTER(methodName,layoutName,flagName,postaction)	\
-(void)methodName:(id)value	\
{	\
	CHECK_LAYOUT_UPDATE(layoutName,value) \
	layoutProperties.layoutFlags.flagName = [TiUtils boolValue:value];	\
	[self replaceValue:value forKey:@#layoutName notification:NO];	\
	postaction; \
}

LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setTop,top,TiDimensionFromObject,[self willChangePosition])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setBottom,bottom,TiDimensionFromObject,[self willChangePosition])

LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setLeft,left,TiDimensionFromObject,[self willChangePosition])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setRight,right,TiDimensionFromObject,[self willChangePosition])

LAYOUTPROPERTIES_SETTER(setWidth,width,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER(setHeight,height,TiDimensionFromObject,[self willChangeSize])

-(void)setFullscreen:(id)value
{
    CHECK_LAYOUT_UPDATE(layoutName,value)
    layoutProperties.fullscreen = [TiUtils boolValue:value def:NO];
    [self replaceValue:value forKey:@"fullscreen" notification:YES];
    [self willChangeSize];
    [self willChangePosition];
}

-(id)getFullscreen
{
    return NUMBOOL(layoutProperties.fullscreen);
}

+(NSArray*)layoutProperties
{
    if (layoutProps == nil) {
        layoutProps = [[NSArray alloc] initWithObjects:@"left", @"right", @"top", @"bottom", @"width", @"height", @"fullscreen", @"minWidth", @"minHeight", @"maxWidth", @"maxHeight", nil];
    }
    return layoutProps;
}

+(NSSet*)transferableProperties
{
    if (transferableProps == nil) {
        transferableProps = [[NSSet alloc] initWithObjects:@"imageCap",@"visible", @"backgroundImage", @"backgroundGradient", @"backgroundColor", @"backgroundSelectedImage", @"backgroundSelectedGradient", @"backgroundSelectedColor", @"backgroundDisabledImage", @"backgroundDisabledGradient", @"backgroundDisabledColor", @"backgroundRepeat",@"focusable", @"touchEnabled", @"viewShadow", @"viewMask", @"accessibilityLabel", @"accessibilityValue", @"accessibilityHint", @"accessibilityHidden",
            @"opacity", @"borderWidth", @"borderColor", @"borderRadius", @"tileBackground",
            @"transform", @"center", @"anchorPoint", @"clipChildren", @"touchPassThrough", @"transform", nil];
    }
    return transferableProps;
}

-(NSArray *)keySequence
{
	static NSArray *keySequence = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		keySequence = [@[@"visible", @"clipChildren"] retain];
	});
	return keySequence;
}

// See below for how we handle setLayout
//LAYOUTPROPERTIES_SETTER(setLayout,layoutStyle,TiLayoutRuleFromObject,[self willChangeLayout])

LAYOUTPROPERTIES_SETTER(setMinWidth,minimumWidth,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER(setMinHeight,minimumHeight,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER(setMaxWidth,maximumWidth,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER(setMaxHeight,maximumHeight,TiDimensionFromObject,[self willChangeSize])

LAYOUTFLAGS_SETTER(setHorizontalWrap,horizontalWrap,horizontalWrap,[self willChangeLayout])

// Special handling to try and avoid Apple's detection of private API 'layout'
-(void)setValue:(id)value forUndefinedKey:(NSString *)key
{
    if ([key isEqualToString:[@"lay" stringByAppendingString:@"out"]]) {
        //CAN NOT USE THE MACRO 
        if (ENFORCE_BATCH_UPDATE) {
            if (updateStarted) {
                [self setTempProperty:value forKey:key]; \
                return;
            }
            else if(!allowLayoutUpdate){
                return;
            }
        }
        layoutProperties.layoutStyle = TiLayoutRuleFromObject(value);
        [self replaceValue:value forKey:[@"lay" stringByAppendingString:@"out"] notification:YES];
        
        [self willChangeLayout];
        return;
    }
    [super setValue:value forUndefinedKey:key];
}


NSString * GetterStringForKrollProperty(NSString * key)
{
    return [NSString stringWithFormat:@"%@_", key];
}

SEL GetterForKrollProperty(NSString * key)
{
	NSString *method = GetterStringForKrollProperty(key);
	return NSSelectorFromString(method);
}

- (id) valueForKey: (NSString *) key
{
    SEL sel = GetterForKrollProperty(key);
	if ([view respondsToSelector:sel])
	{
		return [view performSelector:sel];
	}
    return [super valueForKey:key];
}

-(TiRect*)size
{
	TiRect *rect = [[TiRect alloc] init];
    if ([self viewAttached]) {
        [self makeViewPerformSelector:@selector(fillBoundsToRect:) withObject:rect createIfNeeded:YES waitUntilDone:YES];
        id defaultUnit = [TiApp defaultUnit];
        if ([defaultUnit isKindOfClass:[NSString class]]) {
            [rect convertToUnit:defaultUnit];
        }
    }
    else {
        [rect setRect:CGRectZero];
    }
    
    return [rect autorelease];
}

-(id)rect
{
    TiRect *rect = [[TiRect alloc] init];
	if ([self viewAttached]) {
        __block CGRect viewRect;
        __block CGPoint viewPosition;
        __block CGAffineTransform viewTransform;
        __block CGPoint viewAnchor;
        TiThreadPerformOnMainThread(^{
            TiUIView * ourView = [self view];
            viewRect = [ourView bounds];
            viewPosition = [ourView center];
            viewTransform = [ourView transform];
            viewAnchor = [[ourView layer] anchorPoint];
        }, YES);
        viewRect.origin = CGPointMake(-viewAnchor.x*viewRect.size.width, -viewAnchor.y*viewRect.size.height);
        viewRect = CGRectApplyAffineTransform(viewRect, viewTransform);
        viewRect.origin.x += viewPosition.x;
        viewRect.origin.y += viewPosition.y;
        [rect setRect:viewRect];
        
        id defaultUnit = [TiApp defaultUnit];
        if ([defaultUnit isKindOfClass:[NSString class]]) {
            [rect convertToUnit:defaultUnit];
        }       
    }
    else {
        [rect setRect:CGRectZero];
    }
    NSDictionary* result = [rect toJSON];
    [rect release];
    return result;
}

-(id)absoluteRect
{
    TiRect *rect = [[TiRect alloc] init];
	if ([self viewAttached]) {
        __block CGRect viewRect;
        __block CGPoint viewPosition;
        __block CGAffineTransform viewTransform;
        __block CGPoint viewAnchor;
        TiThreadPerformOnMainThread(^{
            TiUIView * ourView = [self view];
            viewRect = [ourView bounds];
            viewPosition = [ourView center];
            viewTransform = [ourView transform];
            viewAnchor = [[ourView layer] anchorPoint];
            viewRect.origin = CGPointMake(-viewAnchor.x*viewRect.size.width, -viewAnchor.y*viewRect.size.height);
            viewRect = CGRectApplyAffineTransform(viewRect, viewTransform);
            viewRect.origin.x += viewPosition.x;
            viewRect.origin.y += viewPosition.y;
            viewRect.origin = [ourView convertPoint:CGPointZero toView:nil];
            if (![[UIApplication sharedApplication] isStatusBarHidden])
            {
                CGRect statusFrame = [[UIApplication sharedApplication] statusBarFrame];
                viewRect.origin.y -= statusFrame.size.height;
            }
            
        }, YES);
        [rect setRect:viewRect];
        
        id defaultUnit = [TiApp defaultUnit];
        if ([defaultUnit isKindOfClass:[NSString class]]) {
            [rect convertToUnit:defaultUnit];
        }
    }
    else {
        [rect setRect:CGRectZero];
    }
    NSDictionary* result = [rect toJSON];
    [rect release];
    return result;
}

-(id)zIndex
{
    return [self valueForUndefinedKey:@"zindex_"];
}

-(void)setZIndex:(id)value
{
    CHECK_LAYOUT_UPDATE(zIndex, value);
    
    if ([value respondsToSelector:@selector(intValue)]) {
        [self setVzIndex:[TiUtils intValue:value]];
        [self replaceValue:value forKey:@"zindex_" notification:NO];
    }
}

-(NSMutableDictionary*)center
{
    NSMutableDictionary* result = [[[NSMutableDictionary alloc] init] autorelease];
    id xVal = [self valueForUndefinedKey:@"centerX_"];
    if (xVal != nil) {
        [result setObject:xVal forKey:@"x"];
    }
    id yVal = [self valueForUndefinedKey:@"centerY_"];
    if (yVal != nil) {
        [result setObject:yVal forKey:@"y"];
    }
    
    if ([[result allKeys] count] > 0) {
        return result;
    }
    return nil;
}

-(void)setCenter:(id)value
{
    CHECK_LAYOUT_UPDATE(center, value);

    
	if ([value isKindOfClass:[NSDictionary class]])
	{
        TiDimension result;
        id obj = [value objectForKey:@"x"];
        if (obj != nil) {
            [self replaceValue:obj forKey:@"centerX_" notification:NO];
            result = TiDimensionFromObject(obj);
            if ( TiDimensionIsDip(result) || TiDimensionIsPercent(result) ) {
                layoutProperties.centerX = result;
            }
            else {
                layoutProperties.centerX = TiDimensionUndefined;
            }
        }
        obj = [value objectForKey:@"y"];
        if (obj != nil) {
            [self replaceValue:obj forKey:@"centerY_" notification:NO];
            result = TiDimensionFromObject(obj);
            if ( TiDimensionIsDip(result) || TiDimensionIsPercent(result) ) {
                layoutProperties.centerY = result;
            }
            else {
                layoutProperties.centerY = TiDimensionUndefined;
            }
        }
        
        

	} else if ([value isKindOfClass:[TiPoint class]]) {
        CGPoint p = [value point];
		layoutProperties.centerX = TiDimensionDip(p.x);
		layoutProperties.centerY = TiDimensionDip(p.y);
    } else {
		layoutProperties.centerX = TiDimensionUndefined;
		layoutProperties.centerY = TiDimensionUndefined;
	}

	[self willChangePosition];
}

-(id)animatedCenter
{
	if (![self viewAttached])
	{
		return nil;
	}
	__block CGPoint result;
	TiThreadPerformOnMainThread(^{
		UIView * ourView = view;
		CALayer * ourLayer = [ourView layer];
		CALayer * animatedLayer = [ourLayer presentationLayer];
	
		if (animatedLayer !=nil) {
			result = [animatedLayer position];
		}
		else {
			result = [ourLayer position];
		}
	}, YES);
	//TODO: Should this be a TiPoint? If so, the accessor fetcher might try to
	//hold onto the point, which is undesired.
	return [NSDictionary dictionaryWithObjectsAndKeys:NUMFLOAT(result.x),@"x",NUMFLOAT(result.y),@"y", nil];
}

-(void)setBackgroundGradient:(id)arg
{
	TiGradient * newGradient = [TiGradient gradientFromObject:arg proxy:self];
	[self replaceValue:newGradient forKey:@"backgroundGradient" notification:YES];
}

-(UIImage*)toImageWithScale:(CGFloat)scale
{
    TiUIView *myview = [self getOrCreateView];
    [self windowWillOpen];
    CGSize size = myview.bounds.size;
   
    if (CGSizeEqualToSize(size, CGSizeZero) || size.width==0 || size.height==0)
    {
        CGSize size = [self autoSizeForSize:CGSizeMake(1000,1000)];
        if (size.width==0 || size.height == 0)
        {
            size = [UIScreen mainScreen].bounds.size;
        }
        CGRect rect = CGRectMake(0, 0, size.width, size.height);
        [TiUtils setView:myview positionRect:rect];
    }
    if ([TiUtils isRetinaDisplay])
    {
        scale*=2;
        
    }
    UIGraphicsBeginImageContextWithOptions(size, [myview.layer isOpaque], scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    float oldOpacity = myview.alpha;
    myview.alpha = 1;
    [myview.layer renderInContext:context];
    myview.alpha = oldOpacity;
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

-(TiBlob*)toImage:(id)args
{
    KrollCallback *callback = nil;
    float scale = 1.0f;
    
    id obj = nil;
    if( [args count] > 0) {
        obj = [args objectAtIndex:0];
        
        if (obj == [NSNull null]) {
            obj = nil;
        }
        
        if( [args count] > 1) {
            scale = [TiUtils floatValue:[args objectAtIndex:1] def:1.0f];
        }
    }
	ENSURE_SINGLE_ARG_OR_NIL(obj,KrollCallback);
    callback = (KrollCallback*)obj;
	TiBlob *blob = [[[TiBlob alloc] init] autorelease];
	// we spin on the UI thread and have him convert and then add back to the blob
	// if you pass a callback function, we'll run the render asynchronously, if you
	// don't, we'll do it synchronously
	TiThreadPerformOnMainThread(^{
		UIImage *image = [self toImageWithScale:scale];
		[blob setImage:image];
        [blob setMimeType:@"image/png" type:TiBlobTypeImage];
		if (callback != nil)
		{
            NSDictionary *event = [NSDictionary dictionaryWithObject:blob forKey:@"image"];
            [self _fireEventToListener:@"toimage" withObject:event listener:callback thisObject:nil];
		}
	}, (callback==nil));
	
	return blob;
}

-(TiPoint*)convertPointToView:(id)args
{
    id arg1 = nil;
    TiViewProxy* arg2 = nil;
    ENSURE_ARG_AT_INDEX(arg1, args, 0, NSObject);
    ENSURE_ARG_AT_INDEX(arg2, args, 1, TiViewProxy);
    BOOL validPoint;
    CGPoint oldPoint = [TiUtils pointValue:arg1 valid:&validPoint];
    if (!validPoint) {
        [self throwException:TiExceptionInvalidType subreason:@"Parameter is not convertable to a TiPoint" location:CODELOCATION];
    }
    
    __block BOOL validView = NO;
    __block CGPoint p;
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ([self viewAttached] && self.view.window && [arg2 viewAttached] && arg2.view.window) {
            validView = YES;
            p = [self.view convertPoint:oldPoint toView:arg2.view];
        }
    });
    if (!validView) {
        return (TiPoint*)[NSNull null];
    }
    return [[[TiPoint alloc] initWithPoint:p] autorelease];
}


#pragma mark parenting

-(void)childAdded:(TiProxy*)child atIndex:(NSInteger)position shouldRelayout:(BOOL)shouldRelayout
{
    if (![child isKindOfClass:[TiViewProxy class]]){
        return;
    }
    TiViewProxy* childViewProxy = (TiViewProxy*)child;
    if ([NSThread isMainThread])
	{
        if (readyToCreateView)
            [childViewProxy setReadyToCreateView:YES]; //tableview magic not to create view on proxy creation
		
        
        if (!readyToCreateView || [childViewProxy isHidden]) return;
        [childViewProxy performBlockWithoutLayout:^{
            [childViewProxy getOrCreateView];
        }];
        if (!shouldRelayout) return;
        
        [self contentsWillChange];
        if(parentVisible && !hidden)
        {
            [childViewProxy parentWillShow];
        }
        
        //If layout is non absolute push this into the layout queue
        //else just layout the child with current bounds
        if (![self absoluteLayout]) {
            [self contentsWillChange];
        }
        else {
            [self layoutChild:childViewProxy optimize:NO withMeasuredBounds:[[self view] bounds]];
        }
    }
    else if (windowOpened && shouldRelayout) {
        TiThreadPerformOnMainThread(^{[self childAdded:child atIndex:position shouldRelayout:shouldRelayout];}, NO);
        return;
    }
}

-(void)childRemoved:(TiProxy*)child
{
    if (![child isKindOfClass:[TiViewProxy class]]){
        return;
    }
    ENSURE_UI_THREAD_1_ARG(child);
    TiViewProxy* childViewProxy = (TiViewProxy*)child;

    [childViewProxy windowWillClose];
    [childViewProxy setParentVisible:NO];
    [childViewProxy windowDidClose]; //will call detach view
    BOOL layoutNeedsRearranging = ![self absoluteLayout];
    if (layoutNeedsRearranging)
    {
        [self willChangeLayout];
    }
    
}

-(void)removeAllChildren:(id)arg
{
    ENSURE_UI_THREAD_1_ARG(arg);
    [self performBlockWithoutLayout:^{
        [super removeAllChildren:arg];
        [self refreshViewIfNeeded];
    }];
}

-(void)setParent:(TiParentingProxy*)parent_ checkForOpen:(BOOL)check
{
    [super setParent:parent_];
	
	if (check && parent!=nil && ([parent isKindOfClass:[TiViewProxy class]]) && [[self viewParent] windowHasOpened])
	{
		[self windowWillOpen];
	}
}

-(void)setParent:(TiParentingProxy*)parent_
{
	[super setParent:parent_];
	
	if (parent!=nil && ([parent isKindOfClass:[TiViewProxy class]]) && [[self viewParent] windowHasOpened])
	{
		[self windowWillOpen];
	}
}


-(TiViewProxy*)viewParent
{
    return (TiViewProxy*)parent;
}

-(NSArray*)viewChildren
{
    if (childrenCount == 0) return nil;
//    if (![NSThread isMainThread]) {
//        __block NSArray* result = nil;
//        TiThreadPerformOnMainThread(^{
//            result = [[self viewChildren] retain];
//        }, YES);
//        return [result autorelease];
//    }
//    
	pthread_rwlock_rdlock(&childrenLock);
    NSArray* copy = [[children filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object isKindOfClass:[TiViewProxy class]];
    }]] retain];
	pthread_rwlock_unlock(&childrenLock);
	return [copy autorelease];
}

-(NSArray*)visibleChildren
{
    if (childrenCount == 0) return nil;
//    if (![NSThread isMainThread]) {
//        __block NSArray* result = nil;
//        TiThreadPerformOnMainThread(^{
//            result = [[self visibleChildren] retain];
//        }, YES);
//        return [result autorelease];
//    }
	pthread_rwlock_rdlock(&childrenLock);
    NSArray* copy = [[children filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object isKindOfClass:[TiViewProxy class]] && ((TiViewProxy*)object).isHidden == FALSE;
    }]] retain];
    pthread_rwlock_unlock(&childrenLock);
	return [copy autorelease];
}


#pragma mark nonpublic accessors not related to Housecleaning

@synthesize barButtonItem;

-(LayoutConstraint *)layoutProperties
{
	return &layoutProperties;
}

@synthesize sandboxBounds = sandboxBounds;

-(void)setSandboxBounds:(CGRect)rect
{
    if (!CGRectEqualToRect(rect, sandboxBounds))
    {
        sandboxBounds = rect;
//        [self dirtyItAll];
    }
}

-(void)setHidden:(BOOL)newHidden withArgs:(id)args
{
	hidden = newHidden;
}

-(BOOL)isHidden
{
    return hidden;
}

//-(CGSize)contentSizeForSize:(CGSize)size
//{
//    return CGSizeZero;
//}

-(CGSize)verifySize:(CGSize)size
{
    CGSize result = size;
    if([self respondsToSelector:@selector(verifyWidth:)])
	{
		result.width = [self verifyWidth:result.width];
	}
    if([self respondsToSelector:@selector(verifyHeight:)])
	{
		result.height = [self verifyHeight:result.height];
	}

    return result;
}

-(CGSize)autoSizeForSize:(CGSize)size
{
    CGSize contentSize = CGSizeMake(-1, -1);
    if ([self respondsToSelector:@selector(contentSizeForSize:)]) {
        contentSize = [self contentSizeForSize:size];
    }
    BOOL isAbsolute = [self absoluteLayout];
    CGSize result = CGSizeZero;
    
    CGRect bounds = CGRectZero;
    if (!isAbsolute) {
        bounds.size.width = size.width;
        bounds.size.height = size.height;
        verticalLayoutBoundary = 0;
        horizontalLayoutBoundary = 0;
        horizontalLayoutRowHeight = 0;
    }
	CGRect sandBox = CGRectZero;
    CGSize thisSize = CGSizeZero;
    
    if (childrenCount > 0)
    {
        NSArray* childArray = [self visibleChildren];
        if (isAbsolute)
        {
            for (TiViewProxy* thisChildProxy in childArray)
            {
                thisSize = [thisChildProxy minimumParentSizeForSize:size];
                if(result.width<thisSize.width)
                {
                    result.width = thisSize.width;
                }
                if(result.height<thisSize.height)
                {
                    result.height = thisSize.height;
                }
            }
        }
        else {
            BOOL horizontal =  TiLayoutRuleIsHorizontal(layoutProperties.layoutStyle);
            BOOL vertical =  TiLayoutRuleIsVertical(layoutProperties.layoutStyle);
//            BOOL horizontalNoWrap = horizontal && !TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
            BOOL horizontalWrap = horizontal && TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
            
            NSMutableArray * widthFillChildren = horizontal?[NSMutableArray array]:nil;
            NSMutableArray * heightFillChildren = (vertical || horizontalWrap)?[NSMutableArray array]:nil;
            CGFloat widthNonFill = 0;
            CGFloat heightNonFill = 0;
            
            //First measure the sandbox bounds
            for (TiViewProxy* thisChildProxy in childArray)
            {
                BOOL horizontalFill = [thisChildProxy wantsToFillHorizontalLayout];
                BOOL verticalFill = [thisChildProxy wantsToFillVerticalLayout];
                if (!horizontalWrap)
                {
                    if (widthFillChildren && horizontalFill)
                    {
                        [widthFillChildren addObject:thisChildProxy];
                        continue;
                    }
                    else if (heightFillChildren && verticalFill)
                    {
                        [heightFillChildren addObject:thisChildProxy];
                        continue;
                    }
                }
                sandBox = [self computeChildSandbox:thisChildProxy withBounds:bounds];
                thisSize = CGSizeMake(sandBox.origin.x + sandBox.size.width, sandBox.origin.y + sandBox.size.height);
                if(result.width<thisSize.width)
                {
                    result.width = thisSize.width;
                }
                if(result.height<thisSize.height)
                {
                    result.height = thisSize.height;
                }
            }
            
            int nbWidthAutoFill = [widthFillChildren count];
            if (nbWidthAutoFill > 0) {
                CGFloat usableWidth = floorf((size.width - result.width) / nbWidthAutoFill);
                CGRect usableRect = CGRectMake(0,0,usableWidth, size.height);
                for (TiViewProxy* thisChildProxy in widthFillChildren) {
                    sandBox = [self computeChildSandbox:thisChildProxy withBounds:usableRect];
                    thisSize = CGSizeMake(sandBox.origin.x + sandBox.size.width, sandBox.origin.y + sandBox.size.height);
                    if(result.width<thisSize.width)
                    {
                        result.width = thisSize.width;
                    }
                    if(result.height<thisSize.height)
                    {
                        result.height = thisSize.height;
                    }
                }
            }
            
            int nbHeightAutoFill = [heightFillChildren count];
            if (nbHeightAutoFill > 0) {
                CGFloat usableHeight = floorf((size.height - result.height) / nbHeightAutoFill);
                CGRect usableRect = CGRectMake(0,0,size.width, usableHeight);
                for (TiViewProxy* thisChildProxy in heightFillChildren) {
                    sandBox = [self computeChildSandbox:thisChildProxy withBounds:usableRect];
                    thisSize = CGSizeMake(sandBox.origin.x + sandBox.size.width, sandBox.origin.y + sandBox.size.height);
                    if(result.width<thisSize.width)
                    {
                        result.width = thisSize.width;
                    }
                    if(result.height<thisSize.height)
                    {
                        result.height = thisSize.height;
                    }
                }
            }
        }
    }
	
    if (result.width < contentSize.width) {
        result.width = contentSize.width;
    }
    if (result.height < contentSize.height) {
        result.height = contentSize.height;
    }
    result = minmaxSize(&layoutProperties, result, size);

	return [self verifySize:result];
}

-(CGSize)sizeForAutoSize:(CGSize)size
{
    if (layoutProperties.fullscreen == YES) return size;
    
    CGFloat suggestedWidth = size.width;
    BOOL followsFillHBehavior = TiDimensionIsAutoFill([self defaultAutoWidthBehavior:nil]);
    CGFloat suggestedHeight = size.height;
    BOOL followsFillWBehavior = TiDimensionIsAutoFill([self defaultAutoHeightBehavior:nil]);
    
    CGFloat offsetx = TiDimensionCalculateValue(layoutProperties.left, size.width)
    + TiDimensionCalculateValue(layoutProperties.right, size.width);
    
    CGFloat offsety = TiDimensionCalculateValue(layoutProperties.top, size.height)
    + TiDimensionCalculateValue(layoutProperties.bottom, size.height);
    
    CGSize result = CGSizeZero;
    
    if (TiDimensionIsDip(layoutProperties.width) || TiDimensionIsPercent(layoutProperties.width))
    {
        result.width =  TiDimensionCalculateValue(layoutProperties.width, suggestedWidth);
    }
    else if (TiDimensionIsAutoFill(layoutProperties.width) || (TiDimensionIsAuto(layoutProperties.width) && followsFillWBehavior) )
    {
        result.width = size.width;
        result.width -= offsetx;
    }
    else if (TiDimensionIsUndefined(layoutProperties.width))
    {
        if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.centerX) ) {
            result.width = 2 * ( TiDimensionCalculateValue(layoutProperties.centerX, suggestedWidth) - TiDimensionCalculateValue(layoutProperties.left, suggestedWidth) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width = TiDimensionCalculateMargins(layoutProperties.left, layoutProperties.right, suggestedWidth);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerX) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width = 2 * ( size.width - TiDimensionCalculateValue(layoutProperties.right, suggestedWidth) - TiDimensionCalculateValue(layoutProperties.centerX, suggestedWidth));
        }
        else {
            result.width = size.width;
            result.width -= offsetx;
        }
    }
    else
    {
        result.width = size.width;
        result.width -= offsetx;
    }
    
    if (TiDimensionIsDip(layoutProperties.height) || TiDimensionIsPercent(layoutProperties.height))        {
        result.height = TiDimensionCalculateValue(layoutProperties.height, suggestedHeight);
    }
    else if (TiDimensionIsAutoFill(layoutProperties.height) || (TiDimensionIsAuto(layoutProperties.height) && followsFillHBehavior) )
    {
        result.height = size.height;
        result.height -= offsety;
    }
    else if (TiDimensionIsUndefined(layoutProperties.height))
    {
        if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.centerY) ) {
            result.height = 2 * ( TiDimensionCalculateValue(layoutProperties.centerY, suggestedHeight) - TiDimensionCalculateValue(layoutProperties.top, suggestedHeight) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height = TiDimensionCalculateMargins(layoutProperties.top, layoutProperties.bottom, suggestedHeight);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerY) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height = 2 * ( suggestedHeight - TiDimensionCalculateValue(layoutProperties.bottom, suggestedHeight) - TiDimensionCalculateValue(layoutProperties.centerY, suggestedHeight));
        }
        else {
            result.height = size.height;
            result.height -= offsety;
        }
    }
    else {
        result.height -= offsety;
    }
    result = minmaxSize(&layoutProperties, result, size);
    return result;
}

-(CGSize)minimumParentSizeForSize:(CGSize)size
{
    if (layoutProperties.fullscreen == YES) return size;
    
    CGSize suggestedSize = size;
    BOOL followsFillWidthBehavior = TiDimensionIsAutoFill([self defaultAutoWidthBehavior:nil]);
    BOOL followsFillHeightBehavior = TiDimensionIsAutoFill([self defaultAutoHeightBehavior:nil]);
    BOOL recheckForFillW = NO, recheckForFillH = NO;
    
    BOOL autoComputed = NO;
    CGSize autoSize = [self sizeForAutoSize:size];
    //    //Ensure that autoHeightForSize is called with the lowest limiting bound
    //    CGFloat desiredWidth = MIN([self minimumParentWidthForSize:size],size.width);
    
    CGFloat offsetx = TiDimensionCalculateValue(layoutProperties.left, suggestedSize.width)
    + TiDimensionCalculateValue(layoutProperties.right, suggestedSize.width);
    
    CGFloat offsety = TiDimensionCalculateValue(layoutProperties.top, suggestedSize.height)
    + TiDimensionCalculateValue(layoutProperties.bottom, suggestedSize.height);
    
    CGSize result = CGSizeMake(offsetx, offsety);

	if (TiDimensionIsDip(layoutProperties.width) || TiDimensionIsPercent(layoutProperties.width))
	{
		result.width += TiDimensionCalculateValue(layoutProperties.width, suggestedSize.width);
	}
	else if (TiDimensionIsAutoFill(layoutProperties.width) || (TiDimensionIsAuto(layoutProperties.width) && followsFillWidthBehavior) )
	{
		result.width = suggestedSize.width;
	}
    else if (followsFillWidthBehavior && TiDimensionIsUndefined(layoutProperties.width))
    {
        if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.centerX) ) {
            result.width += 2 * ( TiDimensionCalculateValue(layoutProperties.centerX, suggestedSize.width) - TiDimensionCalculateValue(layoutProperties.left, suggestedSize.width) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width += TiDimensionCalculateMargins(layoutProperties.left, layoutProperties.right, suggestedSize.width);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerX) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width += 2 * ( size.width - TiDimensionCalculateValue(layoutProperties.right, suggestedSize.width) - TiDimensionCalculateValue(layoutProperties.centerX, suggestedSize.width));
        }
        else {
            recheckForFillW = followsFillWidthBehavior;
            autoComputed = YES;
            autoSize = [self autoSizeForSize:autoSize];
            result.width += autoSize.width;
        }
    }
	else
	{
		autoComputed = YES;
        autoSize = [self autoSizeForSize:autoSize];
        result.width += autoSize.width;
	}
    if (recheckForFillW && (result.width < suggestedSize.width) ) {
        result.width = suggestedSize.width;
    }
    
    
    if (TiDimensionIsDip(layoutProperties.height) || TiDimensionIsPercent(layoutProperties.height))	{
		result.height += TiDimensionCalculateValue(layoutProperties.height, suggestedSize.height);
	}
    else if (TiDimensionIsAutoFill(layoutProperties.height) || (TiDimensionIsAuto(layoutProperties.height) && followsFillHeightBehavior) )
	{
		recheckForFillH = YES;
        if (autoComputed == NO) {
            autoComputed = YES;
            autoSize = [self autoSizeForSize:autoSize];
        }
		result.height += autoSize.height;
	}
    else if (followsFillHeightBehavior && TiDimensionIsUndefined(layoutProperties.height))
    {
        if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.centerY) ) {
            result.height += 2 * ( TiDimensionCalculateValue(layoutProperties.centerY, suggestedSize.height) - TiDimensionCalculateValue(layoutProperties.top, suggestedSize.height) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height += TiDimensionCalculateMargins(layoutProperties.top, layoutProperties.bottom, suggestedSize.height);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerY) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height += 2 * ( suggestedSize.height - TiDimensionCalculateValue(layoutProperties.bottom, suggestedSize.height) - TiDimensionCalculateValue(layoutProperties.centerY, suggestedSize.height));
        }
        else {
            recheckForFillH = followsFillHeightBehavior;
            if (autoComputed == NO) {
                autoComputed = YES;
                autoSize = [self autoSizeForSize:autoSize];
            }
            result.height += autoSize.height;
        }
    }
	else
	{
		if (autoComputed == NO) {
            autoComputed = YES;
            autoSize = [self autoSizeForSize:autoSize];
        }
		result.height += autoSize.height;
	}
    if (recheckForFillH && (result.height < suggestedSize.height) ) {
        result.height = suggestedSize.height;
    }
    result = minmaxSize(&layoutProperties, result, size);
    
	return result;
}


-(UIBarButtonItem*)barButtonItemForController:(UINavigationController*)navController
{
	if (barButtonItem == nil)
	{
		isUsingBarButtonItem = YES;
		barButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[self barButtonViewForRect:navController.navigationBar.bounds]];
	}
	return barButtonItem;
}

-(UIBarButtonItem*)barButtonItem
{
	return [self barButtonItemForRect:CGRectZero];
}

-(UIBarButtonItem*)barButtonItemForRect:(CGRect)bounds
{
	if (barButtonItem == nil)
	{
		isUsingBarButtonItem = YES;
		barButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[self barButtonViewForRect:bounds]];
	}
	return barButtonItem;
}

- (TiUIView *)barButtonViewForRect:(CGRect)bounds
{
    self.canBeResizedByFrame = YES;
    //TODO: This logic should have a good place in case that refreshLayout is used.
	LayoutConstraint barButtonLayout = layoutProperties;
	if (TiDimensionIsUndefined(barButtonLayout.width))
	{
		barButtonLayout.width = TiDimensionAutoSize;
        
	}
	if (TiDimensionIsUndefined(barButtonLayout.height))
	{
		barButtonLayout.height = TiDimensionAutoSize;
	}
    return [self getAndPrepareViewForOpening:bounds];
}

- (TiUIView *)barButtonViewForSize:(CGSize)size
{
    return [self barButtonViewForRect:CGRectMake(0, 0, size.width, size.height)];
}


#pragma mark Recognizers

//supposed to be called on init
-(void)setDefaultReadyToCreateView:(BOOL)ready
{
    defaultReadyToCreateView = readyToCreateView = ready;
}

-(void)setReadyToCreateView:(BOOL)ready
{
    [self setReadyToCreateView:YES recursive:YES];
}

-(void)setReadyToCreateView:(BOOL)ready recursive:(BOOL)recursive
{
    readyToCreateView = ready;
    if (!recursive) return;
    
    [self makeChildrenPerformSelector:@selector(setReadyToCreateView:) withObject:ready];
}

-(TiUIView*)getOrCreateView
{
    readyToCreateView = YES;
    return [self view];
}

-(TiUIView*) getAndPrepareViewForOpening:(CGRect)bounds
{
    if([self viewAttached]) return view;
    [self setSandboxBounds:bounds];
    [self parentWillShow];
    [self windowWillOpen];
    [self windowDidOpen];
    TiUIView* tiview = [self getOrCreateView];
    return tiview;
}


-(TiUIView*) getAndPrepareViewForOpening
{
    if([self viewAttached]) return view;
    [self determineSandboxBoundsForce];
    [self parentWillShow];
    [self windowWillOpen];
    [self windowDidOpen];
    TiUIView* tiview = [self getOrCreateView];
    return tiview;
}


-(void)determineSandboxBoundsForce
{
    if(!CGRectIsEmpty(sandboxBounds)) return;
    if(!CGRectIsEmpty(view.bounds)){
        [self setSandboxBounds:view.bounds];
    }
    else if (!CGRectIsEmpty(sizeCache)) {
        [self setSandboxBounds:sizeCache];
    }
    else if (parent != nil) {
        CGRect bounds = [[[self viewParent] view] bounds];
        if (!CGRectIsEmpty(bounds)){
            [self setSandboxBounds:bounds];
        }
        else [self setSandboxBounds:([self viewParent]).sandboxBounds];
    }
}

-(TiUIView*)view
{
	if (view == nil && readyToCreateView)
	{
		WARN_IF_BACKGROUND_THREAD_OBJ
#ifdef VERBOSE
		if(![NSThread isMainThread])
		{
			NSLog(@"[WARN] Break here");
		}
#endif		
		// on open we need to create a new view
		[self viewWillInitialize];
		view = [self newView];
		view.proxy = self;
		view.layer.transform = CATransform3DIdentity;
		view.transform = CGAffineTransformIdentity;
        view.hidden = hidden;

		[view initializeState];

        [self configurationStart];
		// fire property changes for all properties to our delegate
		[self firePropertyChanges];

		[self configurationSet];

		NSArray * childrenArray = [[self viewChildren] retain];
		for (id child in childrenArray)
		{
			TiUIView *childView = [(TiViewProxy*)child getOrCreateView];
			[self insertSubview:childView forProxy:child];
		}
		[childrenArray release];

		viewInitialized = YES;
		[self viewDidInitialize];
		// If parent has a non absolute layout signal the parent that
		//contents will change else just lay ourselves out
//		if (parent != nil && ![parent absoluteLayout]) {
//			[parent contentsWillChange];
//		}
//		else {
			if(CGRectIsEmpty(sandboxBounds) && !CGRectIsEmpty(view.bounds)){
                [self setSandboxBounds:view.bounds];
			}
//            [self dirtyItAll];
//            [self refreshViewIfNeeded];
//		}
        if (!CGRectIsEmpty(sandboxBounds))
        {
            [self refreshView];
            [self handlePendingAnimation];
        }
	}

	CGRect bounds = [view bounds];
	if (!CGPointEqualToPoint(bounds.origin, CGPointZero))
	{
		[view setBounds:CGRectMake(0, 0, bounds.size.width, bounds.size.height)];
	}
	
	return view;
}

- (void)prepareForReuse
{
    [self makeChildrenPerformSelector:@selector(prepareForReuse) withObject:nil];
}

//CAUTION: TO BE USED ONLY WITH TABLEVIEW MAGIC
-(void)clearView:(BOOL)recurse
{
    [self setView:nil];
    if (recurse)
    [self makeChildrenPerformSelector:@selector(clearView:) withObject:recurse];
}

//CAUTION: TO BE USED ONLY WITH TABLEVIEW MAGIC
-(void)setView:(TiUIView *)newView
{
    if (view == newView) return;
    
    RELEASE_TO_NIL(view)
    
    if (self.modelDelegate!=nil)
    {
        if ([self.modelDelegate respondsToSelector:@selector(detachProxy)])
            [self.modelDelegate detachProxy];
        self.modelDelegate = nil;
    }
    
    if (newView == nil)
        readyToCreateView = defaultReadyToCreateView;
    else {
        view = [newView retain];
        self.modelDelegate = newView;
    }
}

//USED WITH TABLEVIEW MAGIC
//-(void)processPendingAdds
//{
//    pthread_rwlock_rdlock(&childrenLock);
//    for (TiViewProxy* child in [self children]) {
//        [child processPendingAdds];
//    }
//    
//    pthread_rwlock_unlock(&childrenLock);
//    if (pendingAdds != nil)
//    {
//        for (id child in pendingAdds)
//        {
//            [(TiViewProxy*)child processPendingAdds];
//            [self add:child];
//        }
//		RELEASE_TO_NIL(pendingAdds);
//    }
//}

//CAUTION: TO BE USED ONLY WITH TABLEVIEW MAGIC
-(void)fakeOpening
{
    windowOpened = parentVisible = YES;
}

-(NSMutableDictionary*)langConversionTable
{
    return nil;
}

#pragma mark Methods subclasses should override for behavior changes
-(BOOL)optimizeSubviewInsertion
{
    //Return YES for any view that implements a wrapperView that is a TiUIView (Button and ScrollView currently) and a basic view
    return ( [view isMemberOfClass:[TiUIView class]] ) ;
}

-(BOOL)suppressesRelayout
{
    if (controller != nil) {
        //If controller view is not loaded, sandbox bounds will become zero.
        //In that case we do not want to mess up our sandbox, which is by default
        //mainscreen bounds. It will adjust when view loads.
        return [controller isViewLoaded];
    }
	return NO;
}

-(BOOL)supportsNavBarPositioning
{
	return YES;
}

// TODO: Re-evaluate this along with the other controller propagation mechanisms, post 1.3.0.
// Returns YES for anything that can have a UIController object in its parent view
-(BOOL)canHaveControllerParent
{
	return YES;
}

-(BOOL)shouldDetachViewOnUnload
{
	return YES;
}

-(UIView *)parentViewForChild:(TiViewProxy *)child
{
	return [view parentViewForChildren];
}

-(TiWindowProxy*)getParentWindow
{
    if (parent) {
        if ([parent isKindOfClass:[TiWindowProxy class]])
        {
            return (TiWindowProxy*)parent;
        }
        else {
            return [[self viewParent] getParentWindow];
        }
    }
    return nil;
}

-(UIViewController*)getContentController
{
    if (controller) {
        return controller;
    }
    if (parent) {
        return [[self viewParent] getContentController];
    }
    return nil;
}

#pragma mark Event trigger methods

-(void)windowWillOpen
{

	
	// this method is called just before the top level window
	// that this proxy is part of will open and is ready for
	// the views to be attached
	
	if (windowOpened==YES)
	{
		return;
	}
	
	windowOpened = YES;
	windowOpening = YES;
    
    [self viewDidAttach];
    	
	// If the window was previously opened, it may need to have
	// its existing children redrawn
	// Maybe need to call layout children instead for non absolute layout
    [self makeChildrenPerformSelector:@selector(windowWillOpen) withObject:nil];
	

    //TODO: This should be properly handled and moved, but for now, let's force it (Redundantly, I know.)
	if (parent != nil) {
		[self parentWillShow];
	}
}

-(void)windowDidOpen
{
	windowOpening = NO;
    [self makeChildrenPerformSelector:@selector(windowDidOpen) withObject:nil];
}

-(void)windowWillClose
{
    [self makeChildrenPerformSelector:@selector(windowWillClose) withObject:nil];
}

-(void)windowDidClose
{
    if (controller) {
        [controller removeFromParentViewController];
        RELEASE_TO_NIL_AUTORELEASE(controller);
    }
    [self makeChildrenPerformSelector:@selector(windowDidClose) withObject:nil];
	[self detachView:NO];
	windowOpened=NO;
}


-(void)willFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(willFirePropertyChanges)])
	{
		[view performSelector:@selector(willFirePropertyChanges)];
	}
}

-(void)didFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(didFirePropertyChanges)])
	{
		[view performSelector:@selector(didFirePropertyChanges)];
	}
}

-(void)viewWillInitialize
{
	// for subclasses
}

-(void)viewDidInitialize
{
	// for subclasses
}

-(void)viewDidAttach
{
	// for subclasses
}


-(void)viewWillDetach
{
	// for subclasses
}

-(void)viewDidDetach
{
	// for subclasses
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    //For various views (scrollableView, NavGroup etc this info neeeds to be forwarded)
    NSArray* childProxies = [self viewChildren];
	for (TiViewProxy * thisProxy in childProxies)
	{
		if ([thisProxy respondsToSelector:@selector(willAnimateRotationToInterfaceOrientation:duration:)])
		{
			[(id)thisProxy willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
		}
	}
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    //For various views (scrollableView, NavGroup etc this info neeeds to be forwarded)
    NSArray* childProxies = [self viewChildren];
	for (TiViewProxy * thisProxy in childProxies)
	{
		if ([thisProxy respondsToSelector:@selector(willRotateToInterfaceOrientation:duration:)])
		{
			[(id)thisProxy willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
		}
	}
}

-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    //For various views (scrollableView, NavGroup etc this info neeeds to be forwarded)
    NSArray* childProxies = [self viewChildren];
	for (TiViewProxy * thisProxy in childProxies)
	{
		if ([thisProxy respondsToSelector:@selector(didRotateFromInterfaceOrientation:)])
		{
			[(id)thisProxy didRotateFromInterfaceOrientation:fromInterfaceOrientation];
		}
	}
}

#pragma mark Housecleaning state accessors

-(BOOL)viewHasSuperview:(UIView *)superview
{
	return [(UIView *)view superview] == superview;
}

-(BOOL)viewAttached
{
	return view!=nil && windowOpened;
}

-(BOOL)viewLayedOut
{
    CGRect rectToTest = parent?sizeCache:[[self view] bounds];
    return (rectToTest.size.width != 0 || rectToTest.size.height != 0);
}

//TODO: When swapping about proxies, views are uninitialized, aren't they?
-(BOOL)viewInitialized
{
	return viewInitialized && (view != nil);
}

-(BOOL)viewReady
{
	return view!=nil &&
			CGRectIsNull(view.bounds)==NO &&
			[view superview] != nil;
}

-(BOOL)windowHasOpened
{
	return windowOpened;
}

-(BOOL)windowIsOpening
{
	return windowOpening;
}

- (BOOL) isUsingBarButtonItem
{
	return isUsingBarButtonItem;
}

#pragma mark Building up and Tearing down

-(void)resetDefaultValues
{
    autoresizeCache = UIViewAutoresizingNone;
    sizeCache = CGRectZero;
    sandboxBounds = CGRectZero;
    positionCache = CGPointZero;
    repositioning = NO;
    parentVisible = NO;
    preventListViewSelection = NO;
    viewInitialized = NO;
    readyToCreateView = defaultReadyToCreateView;
    windowOpened = NO;
    windowOpening = NO;
    dirtyflags = 0;
    allowContentChange = YES;
    needsContentChange = NO;
}

-(id)init
{
	if ((self = [super init]))
	{
		destroyLock = [[NSRecursiveLock alloc] init];
		_bubbleParent = YES;
        defaultReadyToCreateView = NO;
        hidden = NO;
        [self resetDefaultValues];
        _transitioning = NO;
        vzIndex = 0;
        _canBeResizedByFrame = NO;
//        _runningViewAnimations = [[NSMutableArray alloc] init];
	}
	return self;
}

-(void)_configure
{
    [self replaceValue:@(YES) forKey:@"enabled" notification:NO];
    [self replaceValue:@(NO) forKey:@"fullscreen" notification:NO];
    [self replaceValue:@(YES) forKey:@"visible" notification:NO];
    [self replaceValue:@(FALSE) forKey:@"opaque" notification:NO];
    [self replaceValue:@(1.0f) forKey:@"opacity" notification:NO];
}

-(void)_initWithProperties:(NSDictionary*)properties
{
    updateStarted = YES;
    allowLayoutUpdate = NO;
	// Set horizontal layout wrap:true as default 
	layoutProperties.layoutFlags.horizontalWrap = NO;
    layoutProperties.fullscreen = NO;
	[self initializeProperty:@"visible" defaultValue:NUMBOOL(YES)];

	if (properties!=nil)
	{
        NSNumber* isVisible = [properties objectForKey:@"visible"];
        hidden = ![TiUtils boolValue:isVisible def:YES];
        
		NSString *objectId = [properties objectForKey:@"id"];
		NSString* className = [properties objectForKey:@"className"];
		NSMutableArray* classNames = [properties objectForKey:@"classNames"];
		
		NSString *type = [NSStringFromClass([self class]) stringByReplacingOccurrencesOfString:@"TiUI" withString:@""];
		type = [[type stringByReplacingOccurrencesOfString:@"Proxy" withString:@""] lowercaseString];

		TiStylesheet *stylesheet = [[[self pageContext] host] stylesheet];
		NSString *basename = [[self pageContext] basename];
		NSString *density = [TiUtils isRetinaDisplay] ? @"high" : @"medium";

		if (objectId!=nil || className != nil || classNames != nil || [stylesheet basename:basename density:density hasTag:type])
		{
			// get classes from proxy
			NSString *className = [properties objectForKey:@"className"];
			NSMutableArray *classNames = [properties objectForKey:@"classNames"];
			if (classNames==nil)
			{
				classNames = [NSMutableArray arrayWithCapacity:1];
			}
			if (className!=nil)
			{
				[classNames addObject:className];
			}

		    
		    NSDictionary *merge = [stylesheet stylesheet:objectId density:density basename:basename classes:classNames tags:[NSArray arrayWithObject:type]];
			if (merge!=nil)
			{
				// incoming keys take precendence over existing stylesheet keys
				NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:merge];
				[dict addEntriesFromDictionary:properties];
                
				properties = dict;
			}
		}
		// do a translation of language driven keys to their converted counterparts
		// for example titleid should look up the title in the Locale
		NSMutableDictionary *table = [self langConversionTable];
		if (table!=nil)
		{
			for (id key in table)
			{
				// determine which key in the lang table we need to use
				// from the lang property conversion key
				id langKey = [properties objectForKey:key];
				if (langKey!=nil)
				{
					// eg. titleid -> title
					id convertKey = [table objectForKey:key];
					// check and make sure we don't already have that key
					// since you can't override it if already present
					if ([properties objectForKey:convertKey]==nil)
					{
						id newValue = [TiLocale getString:langKey comment:nil];
						if (newValue!=nil)
						{
							[(NSMutableDictionary*)properties setObject:newValue forKey:convertKey];
						}
					}
				}
			}
		}
	}
	[super _initWithProperties:properties];
    updateStarted = NO;
    allowLayoutUpdate = YES;
    [self processTempProperties:nil];
    allowLayoutUpdate = NO;

}

-(void)dealloc
{
    if (controller != nil) {
        [controller detachProxy]; //make the controller knows we are done
        TiThreadReleaseOnMainThread(controller, NO);
        controller = nil;
    }
	RELEASE_TO_NIL(destroyLock);
	
	
	[super dealloc];
}


-(void)viewWillAppear:(BOOL)animated
{
    [self parentWillShowWithoutUpdate];
    [self refreshView];
}

-(void)viewWillDisappear:(BOOL)animated
{
}

-(void)viewDidDisappear:(BOOL)animated
{
    [self parentWillHide];
}

-(UIViewController*)hostingController;
{
    if (controller == nil) {
        controller = [[TiViewController alloc] initWithViewProxy:self];
    }
    return controller;
}

-(BOOL)retainsJsObjectForKey:(NSString *)key
{
	return ![key isEqualToString:@"animation"];
}

-(void)firePropertyChanges
{
	[self willFirePropertyChanges];
	
	if ([view respondsToSelector:@selector(readProxyValuesWithKeys:)]) {
		id<NSFastEnumeration> values = [self allKeys];
		[view readProxyValuesWithKeys:values];
	}

	[self didFirePropertyChanges];
}

-(TiUIView*)newView
{
    TiUIView* newview = nil;
	NSString * proxyName = NSStringFromClass([self class]);
	if ([proxyName hasSuffix:@"Proxy"]) 
	{
		Class viewClass = nil;
		NSString * className = [proxyName substringToIndex:[proxyName length]-5];
		viewClass = NSClassFromString(className);
		if (viewClass != nil)
		{
			return [[viewClass alloc] init];
		}
	}
	else
	{
		DeveloperLog(@"[WARN] No TiView for Proxy: %@, couldn't find class: %@",self,proxyName);
	}
    return [[TiUIView alloc] init];
}


-(void)detachView
{
	[self detachView:YES];
}

-(void)detachView:(BOOL)recursive
{
	[destroyLock lock];
    
    if(recursive)
    {
        [self makeChildrenPerformSelector:@selector(detachView) withObject:nil];
    }
    
	if (view!=nil)
	{
		[self viewWillDetach];
        [self cancelAllAnimations:nil];
		[view removeFromSuperview];
		view.proxy = nil;
        view.touchDelegate = nil;
		RELEASE_TO_NIL(view);
		[self viewDidDetach];
	}
    if (self.modelDelegate!=nil)
    {
        if ([self.modelDelegate respondsToSelector:@selector(detachProxy)])
            [self.modelDelegate detachProxy];
        self.modelDelegate = nil;
    }
	[destroyLock unlock];
    [self clearAnimations];
    [self resetDefaultValues];

}

-(void)_destroy
{
	[destroyLock lock];
	if ([self destroyed])
	{
		// not safe to do multiple times given rwlock
		[destroyLock unlock];
		return;
	}
	// _destroy is called during a JS context shutdown, to inform the object to 
	// release all its memory and references.  this will then cause dealloc 
	// on objects that it contains (assuming we don't have circular references)
	// since some of these objects are registered in the context and thus still
	// reachable, we need _destroy to help us start the unreferencing part
	[super _destroy];

	//Part of super's _destroy is to release the modelDelegate, which in our case is ALSO the view.
	//As such, we need to have the super happen before we release the view, so that we can insure that the
	//release that triggers the dealloc happens on the main thread.
	
	if (barButtonItem != nil)
	{
		if ([NSThread isMainThread])
		{
			RELEASE_TO_NIL(barButtonItem);
		}
		else
		{
			TiThreadReleaseOnMainThread(barButtonItem, NO);
			barButtonItem = nil;
		}
	}

	if (view!=nil)
	{
		if ([NSThread isMainThread])
		{
			[self detachView];
		}
		else
		{
			view.proxy = nil;
			TiThreadReleaseOnMainThread(view, NO);
			view = nil;
		}
	}
	[destroyLock unlock];
}

-(void)destroy
{
	//FIXME- me already have a _destroy, refactor this
	[self _destroy];
}

-(void)removeBarButtonView
{
    self.canBeResizedByFrame = NO;
	isUsingBarButtonItem = NO;
	[self setBarButtonItem:nil];
}

#pragma mark Callbacks

-(void)didReceiveMemoryWarning:(NSNotification*)notification
{
	// Only release a view if we're the only living reference for it
	// WARNING: do not call [self view] here as that will create the
	// view if it doesn't yet exist (thus defeating the purpose of
	// this method)
	
	//NOTE: for now, we're going to have to turn this off until post
	//1.4 where we can figure out why the drawing is screwed up since
	//the views aren't reattaching.  
	/*
	if (view!=nil && [view retainCount]==1)
	{
		[self detachView];
	}*/
	[super didReceiveMemoryWarning:notification];
}

-(void)makeViewPerformSelector:(SEL)selector withObject:(id)object createIfNeeded:(BOOL)create waitUntilDone:(BOOL)wait
{
	BOOL isAttached = [self viewAttached];
	
	if(!isAttached && !create)
	{
		return;
	}

	if([NSThread isMainThread])
	{
		[[self view] performSelector:selector withObject:object];
		return;
	}

	if(isAttached)
	{
		TiThreadPerformOnMainThread(^{[[self view] performSelector:selector withObject:object];}, wait);
		return;
	}

	TiThreadPerformOnMainThread(^{
		[[self getOrCreateView] performSelector:selector withObject:object];
	}, wait);
}

#pragma mark Listener Management


-(void)fireEvent:(NSString*)type withObject:(id)obj propagate:(BOOL)propagate reportSuccess:(BOOL)report errorCode:(int)code message:(NSString*)message checkForListener:(BOOL)checkForListener;
{
    if (checkForListener && ![self _hasListeners:type])
	{
		return;
	}
    if (_bubbleParentDefined) {
        propagate = _bubbleParent;
    }
	[super fireEvent:type withObject:obj propagate:propagate reportSuccess:report errorCode:code message:message checkForListener:NO];
}

-(void)parentListenersChanged
{
    TiThreadPerformOnMainThread(^{
        if (view != nil && [view respondsToSelector:@selector(updateTouchHandling)]) {
            [view updateTouchHandling];
        }
    }, NO);
}

-(void)_listenerAdded:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil && [(NSObject*)self.modelDelegate respondsToSelector:@selector(listenerAdded:count:)])
	{
		[self.modelDelegate listenerAdded:type count:count];
	}
	else if(view!=nil) // don't create the view if not already realized
	{
		if ([self.view respondsToSelector:@selector(listenerAdded:count:)]) {
			[self.view listenerAdded:type count:count];
		}
	}
    
    [super _listenerAdded:type count:count];
}

-(void)_listenerRemoved:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil && [(NSObject*)self.modelDelegate respondsToSelector:@selector(listenerRemoved:count:)])
	{
		[self.modelDelegate listenerRemoved:type count:count];
	}
	else if(view!=nil) // don't create the view if not already realized
	{
		if ([self.view respondsToSelector:@selector(listenerRemoved:count:)]) {
			[self.view listenerRemoved:type count:count];
		}
	}
    [super _listenerRemoved:type count:count];

}

-(TiProxy *)parentForBubbling
{
	return parent;
}

#pragma mark Layout events, internal and external

#define SET_AND_PERFORM(flagBit,action)	\
if (!viewInitialized || hidden || !parentVisible || OSAtomicTestAndSetBarrier(flagBit, &dirtyflags)) \
{	\
	action;	\
}


-(void)willEnqueue
{
	SET_AND_PERFORM(TiRefreshViewEnqueued,return);
    if (!allowContentChange) return;
	[TiLayoutQueue addViewProxy:self];
}

-(void)willEnqueueIfVisible
{
	if(parentVisible && !hidden)
	{
		[self willEnqueue];
	}
}


-(void)performBlockWithoutLayout:(void (^)(void))block
{
    allowContentChange = NO;
    block();
    allowContentChange = YES;
}

-(void)performBlock:(void (^)(void))block withinAnimation:(TiViewAnimationStep*)animation
{
    if (animation) {
        [self setRunningAnimation:animation];
        block();
        [self setRunningAnimation:nil];
    }
    else {
        block();
    }
}

-(void)performBlock:(void (^)(void))block withinOurAnimationOnProxy:(TiViewProxy*)viewProxy
{
    [viewProxy performBlock:block withinAnimation:[self runningAnimation]];
}

-(void)parentContentWillChange
{
    if (allowContentChange == NO && [[self viewParent] allowContentChange])
    {
        [[self viewParent] performBlockWithoutLayout:^{
            [[self viewParent] contentsWillChange];
        }];
    }
    else {
        [[self viewParent] contentsWillChange];
    }
}

-(void)willChangeSize
{
	SET_AND_PERFORM(TiRefreshViewSize,return);

	if (![self absoluteLayout])
	{
		[self willChangeLayout];
	}
    else {
        [self willResizeChildren];
    }
	if(TiDimensionIsUndefined(layoutProperties.centerX) ||
			TiDimensionIsUndefined(layoutProperties.centerY))
	{
		[self willChangePosition];
	}

	[self willEnqueueIfVisible];
    [self parentContentWillChange];
	
    if (!allowContentChange) return;
    [self makeChildrenPerformSelector:@selector(parentSizeWillChange) withObject:nil];
}

-(void)willChangePosition
{
	SET_AND_PERFORM(TiRefreshViewPosition,return);

	if(TiDimensionIsUndefined(layoutProperties.width) || 
			TiDimensionIsUndefined(layoutProperties.height))
	{//The only time size can be changed by the margins is if the margins define the size.
		[self willChangeSize];
	}
	[self willEnqueueIfVisible];
    [self parentContentWillChange];
}

-(void)willChangeZIndex
{
	SET_AND_PERFORM(TiRefreshViewZIndex, return);
	//Nothing cascades from here.
	[self willEnqueueIfVisible];
}

-(void)willShow;
{
    [self willChangeZIndex];
    
    pthread_rwlock_rdlock(&childrenLock);
    if (allowContentChange)
    {
        [self makeChildrenPerformSelector:@selector(parentWillShow) withObject:nil];
    }
    else {
        [self makeChildrenPerformSelector:@selector(parentWillShowWithoutUpdate) withObject:nil];
    }
    pthread_rwlock_unlock(&childrenLock);
    
    if (parent && ![[self viewParent] absoluteLayout])
        [self parentContentWillChange];
    else {
        [self contentsWillChange];
    }
    
}

-(void)willHide;
{
    //	SET_AND_PERFORM(TiRefreshViewZIndex,);
    dirtyflags = 0;

    [self makeChildrenPerformSelector:@selector(parentWillHide) withObject:nil];
    
    if (parent && ![[self viewParent] absoluteLayout])
        [self parentContentWillChange];
}

-(void)willResizeChildren
{
    if (childrenCount == 0) return;
	SET_AND_PERFORM(TiRefreshViewChildrenPosition,return);
	[self willEnqueueIfVisible];
}

-(void)willChangeLayout
{
    if (!viewInitialized)return;
    BOOL alreadySet = OSAtomicTestAndSet(TiRefreshViewChildrenPosition, &dirtyflags);

	[self willEnqueueIfVisible];

    if (!allowContentChange || alreadySet) return;
    [self makeChildrenPerformSelector:@selector(parentWillRelay) withObject:nil];
}

-(BOOL) widthIsAutoSize
{
    if (layoutProperties.fullscreen) return NO;
    BOOL isAutoSize = NO;
    if (TiDimensionIsAutoSize(layoutProperties.width))
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.width) && TiDimensionIsAutoSize([self defaultAutoWidthBehavior:nil]) )
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsUndefined(layoutProperties.width) && TiDimensionIsAutoSize([self defaultAutoWidthBehavior:nil]))
    {
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.left) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerX) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.right) ) {
            pinCount ++;
        }
        if (pinCount < 2) {
            isAutoSize = YES;
        }
    }
    return isAutoSize;
}

-(BOOL) heightIsAutoSize
{
    if (layoutProperties.fullscreen) return NO;
    BOOL isAutoSize = NO;
    if (TiDimensionIsAutoSize(layoutProperties.height))
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.height) && TiDimensionIsAutoSize([self defaultAutoHeightBehavior:nil]) )
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsUndefined(layoutProperties.height) && TiDimensionIsAutoSize([self defaultAutoHeightBehavior:nil]))
    {
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.top) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerY) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.bottom) ) {
            pinCount ++;
        }
        if (pinCount < 2) {
            isAutoSize = YES;
        }
    }
    return isAutoSize;
}

-(BOOL) widthIsAutoFill
{
    if (layoutProperties.fullscreen) return YES;
    BOOL isAutoFill = NO;
    BOOL followsFillBehavior = TiDimensionIsAutoFill([self defaultAutoWidthBehavior:nil]);
    
    if (TiDimensionIsAutoFill(layoutProperties.width))
    {
        isAutoFill = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.width))
    {
        isAutoFill = followsFillBehavior;
    }
    else if (TiDimensionIsUndefined(layoutProperties.width))
    {
        BOOL centerDefined = NO;
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.left) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerX) ) {
            centerDefined = YES;
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.right) ) {
            pinCount ++;
        }
        if ( (pinCount < 2) || (!centerDefined) ){
            isAutoFill = followsFillBehavior;
        }
    }
    return isAutoFill;
}

-(BOOL) heightIsAutoFill
{
    if (layoutProperties.fullscreen) return YES;
    BOOL isAutoFill = NO;
    BOOL followsFillBehavior = TiDimensionIsAutoFill([self defaultAutoHeightBehavior:nil]);
    
    if (TiDimensionIsAutoFill(layoutProperties.height))
    {
        isAutoFill = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.height))
    {
        isAutoFill = followsFillBehavior;
    }
    else if (TiDimensionIsUndefined(layoutProperties.height))
    {
        BOOL centerDefined = NO;
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.top) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerY) ) {
            centerDefined = YES;
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.bottom) ) {
            pinCount ++;
        }
        if ( (pinCount < 2) || (!centerDefined) ) {
            isAutoFill = followsFillBehavior;
        }
    }
    return isAutoFill;
}

-(void)contentsWillChange
{
    BOOL isAutoSize = [self widthIsAutoSize] || [self heightIsAutoSize];
    
	if (isAutoSize)
	{
		[self willChangeSize];
	}
	else if (![self absoluteLayout])
	{//Since changing size already does this, we only need to check
	//Layout if the changeSize didn't
		[self willChangeLayout];
	}
}

-(BOOL)allowContentChange
{
    return allowContentChange;
}

-(void)contentsWillChangeImmediate
{
    allowContentChange = NO;
    [self contentsWillChange];
    allowContentChange = YES;
    [self refreshViewOrParent];
}

-(void)contentsWillChangeAnimated:(NSTimeInterval)duration
{
    [UIView animateWithDuration:duration animations:^{
        [self contentsWillChangeImmediate];
    }];
}

-(void)parentSizeWillChange
{
//	if not dip, change size
	if(!TiDimensionIsDip(layoutProperties.width) || !TiDimensionIsDip(layoutProperties.height) )
	{
		[self willChangeSize];
	}
	if(!TiDimensionIsDip(layoutProperties.centerX) ||
			!TiDimensionIsDip(layoutProperties.centerY))
	{
		[self willChangePosition];
	}
}

-(void)parentWillRelay
{
//	if percent or undefined size, change size
	if(TiDimensionIsUndefined(layoutProperties.width) ||
			TiDimensionIsUndefined(layoutProperties.height) ||
			TiDimensionIsPercent(layoutProperties.width) ||
			TiDimensionIsPercent(layoutProperties.height))
	{
		[self willChangeSize];
	}
	[self willChangePosition];
}

-(void)parentWillShow
{
	VerboseLog(@"[INFO] Parent Will Show for %@",self);
	if(parentVisible)
	{//Nothing to do here, we're already visible here.
		return;
	}
	parentVisible = YES;
	if(!hidden)
	{	//We should propagate this new status! Note this does not change the visible property.
		[self willShow];
	}
}

-(void)parentWillShowWithoutUpdate
{
    BOOL wasSet = allowContentChange;
    allowContentChange = NO;
    [self parentWillShow];
    allowContentChange = wasSet;
}

-(void)parentWillHide
{
	VerboseLog(@"[INFO] Parent Will Hide for %@",self);
	if(!parentVisible)
	{//Nothing to do here, we're already invisible here.
		return;
	}
	parentVisible = NO;
	if(!hidden)
	{	//We should propagate this new status! Note this does not change the visible property.
		[self willHide];
	}
}

#pragma mark Layout actions


-(void)updateZIndex {
    if(OSAtomicTestAndClearBarrier(TiRefreshViewZIndex, &dirtyflags) && vzIndex > 0) {
        if(parent != nil) {
            [[self viewParent] reorderZChildren];
        }
    }
}

// Need this so we can overload the sandbox bounds on split view detail/master
-(void)determineSandboxBounds
{
    if (controller) return;
    [self updateZIndex];
    UIView * ourSuperview = [[self view] superview];
    if(ourSuperview != nil)
    {
        sandboxBounds = [ourSuperview bounds];
    }
}

-(void)refreshView:(TiUIView *)transferView
{
    [self refreshView:transferView withinAnimation:nil];
}


-(void)refreshView
{
    [self dirtyItAll];
	[self refreshViewIfNeeded];
}

-(void)refreshViewIfNeeded
{
	[self refreshViewIfNeeded:NO];
}

-(void)refreshViewOrParent
{
    TiViewProxy* viewParent = [self viewParent];
    if (viewParent && [viewParent isDirty]) {
        [self performBlock:^{
            [viewParent refreshViewOrParent];
        } withinOurAnimationOnProxy:viewParent];
    }
    else {
        [self refreshViewIfNeeded:YES];
    }
}

-(void)refreshViewIfNeeded:(BOOL)recursive
{
    BOOL needsRefresh = OSAtomicTestAndClear(TiRefreshViewEnqueued, &dirtyflags);
    TiViewProxy* viewParent = [self viewParent];
    if (viewParent && [viewParent willBeRelaying] && ![viewParent absoluteLayout]) {
        return;
    }
    
    if (!needsRefresh)
    {
        //even if our sandbox is null and we are not ready (next test) let s still call refresh our our children. They wont refresh but at least they will clear their TiRefreshViewEnqueued flags !
        if (recursive){
            [self makeChildrenPerformSelector:@selector(refreshViewIfNeeded:) withObject:recursive];
        }
        return;
	}
    if (CGRectIsEmpty(sandboxBounds) && (!view || ![view superview])) {
        //we have no way to get our size yet. May be we need to be added to a superview
        //let s keep our flags set
        return;
    }
    
	if(parent && !parentVisible)
	{
		VerboseLog(@"[INFO] Parent Invisible");
		return;
	}
	
	if(hidden)
	{
		return;
	}
    
    if (view != nil)
	{
        BOOL relayout = ![self suppressesRelayout];
        if (parent != nil && ![viewParent absoluteLayout]) {
            //Do not mess up the sandbox in vertical/horizontal layouts
            relayout = NO;
        }
        if(relayout)
        {
            [self determineSandboxBounds];
        }
        BOOL layoutChanged = [self relayout];
        
        if (OSAtomicTestAndClear(TiRefreshViewChildrenPosition, &dirtyflags) || layoutChanged) {
            [self layoutChildren:NO];
        }
        [self handlePendingAnimation];
	}
}

-(void)dirtyItAll
{
    OSAtomicTestAndSet(TiRefreshViewZIndex, &dirtyflags);
    OSAtomicTestAndSet(TiRefreshViewEnqueued, &dirtyflags);
    OSAtomicTestAndSet(TiRefreshViewSize, &dirtyflags);
    OSAtomicTestAndSet(TiRefreshViewPosition, &dirtyflags);
    if (childrenCount > 0) OSAtomicTestAndSet(TiRefreshViewChildrenPosition, &dirtyflags);
}

-(void)clearItAll
{
    dirtyflags = 0;
}

-(BOOL)isDirty
{
    return [self willBeRelaying];
}

-(void)refreshView:(TiUIView *)transferView withinAnimation:(TiViewAnimationStep*)animation
{
    [transferView setRunningAnimation:animation];
    WARN_IF_BACKGROUND_THREAD_OBJ;
	OSAtomicTestAndClearBarrier(TiRefreshViewEnqueued, &dirtyflags);
	
	if(!parentVisible)
	{
		VerboseLog(@"[INFO] Parent Invisible");
		return;
	}
	
	if(hidden)
	{
		return;
	}
    
	BOOL changedFrame = NO;
    //BUG BARRIER: Code in this block is legacy code that should be factored out.
	if ([self viewAttached])
	{
		CGRect oldFrame = [[self view] frame];
        BOOL relayout = ![self suppressesRelayout];
        if (parent != nil && ![[self viewParent] absoluteLayout]) {
            //Do not mess up the sandbox in vertical/horizontal layouts
            relayout = NO;
        }
        if(relayout)
        {
            [self determineSandboxBounds];
        }
        if ([self relayout] || relayout || animation || OSAtomicTestAndClear(TiRefreshViewChildrenPosition, &dirtyflags)) {
            OSAtomicTestAndClear(TiRefreshViewChildrenPosition, &dirtyflags);
            [self layoutChildren:NO];
        }
		if (!CGRectEqualToRect(oldFrame, [[self view] frame])) {
			[[self viewParent] childWillResize:self withinAnimation:animation];
		}
	}
    
    //END BUG BARRIER
    
	if(OSAtomicTestAndClearBarrier(TiRefreshViewSize, &dirtyflags))
	{
		[self refreshSize];
		if(TiLayoutRuleIsAbsolute(layoutProperties.layoutStyle))
		{
			for (TiViewProxy * thisChild in [self viewChildren])
			{
				[thisChild setSandboxBounds:sizeCache];
			}
		}
		changedFrame = YES;
	}
	else if(transferView != nil)
	{
		[transferView setBounds:sizeCache];
	}
    
	if(OSAtomicTestAndClearBarrier(TiRefreshViewPosition, &dirtyflags))
	{
		[self refreshPosition];
		changedFrame = YES;
	}
	else if(transferView != nil)
	{
		[transferView setCenter:positionCache];
	}
    
    //We should only recurse if we're a non-absolute layout. Otherwise, the views can take care of themselves.
	if(OSAtomicTestAndClearBarrier(TiRefreshViewChildrenPosition, &dirtyflags) && (transferView == nil))
        //If transferView is non-nil, this will be managed by the table row.
	{
		
	}
    
	if(transferView != nil)
	{
        //TODO: Better handoff of view
		[self setView:transferView];
	}
    
    //By now, we MUST have our view set to transferView.
	if(changedFrame || (transferView != nil))
	{
		[view setAutoresizingMask:autoresizeCache];
	}
    
    
	[self updateZIndex];
    [transferView setRunningAnimation:nil];
}

-(void)refreshPosition
{
	OSAtomicTestAndClearBarrier(TiRefreshViewPosition, &dirtyflags);
}

-(void)refreshSize
{
	OSAtomicTestAndClearBarrier(TiRefreshViewSize, &dirtyflags);
}


+(void)reorderViewsInParent:(UIView*)parentView
{
	if (parentView == nil) return;
    
    NSMutableArray* parentViewToSort = [NSMutableArray array];
    for (UIView* subview in [parentView subviews])
    {
        if ([subview isKindOfClass:[TiUIView class]]) {
            [parentViewToSort addObject:subview];
        }
    }
    NSArray *sortedArray = [parentViewToSort sortedArrayUsingComparator:^NSComparisonResult(TiUIView* a, TiUIView* b) {
        int first = [(TiViewProxy*)(a.proxy) vzIndex];
        int second = [(TiViewProxy*)(b.proxy) vzIndex];
        return (first > second) ? NSOrderedDescending : ( first < second ? NSOrderedAscending : NSOrderedSame );
    }];
    for (TiUIView* view in sortedArray) {
        [parentView bringSubviewToFront:view];
    }
}

-(void)reorderZChildren{
	if (view == nil) return;
    NSArray *sortedArray = [[self viewChildren] sortedArrayUsingComparator:^NSComparisonResult(TiViewProxy* a, TiViewProxy* b) {
        int first = [a vzIndex];
        int second = [b vzIndex];
        return (first > second) ? NSOrderedDescending : ( first < second ? NSOrderedAscending : NSOrderedSame );
    }];
    for (TiViewProxy* child in sortedArray) {
        [view bringSubviewToFront:[child view]];
    }
}

-(void)insertSubview:(UIView *)childView forProxy:(TiViewProxy *)childProxy
{
    UIView * ourView = [self parentViewForChild:childProxy];
    
    if (ourView==nil || childView == nil) {
        return;
    }
    [ourView addSubview:[childProxy view]];
}


-(BOOL)absoluteLayout
{
    return TiLayoutRuleIsAbsolute(layoutProperties.layoutStyle);
}


-(CGRect)computeBoundsForParentBounds:(CGRect)parentBounds
{
    CGSize size = SizeConstraintViewWithSizeAddingResizing(&layoutProperties,self, parentBounds.size, &autoresizeCache);
    if (!CGSizeEqualToSize(size, sizeCache.size)) {
        sizeCache.size = size;
    }
    CGPoint position = PositionConstraintGivenSizeBoundsAddingResizing(&layoutProperties, [[self viewParent] layoutProperties], self, sizeCache.size,
                                                               [[view layer] anchorPoint], parentBounds.size, sandboxBounds.size, &autoresizeCache);
    position.x += sizeCache.origin.x + sandboxBounds.origin.x;
    position.y += sizeCache.origin.y + sandboxBounds.origin.y;
    if (!CGPointEqualToPoint(position, positionCache)) {
        positionCache = position;
    }
    return CGRectMake(position.x - size.width/2, position.y - size.height/2, size.width, size.height);
}

#pragma mark Layout commands that need refactoring out

-(BOOL)relayout
{
	if (!repositioning && !CGSizeEqualToSize(sandboxBounds.size, CGSizeZero))
	{
		ENSURE_UI_THREAD_0_ARGS
        OSAtomicTestAndClear(TiRefreshViewEnqueued, &dirtyflags);
		repositioning = YES;

        UIView *parentView = [[self viewParent] parentViewForChild:self];
        CGSize referenceSize = (parentView != nil) ? parentView.bounds.size : sandboxBounds.size;
        if (CGSizeEqualToSize(referenceSize, CGSizeZero)) {
            repositioning = NO;
            return;
        }
        BOOL needsAll = CGRectIsEmpty(sizeCache);
        BOOL needsSize = OSAtomicTestAndClear(TiRefreshViewSize, &dirtyflags) || needsAll;
        BOOL needsPosition = OSAtomicTestAndClear(TiRefreshViewPosition, &dirtyflags) || needsAll;
        BOOL layoutChanged = NO;
        if (needsSize) {
            CGSize size;
            if (parent != nil && ![[self viewParent] absoluteLayout] ) {
                size = SizeConstraintViewWithSizeAddingResizing(&layoutProperties,self, sandboxBounds.size, &autoresizeCache);
            }
            else {
                size = SizeConstraintViewWithSizeAddingResizing(&layoutProperties,self, referenceSize, &autoresizeCache);
            }
            if (!CGSizeEqualToSize(size, sizeCache.size)) {
                sizeCache.size = size;
                layoutChanged = YES;
            }
        }
        if (needsPosition) {
            CGPoint position;
            position = PositionConstraintGivenSizeBoundsAddingResizing(&layoutProperties, [[self viewParent] layoutProperties], self, sizeCache.size,
            [[view layer] anchorPoint], referenceSize, sandboxBounds.size, &autoresizeCache);

            position.x += sizeCache.origin.x + sandboxBounds.origin.x;
            position.y += sizeCache.origin.y + sandboxBounds.origin.y;
            if (!CGPointEqualToPoint(position, positionCache)) {
                positionCache = position;
                layoutChanged = YES;
            }
        }
        
        layoutChanged |= autoresizeCache != view.autoresizingMask;
        if (!layoutChanged && [view isKindOfClass:[TiUIView class]]) {
            //Views with flexible margins might have already resized when the parent resized.
            //So we need to explicitly check for oldSize here which triggers frameSizeChanged
            CGSize oldSize = [(TiUIView*) view oldSize];
            layoutChanged = layoutChanged || !(CGSizeEqualToSize(oldSize,sizeCache.size) || !CGRectEqualToRect([view bounds], sizeCache) || !CGPointEqualToPoint([view center], positionCache));
        }
        
		
        [view setAutoresizingMask:autoresizeCache];
        [view setBounds:sizeCache];
        [view setCenter:positionCache];
        
        [self updateZIndex];
        
        if ([observer respondsToSelector:@selector(proxyDidRelayout:)]) {
            [observer proxyDidRelayout:self];
        }

        if (layoutChanged) {
            [self fireEvent:@"postlayout" propagate:NO];
        }
        repositioning = NO;
        return layoutChanged;
	}
#ifdef VERBOSE
	else
	{
		DeveloperLog(@"[INFO] %@ Calling Relayout from within relayout.",self);
	}
#endif
    return NO;
}

-(void)layoutChildrenIfNeeded
{
	IGNORE_IF_NOT_OPENED
	
    // if not visible, ignore layout
    if (view.hidden)
    {
        OSAtomicTestAndClearBarrier(TiRefreshViewEnqueued, &dirtyflags);
        return;
    }
    
    [self refreshView:nil];
}

-(BOOL)willBeRelaying
{
    DeveloperLog(@"DIRTY FLAGS %d WILLBERELAYING %d",dirtyflags, (*((char*)&dirtyflags) & (1 << (7 - TiRefreshViewEnqueued))));
    return ((*((char*)&dirtyflags) & (1 << (7 - TiRefreshViewEnqueued))) != 0);
}

-(void)childWillResize:(TiViewProxy *)child
{
    [self childWillResize:child withinAnimation:nil];
}

-(void)childWillResize:(TiViewProxy *)child withinAnimation:(TiViewAnimationStep*)animation
{
    if (animation != nil) {
        [self refreshView:nil withinAnimation:animation];
        return;
    }
    
	[self contentsWillChange];

	IGNORE_IF_NOT_OPENED
	
	BOOL containsChild = [[self children] containsObject:child];

	ENSURE_VALUE_CONSISTENCY(containsChild,YES);

	if (![self absoluteLayout])
	{
		BOOL alreadySet = OSAtomicTestAndSet(TiRefreshViewChildrenPosition, &dirtyflags);
		if (!alreadySet)
		{
			[self willEnqueue];
		}
	}
}

-(void)reposition
{
    [self repositionWithinAnimation:nil];
}

-(TiViewAnimationStep*)runningAnimation
{
    return [view runningAnimation];
}

-(void)setRunningAnimation:(TiViewAnimationStep*)animation
{
    [view setRunningAnimation:animation];
}

-(void)setRunningAnimationRecursive:(TiViewAnimationStep*)animation
{
    [view setRunningAnimation:animation];
    [self runBlock:^(TiViewProxy *proxy) {
        [proxy setRunningAnimationRecursive:animation];
    } onlyVisible:YES recursive:YES];
}

-(void)setFakeAnimationOfDuration:(NSTimeInterval)duration andCurve:(CAMediaTimingFunction*)curve
{
    TiFakeAnimation* anim = [[TiFakeAnimation alloc] init];
    anim.duration = duration;
    anim.curve = curve;
    [self setRunningAnimationRecursive:anim];
    [anim release];
}

-(BOOL)isRotating
{
    return [[self runningAnimation] isKindOfClass:[TiFakeAnimation class]];
}

-(void)removeFakeAnimation
{
//    id anim = [self runningAnimation];
    if ([[self runningAnimation] isKindOfClass:[TiFakeAnimation class]])
    {
        [self setRunningAnimationRecursive:nil];
//        [anim release];
    }
}


-(void)repositionWithinAnimation:(TiViewAnimationStep*)animation
{
	IGNORE_IF_NOT_OPENED
	
	UIView* superview = [[self view] superview];
	if (![self viewAttached] || view.hidden || superview == nil)
	{
		VerboseLog(@"[INFO] Reposition is exiting early in %@.",self);
		return;
	}
	if ([NSThread isMainThread])
    {
        [self performBlock:^{
            [self performBlockWithoutLayout:^{
                [self willChangeSize];
                [self willChangePosition];
            }];
            
            [self refreshViewOrParent];
        } withinAnimation:animation];
	}
	else
	{
		VerboseLog(@"[INFO] Reposition was called by a background thread in %@.",self);
		TiThreadPerformOnMainThread(^{[self reposition];}, NO);
	}
    
}

-(BOOL)wantsToFillVerticalLayout
{
    if ([self heightIsAutoFill]) return YES;
    if (TiDimensionIsDip(layoutProperties.height) || TiDimensionIsPercent(layoutProperties.height))return NO;
    NSArray* subproxies = [self visibleChildren];
    for (TiViewProxy* child in subproxies) {
        if ([child wantsToFillVerticalLayout]) return YES;
    }
    return NO;
}

-(BOOL)wantsToFillHorizontalLayout
{
    if ([self widthIsAutoFill]) return YES;
    if (TiDimensionIsDip(layoutProperties.width) || TiDimensionIsPercent(layoutProperties.width))return NO;
    NSArray* subproxies = [self visibleChildren];
    for (TiViewProxy* child in subproxies) {
        if ([child wantsToFillHorizontalLayout]) return YES;
    }
    return NO;
}

-(CGRect)boundsForMeasureForChild:(TiViewProxy*)child
{
    UIView * ourView = [self parentViewForChild:child];
    if (!ourView) return CGRectZero;
    return [ourView bounds];
}

-(NSArray*)measureChildren:(NSArray*)childArray
{
    if ([childArray count] == 0) {
        return nil;
    }
    
    BOOL horizontal =  TiLayoutRuleIsHorizontal(layoutProperties.layoutStyle);
    BOOL vertical =  TiLayoutRuleIsVertical(layoutProperties.layoutStyle);
	BOOL horizontalNoWrap = horizontal && !TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
	BOOL horizontalWrap = horizontal && TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
    NSMutableArray * measuredBounds = [NSMutableArray arrayWithCapacity:[childArray count]];
    NSUInteger i, count = [childArray count];
	int maxHeight = 0;
    
    NSMutableArray * widthFillChildren = horizontal?[NSMutableArray array]:nil;
    NSMutableArray * heightFillChildren = (vertical || horizontalWrap)?[NSMutableArray array]:nil;
    CGFloat widthNonFill = 0;
    CGFloat heightNonFill = 0;
    
    //First measure the sandbox bounds
    for (id child in childArray)
    {
        CGRect bounds = [self boundsForMeasureForChild:child];
        TiRect * childRect = [[TiRect alloc] init];
        CGRect childBounds = CGRectZero;
        
        if(![self absoluteLayout])
        {
            if (horizontalNoWrap) {
                if ([child wantsToFillHorizontalLayout])
                {
                    [widthFillChildren addObject:child];
                }
                else{
                    childBounds = [self computeChildSandbox:child withBounds:bounds];
                    maxHeight = MAX(maxHeight, childBounds.size.height);
                    widthNonFill += childBounds.size.width;
                }
            }
            else if (vertical) {
                if ([child wantsToFillVerticalLayout])
                {
                    [heightFillChildren addObject:child];
                }
                else{
                    childBounds = [self computeChildSandbox:child withBounds:bounds];
                    heightNonFill += childBounds.size.height;
                }
            }
            else {
                childBounds = [self computeChildSandbox:child withBounds:bounds];
            }
        }
        else {
            childBounds = bounds;
        }
        [childRect setRect:childBounds];
        [measuredBounds addObject:childRect];
        [childRect release];
    }
    //If it is a horizontal layout ensure that all the children in a row have the
    //same height for the sandbox
    
    int nbWidthAutoFill = [widthFillChildren count];
    if (nbWidthAutoFill > 0) {
        //it is horizontalNoWrap
        horizontalLayoutBoundary = 0;
        for (int i =0; i < [childArray count]; i++) {
            id child = [childArray objectAtIndex:i];
            CGRect bounds = [self boundsForMeasureForChild:child];
            CGFloat width = floorf((bounds.size.width - widthNonFill) / nbWidthAutoFill);
            if ([widthFillChildren containsObject:child]){
                CGRect usableRect = CGRectMake(0,0,width + horizontalLayoutBoundary, bounds.size.height);
                CGRect result = [self computeChildSandbox:child withBounds:usableRect];
                maxHeight = MAX(maxHeight, result.size.height);
                [(TiRect*)[measuredBounds objectAtIndex:i] setRect:result];
            }
            else {
                horizontalLayoutBoundary += [[(TiRect*)[measuredBounds objectAtIndex:i] width] floatValue];
            }
        }
    }
    
    int nbHeightAutoFill = [heightFillChildren count];
    if (nbHeightAutoFill > 0) {
        //it is vertical
        verticalLayoutBoundary = 0;
        for (int i =0; i < [childArray count]; i++) {
            id child = [childArray objectAtIndex:i];
            CGRect bounds = [self boundsForMeasureForChild:child];
            CGFloat height = floorf((bounds.size.height - heightNonFill) / nbHeightAutoFill);
            if ([heightFillChildren containsObject:child]){
                CGRect usableRect = CGRectMake(0,0,bounds.size.width, height + verticalLayoutBoundary);
                CGRect result = [self computeChildSandbox:child withBounds:usableRect];
                [(TiRect*)[measuredBounds objectAtIndex:i] setRect:result];
            }
            else {
                verticalLayoutBoundary += [[(TiRect*)[measuredBounds objectAtIndex:i] height] floatValue];
            }
        }
    }
	if (horizontalNoWrap)
	{
        int currentLeft = 0;
		for (i=0; i<count; i++)
		{
            [(TiRect*)[measuredBounds objectAtIndex:i] setX:[NSNumber numberWithInt:currentLeft]];
            currentLeft += [[(TiRect*)[measuredBounds objectAtIndex:i] width] integerValue];
//			[(TiRect*)[measuredBounds objectAtIndex:i] setHeight:[NSNumber numberWithInt:maxHeight]];
		}
	}
    else if(vertical && (count > 1) )
    {
        int currentTop = 0;
		for (i=0; i<count; i++)
		{
            [(TiRect*)[measuredBounds objectAtIndex:i] setY:[NSNumber numberWithInt:currentTop]];
            currentTop += [[(TiRect*)[measuredBounds objectAtIndex:i] height] integerValue];
		}
    }
	else if(horizontal && (count > 1) )
    {
        int startIndex,endIndex, currentTop;
        startIndex = endIndex = maxHeight = currentTop = -1;
        for (i=0; i<count; i++)
        {
            CGRect childSandbox = (CGRect)[(TiRect*)[measuredBounds objectAtIndex:i] rect];
            if (startIndex == -1)
            {
                //FIRST ELEMENT
                startIndex = i;
                maxHeight = childSandbox.size.height;
                currentTop = childSandbox.origin.y;
            }
            else
            {
                if (childSandbox.origin.y != currentTop)
                {
                    //MOVED TO NEXT ROW
                    endIndex = i;
                    for (int j=startIndex; j<endIndex; j++)
                    {
                        [(TiRect*)[measuredBounds objectAtIndex:j] setHeight:[NSNumber numberWithInt:maxHeight]];
                    }
                    startIndex = i;
                    endIndex = -1;
                    maxHeight = childSandbox.size.height;
                    currentTop = childSandbox.origin.y;
                }
                else if (childSandbox.size.height > maxHeight)
                {
                    //SAME ROW HEIGHT CHANGED
                    maxHeight = childSandbox.size.height;
                }
            }
        }
        if (endIndex == -1)
        {
            //LAST ROW
            for (i=startIndex; i<count; i++)
            {
                [(TiRect*)[measuredBounds objectAtIndex:i] setHeight:[NSNumber numberWithInt:maxHeight]];
            }
        }
    }
    return measuredBounds;
}

-(CGRect)computeChildSandbox:(TiViewProxy*)child withBounds:(CGRect)bounds
{
    CGRect originalBounds = bounds;
    BOOL followsFillWBehavior = TiDimensionIsAutoFill([child defaultAutoWidthBehavior:nil]);
    BOOL followsFillHBehavior = TiDimensionIsAutoFill([child defaultAutoHeightBehavior:nil]);
    __block CGSize autoSize;
    __block BOOL autoSizeComputed = FALSE;
    __block CGFloat boundingWidth = TiLayoutFlagsHasHorizontalWrap(&layoutProperties)?bounds.size.width:bounds.size.width - horizontalLayoutBoundary;
    __block CGFloat boundingHeight = bounds.size.height-verticalLayoutBoundary;
    if (boundingHeight < 0) {
        boundingHeight = 0;
    }
    void (^computeAutoSize)() = ^() {
        if (autoSizeComputed == FALSE) {
            autoSize = [child minimumParentSizeForSize:CGSizeMake(bounds.size.width, boundingHeight)];
            autoSizeComputed = YES;
        }
    };
    
    CGFloat (^computeHeight)() = ^() {
        if ([child layoutProperties]->fullscreen == YES) return boundingHeight;
        //TOP + BOTTOM
        CGFloat offsetV = TiDimensionCalculateValue([child layoutProperties]->top, bounds.size.height)
        + TiDimensionCalculateValue([child layoutProperties]->bottom, bounds.size.height);
        TiDimension constraint = [child layoutProperties]->height;
        switch (constraint.type)
        {
            case TiDimensionTypePercent:
            case TiDimensionTypeDip:
            {
                return  TiDimensionCalculateValue(constraint, boundingHeight) + offsetV;
            }
            case TiDimensionTypeAutoFill:
            {
                return boundingHeight;
            }
            case TiDimensionTypeUndefined:
            {
                if (!TiDimensionIsUndefined([child layoutProperties]->top) && !TiDimensionIsUndefined([child layoutProperties]->centerY) ) {
                    CGFloat height = 2 * ( TiDimensionCalculateValue([child layoutProperties]->centerY, boundingHeight) - TiDimensionCalculateValue([child layoutProperties]->top, boundingHeight) );
                    return height + offsetV;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->top) && !TiDimensionIsUndefined([child layoutProperties]->bottom) ) {
                    return boundingHeight;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->centerY) && !TiDimensionIsUndefined([child layoutProperties]->bottom) ) {
                    CGFloat height = 2 * ( boundingHeight - TiDimensionCalculateValue([child layoutProperties]->bottom, boundingHeight) - TiDimensionCalculateValue([child layoutProperties]->centerY, boundingHeight));
                    return height + offsetV;
                }
            }
            case TiDimensionTypeAuto:
            {
                if (followsFillHBehavior) {
                    //FILL behavior
                    return boundingHeight;
                }
            }
            default:
            case TiDimensionTypeAutoSize:
            {
                computeAutoSize();
                return autoSize.height; //offset is already in autoSize
            }
        }
    };
    
    if(TiLayoutRuleIsVertical(layoutProperties.layoutStyle))
    {
        bounds.origin.y = verticalLayoutBoundary;
        //LEFT + RIGHT
        CGFloat offsetH = TiDimensionCalculateValue([child layoutProperties]->left, bounds.size.width)
        + TiDimensionCalculateValue([child layoutProperties]->right, bounds.size.width);
        
        if ([child layoutProperties]->fullscreen == YES) {
            bounds.size.width = boundingWidth;
        }
        else {
            TiDimension constraint = [child layoutProperties]->width;
            switch (constraint.type)
            {
                case TiDimensionTypePercent:
                case TiDimensionTypeDip:
                {
                    bounds.size.width =  TiDimensionCalculateValue(constraint, boundingWidth) + offsetH;
                    break;
                }
                case TiDimensionTypeAutoFill:
                {
                    bounds.size.width = boundingWidth;
                    break;
                }
                case TiDimensionTypeUndefined:
                {
                    if (!TiDimensionIsUndefined([child layoutProperties]->left) && !TiDimensionIsUndefined([child layoutProperties]->centerX) ) {
                        CGFloat width = 2 * ( TiDimensionCalculateValue([child layoutProperties]->centerX, boundingWidth) - TiDimensionCalculateValue([child layoutProperties]->left, boundingWidth) );
                        bounds.size.width = width + offsetH;
                    }
                    else if (!TiDimensionIsUndefined([child layoutProperties]->centerX) && !TiDimensionIsUndefined([child layoutProperties]->right) ) {
                        CGFloat w   = 2 * ( boundingWidth - TiDimensionCalculateValue([child layoutProperties]->right, boundingWidth) - TiDimensionCalculateValue([child layoutProperties]->centerX, boundingWidth));
                        bounds.size.width = autoSize.width + offsetH;
                        break;
                    }
                }
                case TiDimensionTypeAuto:
                {
                    if (followsFillWBehavior) {
                        bounds.size.width = boundingWidth;
                        break;
                    }
                }
                default:
                case TiDimensionTypeAutoSize:
                {
                    computeAutoSize();
                    bounds.size.width = autoSize.width; //offset is already in autoSize
                    break;
                }
            }
        }
        
        bounds.size.height = computeHeight();
        verticalLayoutBoundary += bounds.size.height;
    }
    else if(TiLayoutRuleIsHorizontal(layoutProperties.layoutStyle))
    {
		BOOL horizontalWrap = TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
        BOOL followsFillBehavior = TiDimensionIsAutoFill([child defaultAutoWidthBehavior:nil]);
        bounds.size = [child sizeForAutoSize:bounds.size];
        
        //LEFT + RIGHT
        CGFloat offsetH = TiDimensionCalculateValue([child layoutProperties]->left, bounds.size.width)
        + TiDimensionCalculateValue([child layoutProperties]->right, bounds.size.width);
        //TOP + BOTTOM
        CGFloat offsetV = TiDimensionCalculateValue([child layoutProperties]->top, bounds.size.height)
        + TiDimensionCalculateValue([child layoutProperties]->bottom, bounds.size.height);
        
        
        CGFloat desiredWidth;
        BOOL recalculateWidth = NO;
        BOOL isPercent = NO;
        if ([child layoutProperties]->fullscreen == YES) {
            followsFillBehavior = YES;
            desiredWidth = boundingWidth;
        }
        else {
            TiDimension constraint = [child layoutProperties]->width;

            if (TiDimensionIsDip(constraint) || TiDimensionIsPercent(constraint))
            {
                desiredWidth =  TiDimensionCalculateValue(constraint, boundingWidth) + offsetH;
                isPercent = TiDimensionIsPercent(constraint);
            }
            else if (followsFillBehavior && TiDimensionIsUndefined(constraint))
            {
                if (!TiDimensionIsUndefined([child layoutProperties]->left) && !TiDimensionIsUndefined([child layoutProperties]->centerX) ) {
                    desiredWidth = 2 * ( TiDimensionCalculateValue([child layoutProperties]->centerX, boundingWidth) - TiDimensionCalculateValue([child layoutProperties]->left, boundingWidth) );
                    desiredWidth += offsetH;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->left) && !TiDimensionIsUndefined([child layoutProperties]->right) ) {
                    recalculateWidth = YES;
                    followsFillBehavior = YES;
                    desiredWidth = boundingWidth;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->centerX) && !TiDimensionIsUndefined([child layoutProperties]->right) ) {
                    desiredWidth = 2 * ( boundingWidth - TiDimensionCalculateValue([child layoutProperties]->right, boundingWidth) - TiDimensionCalculateValue([child layoutProperties]->centerX, boundingWidth));
                    desiredWidth += offsetH;
                }
                else {
                    recalculateWidth = YES;
                    computeAutoSize();
                    desiredWidth = autoSize.width;
                }
            }
            else if(TiDimensionIsAutoFill(constraint) || (TiDimensionIsAuto(constraint) && followsFillWBehavior)){
                followsFillBehavior = YES;
                desiredWidth = boundingWidth;
            }
            else {
                //This block takes care of auto,SIZE and FILL. If it is size ensure followsFillBehavior is set to false
                recalculateWidth = YES;
                computeAutoSize();
                desiredWidth = autoSize.width;
                followsFillBehavior = NO;
            }
        }
        
        bounds.size.height = computeHeight();
        
        if (horizontalWrap && (horizontalLayoutBoundary + desiredWidth >   boundingWidth)) {
            if (horizontalLayoutBoundary == 0.0) {
                //This is start of row
                bounds.origin.x = horizontalLayoutBoundary;
                bounds.origin.y = verticalLayoutBoundary;
                verticalLayoutBoundary += bounds.size.height;
                horizontalLayoutRowHeight = 0.0;
            }
            else {
                //This is not the start of row. Move to next row
                horizontalLayoutBoundary = 0.0;
                verticalLayoutBoundary += horizontalLayoutRowHeight;
                horizontalLayoutRowHeight = 0;
                bounds.origin.x = horizontalLayoutBoundary;
                bounds.origin.y = verticalLayoutBoundary;
                
                boundingWidth = originalBounds.size.width;
                boundingHeight = originalBounds.size.height - verticalLayoutBoundary;
                
                if (!recalculateWidth) {
                    if (desiredWidth < boundingWidth) {
                        horizontalLayoutBoundary += desiredWidth;
                        bounds.size.width = desiredWidth;
                        horizontalLayoutRowHeight = bounds.size.height;
                    }
                    else {
                        verticalLayoutBoundary += bounds.size.height;
                    }
                }
                else if (followsFillBehavior) {
                    
                    verticalLayoutBoundary += bounds.size.height;
                }
                else {
                    computeAutoSize();
                    desiredWidth = autoSize.width + offsetH;
                    if (desiredWidth < boundingWidth) {
                        
                        bounds.size.width = desiredWidth;
                        horizontalLayoutBoundary = bounds.size.width;
                        horizontalLayoutRowHeight = bounds.size.height;
                    }
                    else {
                        //fill whole space, another row again
                        verticalLayoutBoundary += bounds.size.height;
                    }
                }
                
            }
        }
        else {
            //If it fits update the horizontal layout row height
            bounds.origin.x = horizontalLayoutBoundary;
            bounds.origin.y = verticalLayoutBoundary;
            
            if (bounds.size.height > horizontalLayoutRowHeight) {
                horizontalLayoutRowHeight = bounds.size.height;
            }
            if (!recalculateWidth) {
                //DIP,PERCENT,UNDEFINED WITH ATLEAST 2 PINS one of them being centerX
                bounds.size.width = desiredWidth;
                horizontalLayoutBoundary += bounds.size.width;
            }
            else if(followsFillBehavior)
            {
                //FILL that fits in left over space. Move to next row
                bounds.size.width = boundingWidth;
				if (horizontalWrap) {
					horizontalLayoutBoundary = 0.0;
                	verticalLayoutBoundary += horizontalLayoutRowHeight;
					horizontalLayoutRowHeight = 0.0;
				} else {
					horizontalLayoutBoundary += bounds.size.width;
				}
            }
            else
            {
                //SIZE behavior
                bounds.size.width = desiredWidth;
                horizontalLayoutBoundary += bounds.size.width;
            }
        }
    }
    else {
        //        CGSize autoSize = [child minimumParentSizeForSize:bounds.size];
    }
    return bounds;
}

-(void)layoutChild:(TiViewProxy*)child optimize:(BOOL)optimize withMeasuredBounds:(CGRect)bounds
{
	IGNORE_IF_NOT_OPENED
	
	UIView * ourView = [self parentViewForChild:child];

	if (ourView==nil || [child isHidden])
	{
        [child clearItAll];
		return;
	}
	
	if (optimize==NO)
	{
		TiUIView *childView = [child view];
		TiUIView *parentView = (TiUIView*)[childView superview];
		if (parentView!=ourView)
		{
            [self insertSubview:childView forProxy:child];
            [self reorderZChildren];
		}
	}
	[child setSandboxBounds:bounds];
    [child dirtyItAll]; //for multileve recursion we need to make sure the child resizes itself
    [self performBlock:^{
        [child relayout];
    } withinOurAnimationOnProxy:child];

	// tell our children to also layout
	[child layoutChildren:optimize];
    [child handlePendingAnimation];
}

-(void)layoutNonRealChild:(TiViewProxy*)child withParent:(UIView*)parentView
{
    CGRect bounds = [self computeChildSandbox:child withBounds:[parentView bounds]];
    [child setSandboxBounds:bounds];
    [child refreshViewIfNeeded];
}

-(void)layoutChildren:(BOOL)optimize
{
	IGNORE_IF_NOT_OPENED
	
	verticalLayoutBoundary = 0.0;
	horizontalLayoutBoundary = 0.0;
	horizontalLayoutRowHeight = 0.0;
	
	if (optimize==NO)
	{
		OSAtomicTestAndSetBarrier(TiRefreshViewChildrenPosition, &dirtyflags);
	}
    
    if (CGSizeEqualToSize([[self view] bounds].size, CGSizeZero)) return;
    
    if (childrenCount > 0)
    {
        //TODO: This is really expensive, but what can you do? Laying out the child needs the lock again.
        NSArray * childrenArray = [[self visibleChildren] retain];
        
        NSUInteger childCount = [childrenArray count];
        if (childCount > 0) {
            NSArray * measuredBounds = [[self measureChildren:childrenArray] retain];
            NSUInteger childIndex;
            for (childIndex = 0; childIndex < childCount; childIndex++) {
                id child = [childrenArray objectAtIndex:childIndex];
                CGRect childSandBox = (CGRect)[(TiRect*)[measuredBounds objectAtIndex:childIndex] rect];
                [self layoutChild:child optimize:optimize withMeasuredBounds:childSandBox];
            }
            [measuredBounds release];
        }
        [childrenArray release];
    }


	
	if (optimize==NO)
	{
		OSAtomicTestAndClearBarrier(TiRefreshViewChildrenPosition, &dirtyflags);
	}
}


-(TiDimension)defaultAutoWidthBehavior:(id)unused
{
    return TiDimensionAutoFill;
}
-(TiDimension)defaultAutoHeightBehavior:(id)unused
{
    return TiDimensionAutoFill;
}

#pragma mark - Accessibility API

- (void)setAccessibilityLabel:(id)accessibilityLabel
{
	ENSURE_UI_THREAD(setAccessibilityLabel, accessibilityLabel);
	if ([self viewAttached]) {
		[[self view] setAccessibilityLabel_:accessibilityLabel];
	}
	[self replaceValue:accessibilityLabel forKey:@"accessibilityLabel" notification:NO];
}

- (void)setAccessibilityValue:(id)accessibilityValue
{
	ENSURE_UI_THREAD(setAccessibilityValue, accessibilityValue);
	if ([self viewAttached]) {
		[[self view] setAccessibilityValue_:accessibilityValue];
	}
	[self replaceValue:accessibilityValue forKey:@"accessibilityValue" notification:NO];
}

- (void)setAccessibilityHint:(id)accessibilityHint
{
	ENSURE_UI_THREAD(setAccessibilityHint, accessibilityHint);
	if ([self viewAttached]) {
		[[self view] setAccessibilityHint_:accessibilityHint];
	}
	[self replaceValue:accessibilityHint forKey:@"accessibilityHint" notification:NO];
}

- (void)setAccessibilityHidden:(id)accessibilityHidden
{
	ENSURE_UI_THREAD(setAccessibilityHidden, accessibilityHidden);
	if ([self viewAttached]) {
		[[self view] setAccessibilityHidden_:accessibilityHidden];
	}
	[self replaceValue:accessibilityHidden forKey:@"accessibilityHidden" notification:NO];
}

#pragma mark - View Templates

+ (TiProxy *)createFromDictionary:(NSDictionary*)dictionary rootProxy:(TiProxy*)rootProxy inContext:(id<TiEvaluator>)context
{
	return [[self class] createFromDictionary:dictionary rootProxy:rootProxy inContext:context defaultType:@"Ti.UI.View"];
}


-(void)hideKeyboard:(id)arg
{
	ENSURE_UI_THREAD_1_ARG(arg);
	if ([self viewAttached])
	{
		[[self view] endEditing:YES];
	}
}

-(void)blur:(id)args
{
	ENSURE_UI_THREAD_1_ARG(args)
	if ([self viewAttached])
	{
		[[self view] endEditing:YES];
	}
}

-(void)focus:(id)args
{
	ENSURE_UI_THREAD_1_ARG(args)
	if ([self viewAttached])
	{
		[[self view] becomeFirstResponder];
	}
}

- (BOOL)focused:(id)unused
{
    return [self focused];
}

-(BOOL)focused
{
	BOOL result=NO;
	if ([self viewAttached])
	{
		result = [[self view] isFirstResponder];
	}
    
	return result;
}


-(void)handlePendingTransition
{
    if (_pendingTransition) {
        id args = _pendingTransition;
        _pendingTransition = nil;
        [self transitionViews:args];
        RELEASE_TO_NIL(args);
    }
}

-(void)transitionViews:(id)args
{
    
	ENSURE_UI_THREAD_1_ARG(args)
    if (_transitioning) {
        _pendingTransition = [args retain];
        return;
    }
    _transitioning = YES;
    if ([args count] > 1) {
        TiViewProxy *view1Proxy = nil;
        TiViewProxy *view2Proxy = nil;
        ENSURE_ARG_OR_NIL_AT_INDEX(view1Proxy, args, 0, TiViewProxy);
        ENSURE_ARG_OR_NIL_AT_INDEX(view2Proxy, args, 1, TiViewProxy);
        if ([self viewAttached])
        {
            if (view1Proxy != nil) {
                pthread_rwlock_wrlock(&childrenLock);
                if (![children containsObject:view1Proxy])
                {
                    pthread_rwlock_unlock(&childrenLock);
                    if (view2Proxy)[self add:view2Proxy];
                    _transitioning = NO;
                    [self handlePendingTransition];
                    return;
                }
            }
            NSDictionary* props = [args count] > 2 ? [args objectAtIndex:2] : nil;
            if (props == nil) {
                DebugLog(@"[WARN] Called transitionViews without transitionStyle");
            }
            pthread_rwlock_unlock(&childrenLock);
            
            TiUIView* view1 = nil;
            __block TiUIView* view2 = nil;
            if (view2Proxy) {
                [view2Proxy performBlockWithoutLayout:^{
                    [view2Proxy setParent:self];
                    view2 = [view2Proxy getAndPrepareViewForOpening];
                }];
                
                id<TiEvaluator> context = self.executionContext;
                if (context == nil) {
                    context = self.pageContext;
                }
                [context.krollContext invokeBlockOnThread:^{
                    [self rememberProxy:view2Proxy];
                    [view2Proxy forgetSelf];
                }];
            }
            if (view1Proxy != nil) {
                view1 = [view1Proxy getAndPrepareViewForOpening];
            }
            
            TiTransition* transition = [TiTransitionHelper transitionFromArg:props containerView:self.view];
            transition.adTransition.type = ADTransitionTypePush;
            [[self view] transitionfromView:view1 toView:view2 withTransition:transition completionBlock:^{
                if (view1Proxy) [self remove:view1Proxy];
                if (view2Proxy) [self add:view2Proxy];
                _transitioning = NO;
                [self handlePendingTransition];
            }];
        }
        else {
            if (view1Proxy) [self remove:view1Proxy];
            if (view2Proxy)[self add:view2Proxy];
            _transitioning = NO;
            [self handlePendingTransition];
        }
	}
}


-(void)blurBackground:(id)args
{
    ENSURE_UI_THREAD_1_ARG(args)
    if ([self viewAttached]) {
        [[self view] blurBackground:args];
    }
}
-(void)configurationStart:(BOOL)recursive
{
    needsContentChange = allowContentChange = NO;
    [view configurationStart];
    if (recursive)[self makeChildrenPerformSelector:@selector(configurationStart:) withObject:recursive];
}

-(void)configurationStart
{
    [self configurationStart:NO];
}

-(void)configurationSet:(BOOL)recursive
{
    [view configurationSet];
    if (recursive)[self makeChildrenPerformSelector:@selector(configurationSet:) withObject:recursive];
    allowContentChange = YES;
}

-(void)configurationSet
{
    [self configurationSet:NO];
}



-(BOOL)containsView:(id)args
{
    ENSURE_SINGLE_ARG(args, TiProxy);
    return [self containsChild:args];
}

-(BOOL)canBeNextResponder
{
    return !hidden && [[self view] interactionEnabled];
}

@end
