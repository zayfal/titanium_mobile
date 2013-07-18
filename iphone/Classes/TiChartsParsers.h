/**
 * Ti.Charts Module
 * Copyright (c) 2011-2013 by Appcelerator, Inc. All Rights Reserved.
 * Please see the LICENSE included with this distribution for details.
 */

#import "CorePlot-CocoaTouch.h"


@interface TiChartsParsers : NSObject {
}

+(CPTColor*)parseColor:(id)color def:(CPTColor*)def;
+(CPTMutableTextStyle*)parseTextStyle:(NSDictionary*)properties def:(CPTTextStyle*)def;
+(CPTLineStyle*)parseLineColor:(id)color withWidth:(id)width withGradient:(id)gradient andOpacity:(id)opacity def:(CPTLineStyle*)def;
+(CPTLineStyle*)parseLine:(id)object withPrefix:(id)prefix def:(CPTLineStyle*)def;
+(CPTFill*)parseFillColor:(id)color withGradient:(id)gradientProps andOpacity:(id)opacity def:(CPTFill*)def;
+(CPTPlotSymbol*)parseSymbol:(NSDictionary*)properties def:(CPTPlotSymbol*)def;
+(NSDecimal)decimalFromFloat:(id)value def:(NSDecimal)def;
+(void)parseLabelStyle:(NSDictionary*)properties forPlot:(CPTPlot*)plot def:(CPTTextStyle*)def;
+(CPTXYAxis*)parseAxis:(CPTCoordinate)coordinate properties:(NSDictionary*)properties usingPlotSpace:(CPTPlotSpace*)plotSpace def:(CPTXYAxis*)def;
+(CPTPlotRange*)parsePlotRange:(NSDictionary*)properties def:(CPTPlotRange*)def;

+(CPTShadow*)parseShadow:(NSString*) property inProperties:(id)properties def:(CPTShadow*)def;
+(CPTShadow*)parseShadow:(NSDictionary*)properties def:(CPTShadow*)def;

@end
