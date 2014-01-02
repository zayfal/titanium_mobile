/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#import "TiUIWindow.h"
#import "TiUIWindowProxy.h"

@implementation TiUIWindow

- (void) dealloc
{
	[super dealloc];
}

//-(void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
//{
//    [super frameSizeChanged:frame bounds:bounds];
//    
//    //Need the delay so that we get the right navbar bounds
//    TiProxy* windowProxy = [self proxy];
//    if ([windowProxy respondsToSelector:@selector(willChangeSize)]) {
//        [(id)windowProxy willChangeSize];
//    }
//    if ([windowProxy respondsToSelector:@selector(updateNavBar)]) {
//        [windowProxy performSelector:@selector(updateNavBar) 
//                           withObject:nil 
//                           afterDelay:[[UIApplication sharedApplication] statusBarOrientationAnimationDuration] ];
//    }
//}

-(void)setFrame:(CGRect)frame
{
	// this happens when a controller resizes its view
	if ([self.proxy isKindOfClass:[TiWindowProxy class]])
	{
        CGRect currentframe = [self frame];
        if (!CGRectIsEmpty(frame) && !CGRectEqualToRect(frame, currentframe))
        {
            CGRect bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
            [(TiWindowProxy*)self.proxy setSandboxBounds:bounds];
            [(TiWindowProxy*)self.proxy relayout];
            [(TiWindowProxy*)self.proxy layoutChildren:NO];
        }
	}
    else {
        [super setFrame:frame];
    }
}

@end

