/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#if defined(USE_TI_XML) || defined(USE_TI_NETWORK)

#import "TiDOMElementProxy.h"
#import "TiDOMNodeProxy.h"
#import "TiDOMNodeListProxy.h"
#import "TiDOMAttrProxy.h"
#import "TiUtils.h"

@implementation TiDOMElementProxy

-(void)dealloc
{
	RELEASE_TO_NIL(element);
	[super dealloc];
}

-(void)setElement:(GDataXMLElement*)element_
{
	RELEASE_TO_NIL(element);
	element = [element_ retain];
	[self setNode:element];
}

-(id)getElementsByTagName:(id)args
{
	ENSURE_SINGLE_ARG(args,NSString);
	NSError *error = nil;
	NSString *xpath = [NSString stringWithFormat:@"self::node()/descendant::*[local-name()='%@']",args];
	// see if it's a namespace
	NSRange range = [args rangeOfString:@":"];
	if (range.location!=NSNotFound)
	{
		xpath = [NSString stringWithFormat:@"self::node()/descendant::*[name()='%@']",args];
	}
	NSArray *nodes = [element nodesForXPath:xpath error:&error];
	if (error==nil && nodes!=nil && [nodes count]>0)
	{
		TiDOMNodeListProxy *proxy = [[[TiDOMNodeListProxy alloc] _initWithPageContext:[self pageContext]] autorelease];
		[proxy setNodes:nodes];
		[proxy setDocument:[self document]];
		return proxy;
	}
	if (error!=nil)
	{
		[self throwException:[error description] subreason:nil location:CODELOCATION];
	}
	return nil;
}

-(id)evaluate:(id)args
{
	ENSURE_SINGLE_ARG(args,NSString);
	NSError *error = nil;
	NSArray *nodes = [element nodesForXPath:args error:&error];
	if (error==nil && nodes!=nil && [nodes count]>0)
	{
		TiDOMNodeListProxy *proxy = [[[TiDOMNodeListProxy alloc] _initWithPageContext:[self pageContext]] autorelease];
		[proxy setNodes:nodes];
		[proxy setDocument:[self document]];
		return proxy;
	}
	return nil;
}

-(id)tagName
{
	return [element name];
}

-(id)nodeValue
{
	// DOM spec says nodeValue for element must return null
	return [NSNull null];
}

-(id)getAttribute:(id)args
{
	ENSURE_SINGLE_ARG(args,NSString);
	GDataXMLNode *_node = [element attributeForName:args];
	if (_node!=nil)
	{
		return [_node stringValue];
	}
	return @"";
}

-(void)setAttribute:(id)args
{
	ENSURE_ARG_COUNT(args, 2);

	NSString *name = [args objectAtIndex:0];
	ENSURE_STRING_OR_NIL(name);

	NSString *val = [args objectAtIndex:1];
	ENSURE_STRING_OR_NIL(val);

	if (name != nil && val != nil)
	{
		[element addAttribute: [GDataXMLNode attributeWithName: name stringValue: val]];
	}
}

-(void)removeAttribute:(id)args
{
	ENSURE_SINGLE_ARG(args, NSString);
	
	GDataXMLNode * attributeNode = [element attributeForName:args];
	[element removeChild:attributeNode];
}

-(id)getAttributeNode:(id)args
{
	ENSURE_SINGLE_ARG(args, NSString);
	GDataXMLNode * attributeNode = [element attributeForName:args];
	if (attributeNode == nil) {
		return [NSNull null];
	}
	TiDOMAttrProxy * result = [[[TiDOMAttrProxy alloc] _initWithPageContext:[self pageContext]] autorelease];
	[result setAttribute:args value:[attributeNode stringValue] owner:element];
	[result setDocument:[self document]];
	return result;
}

-(id)insertBefore:(id)args
{
	[self throwException:@"mutation not supported" subreason:nil location:CODELOCATION];
}

-(id)replaceChild:(id)args
{
	[self throwException:@"mutation not supported" subreason:nil location:CODELOCATION];
}

-(id)removeChild:(id)args
{
	ENSURE_ARG_COUNT(args, 1);
	TiDOMNodeProxy * oldChild;
	ENSURE_ARG_AT_INDEX(oldChild, args, 0, TiDOMNodeProxy);
	[element removeChild:[oldChild node]];
	return oldChild;
}

-(id)appendChild:(id)args
{
	ENSURE_ARG_COUNT(args, 1);
	TiDOMNodeProxy * newChild;
	ENSURE_ARG_AT_INDEX(newChild, args, 0, TiDOMNodeProxy);
	[element addChild:[newChild node]];
	return newChild;
}

-(void)setAttributeNode:(id)args
{
	//TODO:
}

-(void)removeAttributeNode:(id)args
{
	//TODO:
}

-(id)getAttributeNS:(id)args
{
	//TODO:
	return nil;
}

-(void)setAttributeNS:(id)args
{
	//TODO:
}

-(void)removeAttributeNS:(id)args
{
	//TODO:
}

-(id)getAttributeNodeNS:(id)args
{
	//TODO:
	return nil;
}

-(void)setAttributeNodeNS:(id)args
{
	//TODO:
}

-(id)getElementsByTagNameNS:(id)args
{
	//TODO:
	return nil;
}

-(id)hasAttribute:(id)args
{
	return NUMBOOL([self hasAttribute:args]!=nil);
}

-(id)hasAttributeNS:(id)args
{
	//TODO:
	return NUMBOOL(NO);
}

@end

#endif