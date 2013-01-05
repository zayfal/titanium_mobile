/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#ifdef USE_TI_UILABEL

#import "TiUILabel.h"
#import "TiUILabelProxy.h"
#import "TiUtils.h"
#import "UIImage+Resize.h"
#import "DTCoreText.h"

#define kDefaultFontSize 12.0

static inline CTTextAlignment UITextAlignmentToCTTextAlignment(UITextAlignment alignment)
{
    switch (alignment) {
        case UITextAlignmentLeft:
            return kCTLeftTextAlignment;
        case UITextAlignmentRight:
            return kCTRightTextAlignment;
        default:
            return kCTCenterTextAlignment;
            break;
    }
}

static inline CTLineBreakMode UILineBreakModeToCTLineBreakMode(UILineBreakMode linebreak)
{
    switch (linebreak) {
        case UILineBreakModeClip:
            return kCTLineBreakByClipping;
        case UILineBreakModeCharacterWrap:
            return kCTLineBreakByCharWrapping;
        case UILineBreakModeHeadTruncation:
            return kCTLineBreakByTruncatingHead;
        case UILineBreakModeTailTruncation:
            return kCTLineBreakByTruncatingTail;
        case UILineBreakModeMiddleTruncation:
            return kCTLineBreakByTruncatingMiddle;
        case UILineBreakModeWordWrap:
        default:
            return kCTLineBreakByWordWrapping;
            break;
    }
}

@implementation TiUILabel

#pragma mark Internal

-(id)init
{
    if (self = [super init]) {
        options = [[NSMutableDictionary dictionary] retain];
        padding = CGRectZero;
        textPadding = CGRectZero;
        initialLabelFrame = CGRectZero;
        webFont = [[WebFont defaultFont] retain];
        webFont.size = 17; //to get the same default font size as UILabel
    }
    return self;
}

-(void)dealloc
{
    RELEASE_TO_NIL(label);
    RELEASE_TO_NIL(options);
    RELEASE_TO_NIL(content);
    RELEASE_TO_NIL(webFont);
    [super dealloc];
}

- (BOOL)interactionDefault
{
	// by default, labels don't have any interaction unless you explicitly add
	// it via addEventListener
	return NO;
}


- (CGSize)suggestedFrameSizeToFitEntireStringConstraintedToWidth:(CGFloat)suggestedWidth
{
    CGSize maxSize = CGSizeMake(suggestedWidth<=0 ? 480 : suggestedWidth, 10000);
    CGFloat textWidth = [[self label] sizeThatFits:maxSize].width;
    textWidth = MIN(textWidth,  maxSize.width);
    CGRect textRect = [[self label] textRectForBounds:CGRectMake(0,0,textWidth, maxSize.height) limitedToNumberOfLines:label.numberOfLines];
    textRect.size.height -= textRect.origin.y;
    textRect.size.width += textPadding.origin.x + textPadding.size.width;
    textRect.size.height += textPadding.origin.y + textPadding.size.height;
    return textRect.size;
}

-(CGFloat)contentWidthForWidth:(CGFloat)suggestedWidth
{
    return [self suggestedFrameSizeToFitEntireStringConstraintedToWidth:suggestedWidth].width;
}

-(CGFloat)contentHeightForWidth:(CGFloat)width
{
    return [self suggestedFrameSizeToFitEntireStringConstraintedToWidth:width].height;
}

-(void)padLabel
{
	CGRect	initFrame = CGRectMake(initialLabelFrame.origin.x + textPadding.origin.x
                                   , initialLabelFrame.origin.y + textPadding.origin.y
                                   , initialLabelFrame.size.width - textPadding.origin.x - textPadding.size.width
                                   , initialLabelFrame.size.height - textPadding.origin.y - textPadding.size.height);
    [label setFrame:initFrame];
    
    if ([self backgroundImageLayer] != nil && !CGRectIsEmpty(initialLabelFrame))
    {
        [self updateBackgroundImageFrameWithPadding];
    }
	[(TiViewProxy *)[self proxy] contentsWillChange];
	return;
}

