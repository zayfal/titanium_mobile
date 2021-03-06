/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#ifdef USE_TI_UISLIDER

#import "TiUISliderProxy.h"

NSArray* sliderKeySequence;

@implementation TiUISliderProxy

+(NSSet*)transferableProperties
{
    NSSet *common = [TiViewProxy transferableProperties];
    return [common setByAddingObjectsFromSet:[NSSet setWithObjects:@"min",
                                              @"max",@"value",@"enabled",@"leftTrackLeftCap",
                                              @"leftTrackTopCap",@"rightTrackLeftCap",
                                              @"rightTrackTopCap", @"thumbImage",
                                              @"selectedThumbImage",@"highlightedThumbImage",
                                              @"disabledThumbImage", @"leftTrackImage",
                                              @"selectedLeftTrackImage",@"highlightedLeftTrackImage",
                                              @"disabledLeftTrackImage", @"rightTrackImage",
                                              @"selectedRightTrackImage",@"highlightedRightTrackImage",
                                              @"disabledRightTrackImage", nil]];
}

-(NSArray *)keySequence
{
	if (sliderKeySequence == nil)
	{
		sliderKeySequence = [[[super keySequence] arrayByAddingObjectsFromArray:@[@"min",@"max",@"value",@"leftTrackLeftCap",@"leftTrackTopCap",@"rightTrackLeftCap",@"rightTrackTopCap",
                              @"leftTrackImage",@"selectedLeftTrackImage", @"highlightedLeftTrackImage", @"disabledLeftTrackImage",
                              @"rightTrackImage",@"selectedRightTrackImage", @"highlightedRightTrackImage", @"disabledRightTrackImage"]] retain];
	}
	return sliderKeySequence;
}

-(NSString*)apiName
{
    return @"Ti.UI.Slider";
}

-(void)_initWithProperties:(NSDictionary *)properties
{
    [self initializeProperty:@"leftTrackLeftCap" defaultValue:NUMFLOAT(1.0)];
    [self initializeProperty:@"leftTrackTopCap" defaultValue:NUMFLOAT(1.0)];
    [self initializeProperty:@"rightTrackLeftCap" defaultValue:NUMFLOAT(1.0)];
    [self initializeProperty:@"rightTrackTopCap" defaultValue:NUMFLOAT(1.0)];
    [super _initWithProperties:properties];
}


-(UIViewAutoresizing)verifyAutoresizing:(UIViewAutoresizing)suggestedResizing
{
	return suggestedResizing & ~UIViewAutoresizingFlexibleHeight;
}

-(TiDimension)defaultAutoHeightBehavior:(id)unused
{
    return TiDimensionAutoSize;
}


USE_VIEW_FOR_VERIFY_HEIGHT

@end

#endif