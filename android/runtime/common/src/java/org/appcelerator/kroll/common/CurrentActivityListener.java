/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2011 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
package org.appcelerator.kroll.common;

import android.app.Activity;

/**
 * This interface invokes a callback function when the current activity becomes visible.
 */
public interface CurrentActivityListener
{
	/**
	 * Implementing classes should override this method to run code after the current activity has become visible.
	 * Refer to {@link TiUIHelper#waitForCurrentActivity(CurrentActivityListener)} for an example use case.
	 * @param activity the associated activity.
	 */
	public void onCurrentActivityReady(Activity activity);
}