-(void)setCenter:(CGPoint)newCenter
{
	[super setCenter:CGPointMake(floorf(newCenter.x), floorf(newCenter.y))];
}

-(void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
	initialLabelFrame = bounds;
    
    [self padLabel];
    
    [super frameSizeChanged:frame bounds:bounds];
}


- (void)configurationSet {
    [super configurationSet];
    configSet = YES;
    [self setAttributedTextViewContent];
}

-(TTTAttributedLabel*)label
{
	if (label==nil)
	{
        _multilineBreakMode = UILineBreakModeWordWrap;
        label = [[TTTAttributedLabel alloc] initWithFrame:CGRectZero];
        label.backgroundColor = [UIColor clearColor];
        label.numberOfLines = 0;//default wordWrap to True
        label.lineBreakMode = UILineBreakModeWordWrap; //default ellipsis to none
        label.layer.shadowRadius = 0; //for backward compatibility
        label.layer.shadowOffset = CGSizeZero;
        label.delegate = self;
        [self addSubview:label];
	}
	return label;
}

- (id)accessibilityElement
{
	return [self label];
}

- (void)setAttributedTextViewContent {
    if (!configSet) return; // lazy init
    
    if (content == nil) {
        [[self label] setText:nil];
        [(TiViewProxy *)[self proxy] contentsWillChange];
        return;
    }
    
    switch (contentType) {
        case kContentTypeHTML:
        {
            //we need to set default values
            [options setValue:self.label.textColor forKey:DTDefaultTextColor];
            [options setValue:self.label.textColor forKey:DTDefaultLinkColor];
            [options setValue:[NSNumber numberWithInt:UITextAlignmentToCTTextAlignment(self.label.textAlignment)] forKey:DTDefaultTextAlignment];

            [options setValue:[NSNumber numberWithInt:UILineBreakModeToCTLineBreakMode(_multilineBreakMode)]  forKey:DTDefaultLineBreakMode];
            
            int traitsDefault = 0;
            if (webFont.isItalicStyle)
                traitsDefault |= kCTFontItalicTrait;
            if (webFont.isBoldWeight)
                traitsDefault |= kCTFontBoldTrait;
            [options setValue:[NSNumber numberWithInt:traitsDefault] forKey:DTDefaultFontStyle];

            [options setValue:[NSNumber numberWithFloat:(webFont.size / kDefaultFontSize)] forKey:NSTextSizeMultiplierDocumentOption];
            
            NSAttributedString * astr = [[NSAttributedString alloc] initWithHTMLData:[content dataUsingEncoding:NSUTF8StringEncoding] options:options documentAttributes:nil];
            [[self label] setText:astr];
            break;
        }
        default:
        {
            [[self label] setText:content];
            break;
        }
    }
    [(TiViewProxy *)[self proxy] contentsWillChange];
}

-(void)setHighlighted:(BOOL)newValue
{
    [[self label] setHighlighted:newValue];
}

- (void)didMoveToSuperview
{
	[self setHighlighted:NO];
	[super didMoveToSuperview];
}

-(BOOL)isHighlighted
{
    return [[self label] isHighlighted];
}

#pragma mark Public APIs

-(void)setVerticalAlign_:(id)value
{
    UIControlContentVerticalAlignment verticalAlign = [TiUtils contentVerticalAlignmentValue:value];
    
    [[self label] setVerticalAlignment:(TTTAttributedLabelVerticalAlignment)verticalAlign];
}
-(void)setText_:(id)text
{
    ENSURE_STRING_OR_NIL(text)
    RELEASE_TO_NIL(content)
    contentType = kContentTypeText;
    content = [text retain];
    [self setAttributedTextViewContent];
}


- (void)setHtml_:(id)html {
    ENSURE_STRING_OR_NIL(html)
    RELEASE_TO_NIL(content)
    contentType = kContentTypeHTML;
    content = [html retain];
    [self setAttributedTextViewContent];
}

-(void)setAutoLink_:(id)value
{
    [[self label] setDataDetectorTypes:[TiUtils intValue:value]];
    //we need to update the text
    [self setAttributedTextViewContent];
}

