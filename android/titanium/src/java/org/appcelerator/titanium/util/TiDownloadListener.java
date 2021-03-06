/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2013 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
package org.appcelerator.titanium.util;

import java.net.HttpURLConnection;
import java.net.URI;

public interface TiDownloadListener
{
	public void downloadTaskFinished(URI uri, HttpURLConnection connection);

	public void downloadTaskFailed(URI uri, HttpURLConnection connection);

	// This method will be called after the download is finished in the
	// same background thread, but BEFORE TaskFinished is called.
	public void postDownload(URI uri, HttpURLConnection connection);
}
