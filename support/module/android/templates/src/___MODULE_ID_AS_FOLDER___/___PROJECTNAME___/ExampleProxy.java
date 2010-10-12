/**
 * This file was auto-generated by the Titanium Module SDK helper for Android
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 *
 */
package __MODULE_ID__.___PROJECTNAME___;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;

import org.appcelerator.titanium.TiContext;
import org.appcelerator.titanium.util.Log;
import org.appcelerator.titanium.util.TiConfig;

// This proxy can be created by calling ___MODULE_NAME_CAMEL___.createExample({message: "hello world"})
@Kroll.proxy(creatableInModule=___MODULE_NAME_CAMEL___Module.class)
public class ExampleProxy extends KrollProxy
{
	// Standard Debugging variables
	private static final String LCAT = "ExampleProxy";
	private static final boolean DBG = TiConfig.LOGD;
	
	// Constructor
	public ExampleProxy(TiContext tiContext) {
		super(tiContext);
	}
	
	// Handle creation options
	@Override
	public void handleCreationDict(KrollDict options) {
		super.handleCreationDict(options);
		
		if (options.containsKey("message")) {
			Log.d(LCAT, "example created with message: " + options.get("message"));
		}
	}
	
	// Methods
	
	@Kroll.method
	public void printMessage(String message) {
		Log.d(LCAT, "printing message: " + message);
	}
}