-(void)setColor_:(id)color
{
	UIColor * newColor = [[TiUtils colorValue:color] _color];
	[[self label] setTextColor:(newColor != nil)?newColor:[UIColor darkTextColor]];
    
    //we need to reset the text to update default paragraph settings
    [self setAttributedTextViewContent];
}

-(void)setHighlightedColor_:(id)color
{
	UIColor * newColor = [[TiUtils colorValue:color] _color];
	[[self label] setHighlightedTextColor:(newColor != nil)?newColor:[UIColor lightTextColor]];
    
    //we need to reset the text to update default paragraph settings
    [self setAttributedTextViewContent];
}

-(void)setFont_:(id)font
{
    RELEASE_TO_NIL(content);
    webFont =[[TiUtils fontValue:font] retain];
	[[self label] setFont:[webFont font]];
    
    //we need to reset the text to update default paragraph settings
    [self setAttributedTextViewContent];
}

-(void)setMinimumFontSize_:(id)size
{
    CGFloat newSize = [TiUtils floatValue:size];
    if (newSize < 4) { // Beholden to 'most minimum' font size
        [[self label] setAdjustsFontSizeToFitWidth:NO];
        [[self label] setMinimumFontSize:0.0];
    }
    else {
        [[self label] setAdjustsFontSizeToFitWidth:YES];
        [[self label] setMinimumFontSize:newSize];
    }
    [self updateNumberLines];   
}

-(void)setBackgroundImageLayerBounds:(CGRect)bounds
{
    if ([self backgroundImageLayer] != nil)
    {
        CGRect backgroundFrame = CGRectMake(bounds.origin.x - padding.origin.x,
                                            bounds.origin.y - padding.origin.y,
                                            bounds.size.width + padding.origin.x + padding.size.width,
                                            bounds.size.height + padding.origin.y + padding.size.height);
        [self backgroundImageLayer].frame = backgroundFrame;
    }
}

-(void) updateBackgroundImageFrameWithPadding
{
    [self setBackgroundImageLayerBounds:self.bounds];
}

-(void)setBackgroundImage_:(id)url
{
    [super setBackgroundImage_:url];
    //if using padding we must not mask to bounds.
    [self backgroundImageLayer].masksToBounds = CGRectEqualToRect(padding, CGRectZero) ;
    [self updateBackgroundImageFrameWithPadding];
}

-(void)setBackgroundPaddingLeft_:(id)left
{
    padding.origin.x = [TiUtils floatValue:left];
    [self updateBackgroundImageFrameWithPadding];
}

-(void)setBackgroundPaddingRight_:(id)right
{
    padding.size.width = [TiUtils floatValue:right];
    [self updateBackgroundImageFrameWithPadding];
}

-(void)setBackgroundPaddingTop_:(id)top
{
    padding.origin.y = [TiUtils floatValue:top];
    [self updateBackgroundImageFrameWithPadding];
}

-(void)setBackgroundPaddingBottom_:(id)bottom
{
    padding.size.height = [TiUtils floatValue:bottom];
    [self updateBackgroundImageFrameWithPadding];
}

-(void)setTextAlign_:(id)alignment
{
	[[self label] setTextAlignment:[TiUtils textAlignmentValue:alignment]];
    
    //we need to reset the text to update default paragraph settings
    [self setAttributedTextViewContent];
}

-(void)setShadowColor_:(id)color
{
	if (color==nil)
	{
		[[[self label] layer]setShadowColor:nil];
	}
	else
	{
		color = [TiUtils colorValue:color];
		[[self label] setShadowColor:[color _color]];
	}
}

-(void)setShadowRadius_:(id)arg
{
    [[self label] setShadowRadius:[TiUtils floatValue:arg]];
}
-(void)setShadowOffset_:(id)value
{
	CGPoint p = [TiUtils pointValue:value];
	CGSize size = {p.x,p.y};
	[[self label] setShadowOffset:size];
}

-(void)setTextPaddingLeft_:(id)left
{
    textPadding.origin.x = [TiUtils floatValue:left];
    [self padLabel];
}

-(void)setTextPaddingRight_:(id)right
{
    textPadding.size.width = [TiUtils floatValue:right];
    [self padLabel];
}

-(void)setTextPaddingTop_:(id)top
{
    textPadding.origin.y = [TiUtils floatValue:top];
    [self padLabel];
}

-(void)setTextPaddingBottom_:(id)bottom
{
    textPadding.size.height = [TiUtils floatValue:bottom];
    [self padLabel];
}

-(void) updateNumberLines
{
    if ([[self label] minimumFontSize] >= 4.0)
    {
        [[self label] setNumberOfLines:1];
    }
    else if ([[self proxy] valueForKey:@"maxLines"])
        [[self label] setNumberOfLines:([[[self proxy] valueForKey:@"maxLines"] integerValue])];
    else
    {
        BOOL shouldWordWrap = [TiUtils boolValue:[[self proxy] valueForKey:@"wordWrap"] def:YES];
        if (shouldWordWrap)
        {
            [[self label] setNumberOfLines:0];
        }
        else
        {
            [[self label] setNumberOfLines:1];
        }
    }

    [self setAttributedTextViewContent];
}

-(void)setWordWrap_:(id)value
{
    [self updateNumberLines];
}

-(void)setMaxLines_:(id)value
{
	[self updateNumberLines];
}

-(void)setEllipsize_:(id)value
{
    [[self label] setLineBreakMode:[TiUtils intValue:value]];
    //we need to update the text
    [self setAttributedTextViewContent];
}


-(void)setMultiLineEllipsize_:(id)value
{
    _multilineBreakMode = [TiUtils intValue:value];
    if (_multilineBreakMode != UILineBreakModeWordWrap)
        [[self label] setLineBreakMode:UILineBreakModeWordWrap];

    //we need to update the text
    [self setAttributedTextViewContent];
}


#pragma mark -
#pragma mark DTAttributedTextContentViewDelegate

- (void)attributedLabel:(TTTAttributedLabel *)label
   didSelectLinkWithURL:(NSURL *)url
{
    [[UIApplication sharedApplication] openURL:url];
}

- (void)attributedLabel:(TTTAttributedLabel *)label
didSelectLinkWithAddress:(NSDictionary *)addressComponents
{
    NSMutableString* address = [NSMutableString string];
    NSString* temp = nil;
    if((temp = [addressComponents objectForKey:NSTextCheckingStreetKey]))
        [address appendString:temp];
    if((temp = [addressComponents objectForKey:NSTextCheckingCityKey]))
        [address appendString:[NSString stringWithFormat:@"%@%@", ([address length] > 0) ? @", " : @"", temp]];
    if((temp = [addressComponents objectForKey:NSTextCheckingStateKey]))
        [address appendString:[NSString stringWithFormat:@"%@%@", ([address length] > 0) ? @", " : @"", temp]];
    if((temp = [addressComponents objectForKey:NSTextCheckingZIPKey]))
        [address appendString:[NSString stringWithFormat:@" %@", temp]];
    if((temp = [addressComponents objectForKey:NSTextCheckingCountryKey]))
        [address appendString:[NSString stringWithFormat:@"%@%@", ([address length] > 0) ? @", " : @"", temp]];
    NSString* urlString = [NSString stringWithFormat:@"http://maps.google.com/maps?q=%@", [address stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]];
}

- (void)attributedLabel:(TTTAttributedLabel *)label
didSelectLinkWithPhoneNumber:(NSString *)phoneNumber
{
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", phoneNumber]];
    [[UIApplication sharedApplication] openURL:url];
}

//- (void)attributedLabel:(TTTAttributedLabel *)label
//  didSelectLinkWithDate:(NSDate *)date
//{
//    [[UIApplication sharedApplication] openURL:url];
//}
//
//- (void)attributedLabel:(TTTAttributedLabel *)label
//  didSelectLinkWithDate:(NSDate *)date
//               timeZone:(NSTimeZone *)timeZone
//               duration:(NSTimeInterval)duration
//{
//    [[UIApplication sharedApplication] openURL:url];
//}

@end

#endif
