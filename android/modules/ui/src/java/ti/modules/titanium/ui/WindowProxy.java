/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2013 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

package ti.modules.titanium.ui;

import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.TiActivity;
import org.appcelerator.titanium.TiActivityWindow;
import org.appcelerator.titanium.TiActivityWindows;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.TiBaseActivity;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.TiDimension;
import org.appcelerator.titanium.TiTranslucentActivity;
import org.appcelerator.titanium.animation.TiAnimator;
import org.appcelerator.titanium.proxy.ActivityProxy;
import org.appcelerator.titanium.proxy.DecorViewProxy;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.proxy.TiWindowProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiCompositeLayout;
import org.appcelerator.titanium.util.TiRHelper;
import org.appcelerator.titanium.view.TiUIView;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.os.Message;
import android.view.View;
import android.view.ViewGroup.LayoutParams;
import android.view.Window;
import android.view.WindowManager;

@Kroll.proxy(creatableInModule=UIModule.class, propertyAccessors={
	TiC.PROPERTY_MODAL,
	TiC.PROPERTY_ACTIVITY,
	TiC.PROPERTY_URL,
	TiC.PROPERTY_WINDOW_PIXEL_FORMAT,
	TiC.PROPERTY_FLAG_SECURE
})
public class WindowProxy extends TiWindowProxy implements TiActivityWindow
{
	private static final String TAG = "WindowProxy";
	protected static final String PROPERTY_POST_WINDOW_CREATED = "postWindowCreated";
	private static final String PROPERTY_LOAD_URL = "loadUrl";

	private static final int MSG_FIRST_ID = TiViewProxy.MSG_LAST_ID + 1;
	private static final int MSG_SET_PIXEL_FORMAT = MSG_FIRST_ID + 100;
	private static final int MSG_SET_TITLE = MSG_FIRST_ID + 101;
	private static final int MSG_SET_WIDTH_HEIGHT = MSG_FIRST_ID + 102;
	private static final int MSG_REMOVE_LIGHTWEIGHT = MSG_FIRST_ID + 103;
	protected static final int MSG_LAST_ID = MSG_FIRST_ID + 999;

	protected WeakReference<TiBaseActivity> windowActivity;

	// This flag is just for a temporary use. We won't need it after the lightweight window
	// is completely removed.
	private boolean lightweight = false;

	public WindowProxy()
	{
		super();
		defaultValues.put(TiC.PROPERTY_WINDOW_PIXEL_FORMAT, PixelFormat.UNKNOWN);
	}

	@Override
	protected KrollDict getLangConversionTable()
	{
		KrollDict table = new KrollDict();
		table.put(TiC.PROPERTY_TITLE, TiC.PROPERTY_TITLEID);
		return table;
	}
	
	private class TiWindowView extends TiUIView{
		public TiWindowView(TiViewProxy proxy) {
			super(proxy);
			layoutParams.autoFillsHeight = true;
			layoutParams.autoFillsWidth = true;
			TiCompositeLayout layout = new TiCompositeLayout(proxy.getActivity(), this);
			setNativeView(layout);
		}
	}
	 
	
	@Override
	public TiUIView createView(Activity activity)
	{
		TiUIView v = new TiWindowView(this);
		setView(v);
		return v;
	}

	public void addLightweightWindowToStack() 
	{
		// Add LW window to the decor view and add it to stack.
		Activity topActivity = TiApplication.getAppCurrentActivity();
		if (topActivity instanceof TiBaseActivity) {
			TiBaseActivity baseActivity = (TiBaseActivity) topActivity;
			ActivityProxy activityProxy = baseActivity.getActivityProxy();
			if (activityProxy != null) {
				DecorViewProxy decorView = activityProxy.getDecorView();
				if (decorView != null) {
					decorView.add(this);
					windowActivity = new WeakReference<TiBaseActivity>(baseActivity);

					// Need to handle the url window in the JS side.
					callPropertySync(PROPERTY_LOAD_URL, null);

					opened = true;
					// fireEvent(TiC.EVENT_OPEN, null);

					baseActivity.addWindowToStack(this);
					return;
				}
			}
		}
		Log.e(TAG, "Unable to open the lightweight window because the current activity is not available.");
	}

	public void removeLightweightWindowFromStack()
	{
		// Remove LW window from decor view and remove it from stack
		TiBaseActivity activity = (windowActivity != null) ? windowActivity.get() : null;
		if (activity != null) {
			ActivityProxy activityProxy = activity.getActivityProxy();
			closeFromActivity(true);
			if (activityProxy != null) {
				activityProxy.getDecorView().remove(this);
			}
			activity.removeWindowFromStack(this);
			
		}
	}

	@Override
	public void open(@Kroll.argument(optional = true) Object arg)
	{
		HashMap<String, Object> option = null;
		if (arg instanceof HashMap) {
			option = (HashMap<String, Object>) arg;
		}
		if (option != null) {
		    KrollDict props = new KrollDict(option);
		    Set<String> propsToKeep = new HashSet<String>();
            propsToKeep.add(TiC.PROPERTY_FULLSCREEN);
            propsToKeep.add(TiC.PROPERTY_ORIENTATION_MODES);
            propsToKeep.add(TiC.PROPERTY_LIGHTWEIGHT);
            propsToKeep.add(TiC.PROPERTY_MODAL);
            propsToKeep.add(TiC.PROPERTY_NAV_BAR_HIDDEN);
            propsToKeep.add(TiC.PROPERTY_WINDOW_SOFT_INPUT_MODE);
            props.keySet().retainAll(propsToKeep);
			properties.putAll(props);
		}

		if (hasProperty(TiC.PROPERTY_ORIENTATION_MODES)) {
			Object obj = getProperty(TiC.PROPERTY_ORIENTATION_MODES);
			if (obj instanceof Object[]) {
				orientationModes = TiConvert.toIntArray((Object[]) obj);
			}
		}

		if (hasProperty(TiC.PROPERTY_LIGHTWEIGHT))
		{
			lightweight = TiConvert.toBoolean(getProperty(TiC.PROPERTY_LIGHTWEIGHT), false);
		}

		// When we open a window using tab.open(win), we treat it as opening a HW window on top of the tab.
		if (hasProperty("tabOpen")) {
			lightweight = false;

		// If "ti.android.useLegacyWindow" is set to true in the tiapp.xml, follow the old window behavior:
		// create a HW window if any of the four properties, "fullscreen", "navBarHidden", "windowSoftInputMode" and
		// "modal", is specified; otherwise create a LW window.
		} else if (TiApplication.USE_LEGACY_WINDOW && !hasProperty(TiC.PROPERTY_FULLSCREEN)
			&& !hasProperty(TiC.PROPERTY_NAV_BAR_HIDDEN) && !hasProperty(TiC.PROPERTY_WINDOW_SOFT_INPUT_MODE)
			&& !hasProperty(TiC.PROPERTY_MODAL)) {
			lightweight = true;
		}

		if (Log.isDebugModeEnabled()) {
			Log.d(TAG, "open the window: lightweight = " + lightweight, Log.DEBUG_MODE);
		}

		if (lightweight) {
			addLightweightWindowToStack();
		} else {
			// The "top", "bottom", "left" and "right" properties do not work for heavyweight windows.
//			properties.remove(TiC.PROPERTY_TOP);
//			properties.remove(TiC.PROPERTY_BOTTOM);
//			properties.remove(TiC.PROPERTY_LEFT);
//			properties.remove(TiC.PROPERTY_RIGHT);
			super.open(arg);
		}
	}
	
	@Override
	public void close(@Kroll.argument(optional = true) Object arg)
	{
		if (!(opened || opening)) {
			return;
		}
		if (lightweight) {
			if (TiApplication.isUIThread()) {
				removeLightweightWindowFromStack();
			} else {
				getMainHandler().obtainMessage(MSG_REMOVE_LIGHTWEIGHT).sendToTarget();
			}
		} else {
			super.close(arg);
		}
	}

	@Override
	protected void handleOpen(KrollDict options)
	{
		Activity topActivity = TiApplication.getAppCurrentActivity();
		//null can happen when app is closed as soon as it is opened
		if (topActivity == null) return;
		
		Intent intent = new Intent(topActivity, TiActivity.class);
		fillIntent(topActivity, intent);

		int windowId = TiActivityWindows.addWindow(this);
		intent.putExtra(TiC.INTENT_PROPERTY_USE_ACTIVITY_WINDOW, true);
		intent.putExtra(TiC.INTENT_PROPERTY_WINDOW_ID, windowId);
		
        int enterAnimation = TiConvert.toInt(options, TiC.PROPERTY_ACTIVITY_ENTER_ANIMATION, -1);
        int exitAnimation = TiConvert.toInt(options, TiC.PROPERTY_ACTIVITY_EXIT_ANIMATION, -1);
        
        boolean animated = TiConvert.toBoolean(options, TiC.PROPERTY_ANIMATED, true);
        if (options.containsKey("_anim")) {
            animated = false;
            animateInternal(options.get("_anim"), null);
        }
		if (!animated) {
			intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
			enterAnimation = 0;
            exitAnimation = 0;
		}
		
        topActivity.startActivity(intent);
        if (enterAnimation != -1 || exitAnimation != -1) {
            topActivity.overridePendingTransition(enterAnimation, exitAnimation);
        }
	}
	
	private TiAnimator _closingAnim;
    @Override
    public void animationFinished(TiAnimator animation) {
        super.animationFinished(animation);
        if (_closingAnim == animation) {
            TiBaseActivity activity = (windowActivity != null) ? windowActivity.get() : null;
            if (activity != null && !activity.isFinishing()) {
                activity.finish();
                activity.overridePendingTransition(0, 0);
             // Finishing an activity is not synchronous, so we remove the activity from the activity stack here
                TiApplication.removeFromActivityStack(activity);
                windowActivity = null;
            }
        }
    }

	@Override
	protected void handleClose(KrollDict options)
	{
        TiBaseActivity activity = (windowActivity != null) ? windowActivity.get() : null;
		if (activity == null) {
			//we must have been opened without creating the activity.
			closeFromActivity(true);
			return;
		}
		if (!activity.isFinishing()) {
		    if (options.containsKey("_anim")) {
		        _closingAnim = animateInternal(options.get("_anim"), null);
		        return;
            }
			activity.finish();
	        
	        int enterAnimation = TiConvert.toInt(options, TiC.PROPERTY_ACTIVITY_ENTER_ANIMATION, -1);
	        int exitAnimation = TiConvert.toInt(options, TiC.PROPERTY_ACTIVITY_EXIT_ANIMATION, -1);
	        boolean animated = TiConvert.toBoolean(options, TiC.PROPERTY_ANIMATED, true);
	        if (!animated) {
	            enterAnimation = 0;
	            exitAnimation = 0;
	        }
	        if (enterAnimation != -1 || exitAnimation != -1) {
	            activity.overridePendingTransition(enterAnimation, exitAnimation);
	        }
			// Finishing an activity is not synchronous, so we remove the activity from the activity stack here
			TiApplication.removeFromActivityStack(activity);
			windowActivity = null;
		}
	}

	@SuppressWarnings("unchecked")
	@Override
	public void windowCreated(TiBaseActivity activity) {
		windowActivity = new WeakReference<TiBaseActivity>(activity);
		activity.setWindowProxy(this);
		setActivity(activity);

		Window win = activity.getWindow();
		// Handle the background of the window activity if it is a translucent activity.
		// If it is a modal window, set a translucent dimmed background to the window.
		// If the opacity is given, set a transparent background to the window. In this case, if no backgroundColor or
		// backgroundImage is given, the window will be completely transparent.
		boolean modal = TiConvert.toBoolean(getProperty(TiC.PROPERTY_MODAL), false);
		Drawable background = null;
		if (modal) {
			background = new ColorDrawable(0x9F000000);
		} else if (hasProperty(TiC.PROPERTY_OPACITY)) {
			background = new ColorDrawable(0x00000000);
		}
		if (background != null) {
			win.setBackgroundDrawable(background);
		}

		// Handle the width and height of the window.
		// TODO: If width / height is a percentage value, we can not get the dimension in pixel because
		// the width / height of the decor view is not measured yet at this point. So we can not use the 
		// getAsPixels() method. Maybe we can use WindowManager.getDefaultDisplay.getRectSize(rect) to
		// get the application display dimension.
		if (hasProperty(TiC.PROPERTY_WIDTH) || hasProperty(TiC.PROPERTY_HEIGHT)) {
			Object width = getProperty(TiC.PROPERTY_WIDTH);
			Object height = getProperty(TiC.PROPERTY_HEIGHT);
			View decorView = win.getDecorView();
			if (decorView != null) {
				int w = LayoutParams.MATCH_PARENT;
				if (!(width == null || width.equals(TiC.LAYOUT_FILL))) {
					TiDimension wDimension = TiConvert.toTiDimension(width, TiDimension.TYPE_WIDTH);
					if (!wDimension.isUnitPercent()) {
						w = wDimension.getAsPixels(decorView);
					}
				}
				int h = LayoutParams.MATCH_PARENT;
				if (!(height == null || height.equals(TiC.LAYOUT_FILL))) {
					TiDimension hDimension = TiConvert.toTiDimension(height, TiDimension.TYPE_HEIGHT);
					if (!hDimension.isUnitPercent()) {
						h = hDimension.getAsPixels(decorView);
					}
				}
				win.setLayout(w, h);
			}
		}

		

		// Need to handle the cached activity proxy properties and url window in the JS side.
		callPropertySync(PROPERTY_POST_WINDOW_CREATED, null);
	}

	@Override
	public void onWindowActivityCreated()
	{
		
		opened = true;
		opening = false;
		
		if (parent == null && windowActivity != null) {
			TiBaseActivity activity = windowActivity.get();
			// Fire the open event after setContentView() because getActionBar() need to be called
			// after setContentView(). (TIMOB-14914)
			activity.getActivityProxy().getDecorView().add(this);
			activity.addWindowToStack(this);
		}
		
		
		handlePostOpen();
		

		super.onWindowActivityCreated();
	}
	
	@Override
	public void closeFromActivity(boolean activityIsFinishing)
	{
		super.closeFromActivity(activityIsFinishing);
		windowActivity = null;
	}

	@Override
	protected Activity getWindowActivity()
	{
		return (windowActivity != null) ? windowActivity.get() : null;
	}
	
	@Override
	public void setActivity(Activity activity)
	{
		windowActivity = new WeakReference<TiBaseActivity>((TiBaseActivity) activity);
		super.setActivity(activity);
		if (activity == null) return;
		if (hasProperty(TiC.PROPERTY_TOUCH_ENABLED)) {
			boolean active = TiConvert.toBoolean(getProperty(TiC.PROPERTY_TOUCH_ENABLED), true);
			if (active)
			{
				activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
			}
			else {
				activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                    | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
			}
		}
		if (hasProperty(TiC.PROPERTY_TOUCH_PASSTHROUGH)) {
			boolean active = TiConvert.toBoolean(getProperty(TiC.PROPERTY_TOUCH_PASSTHROUGH), true);
			if (active)
			{
				activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
			}
			else {
				activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                    | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
			}
		}
		if (hasProperty(TiC.PROPERTY_FOCUSABLE)) {
			boolean active = TiConvert.toBoolean(getProperty(TiC.PROPERTY_FOCUSABLE), true);
			if (active)
			{
				activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
			}
			else {
				activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
			}
		}
	}

	private void fillIntent(Activity activity, Intent intent)
	{
		int windowFlags = 0;
		if (hasProperty(TiC.PROPERTY_WINDOW_FLAGS)) {
			windowFlags = TiConvert.toInt(getProperty(TiC.PROPERTY_WINDOW_FLAGS), 0);
		}
		
		//Set the fullscreen flag
		if (hasProperty(TiC.PROPERTY_FULLSCREEN)) {
			boolean flagVal = TiConvert.toBoolean(getProperty(TiC.PROPERTY_FULLSCREEN), false);
			if (flagVal) {
				windowFlags = windowFlags | WindowManager.LayoutParams.FLAG_FULLSCREEN;
			}
		}
		
		//Set the secure flag
		if (hasProperty(TiC.PROPERTY_FLAG_SECURE)) {
			boolean flagVal = TiConvert.toBoolean(getProperty(TiC.PROPERTY_FLAG_SECURE), false);
			if (flagVal) {
				windowFlags = windowFlags | WindowManager.LayoutParams.FLAG_SECURE;
			}
		}
		
		//Stuff flags in intent
		intent.putExtra(TiC.PROPERTY_WINDOW_FLAGS, windowFlags);
		
		if (hasProperty(TiC.PROPERTY_WINDOW_SOFT_INPUT_MODE)) {
			intent.putExtra(TiC.PROPERTY_WINDOW_SOFT_INPUT_MODE, TiConvert.toInt(getProperty(TiC.PROPERTY_WINDOW_SOFT_INPUT_MODE), -1));
		}
		if (hasProperty(TiC.PROPERTY_EXIT_ON_CLOSE)) {
			intent.putExtra(TiC.INTENT_PROPERTY_FINISH_ROOT, TiConvert.toBoolean(getProperty(TiC.PROPERTY_EXIT_ON_CLOSE), false));
		} else {
			intent.putExtra(TiC.INTENT_PROPERTY_FINISH_ROOT, activity.isTaskRoot());
		}
		if (hasProperty(TiC.PROPERTY_NAV_BAR_HIDDEN)) {
			intent.putExtra(TiC.PROPERTY_NAV_BAR_HIDDEN, TiConvert.toBoolean(getProperty(TiC.PROPERTY_NAV_BAR_HIDDEN), false));
		}

		boolean modal = false;
		if (hasProperty(TiC.PROPERTY_MODAL)) {
			modal = TiConvert.toBoolean(getProperty(TiC.PROPERTY_MODAL), false);
			if (modal) {
				intent.setClass(activity, TiTranslucentActivity.class);
			}
			intent.putExtra(TiC.PROPERTY_MODAL, modal);
		}
		if (modal || hasProperty(TiC.PROPERTY_OPACITY) || (hasProperty(TiC.PROPERTY_BACKGROUND_COLOR) && 
				Color.alpha(TiConvert.toColor(getProperty(TiC.PROPERTY_BACKGROUND_COLOR))) < 255 )) {
			intent.setClass(activity, TiTranslucentActivity.class);
		} else if (hasProperty(TiC.PROPERTY_BACKGROUND_COLOR)) {
			int bgColor = TiConvert.toColor(properties, TiC.PROPERTY_BACKGROUND_COLOR);
			if (Color.alpha(bgColor) < 0xFF) {
				intent.setClass(activity, TiTranslucentActivity.class);
			}
		}
		if (hasProperty(TiC.PROPERTY_WINDOW_PIXEL_FORMAT)) {
			intent.putExtra(TiC.PROPERTY_WINDOW_PIXEL_FORMAT, TiConvert.toInt(getProperty(TiC.PROPERTY_WINDOW_PIXEL_FORMAT), PixelFormat.UNKNOWN));
		}

		// Set the theme property
		if (hasProperty(TiC.PROPERTY_THEME)) {
			String theme = TiConvert.toString(getProperty(TiC.PROPERTY_THEME));
			if (theme != null) {
				try {
					intent.putExtra(TiC.PROPERTY_THEME,
						TiRHelper.getResource("style." + theme.replaceAll("[^A-Za-z0-9_]", "_")));
				} catch (Exception e) {
					Log.w(TAG, "Cannot find the theme: " + theme);
				}
			}
		}
	}

	@Override
	public void onPropertyChanged(String name, Object value)
	{
		if ((opening || opened) && !lightweight) {
			Activity activity = getWindowActivity();
			if (TiC.PROPERTY_WINDOW_PIXEL_FORMAT.equals(name)) {
				getMainHandler().obtainMessage(MSG_SET_PIXEL_FORMAT, value).sendToTarget();
			} else if (TiC.PROPERTY_TITLE.equals(name)) {
				getMainHandler().obtainMessage(MSG_SET_TITLE, value).sendToTarget();
			} else if (TiC.PROPERTY_TOP.equals(name) || TiC.PROPERTY_BOTTOM.equals(name) || TiC.PROPERTY_LEFT.equals(name)
				|| TiC.PROPERTY_RIGHT.equals(name)) {
				// The "top", "bottom", "left" and "right" properties do not work for heavyweight windows.
				return;
			} else if (TiC.PROPERTY_TOUCH_ENABLED.equals(name) && activity != null)
			{
				boolean active = TiConvert.toBoolean(value, true);
				if (active)
				{
					activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
	                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
				}
				else {
					activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
				}
			} else if (TiC.PROPERTY_FOCUSABLE.equals(name) && activity != null)
			{
				boolean active = TiConvert.toBoolean(value, true);
				if (active)
				{
					activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
				}
				else {
					activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
				}
			}
		}
		super.onPropertyChanged(name, value);
	}

	@Override
	@Kroll.setProperty(retain=false) @Kroll.method
	public void setWidth(Object width)
	{
		// We know it's a HW window only when it's opening/opened.
		if ((opening || opened) && !lightweight) {
			Object current = getProperty(TiC.PROPERTY_WIDTH);
			if (shouldFireChange(current, width)) {
				Object height = getProperty(TiC.PROPERTY_HEIGHT);
				if (TiApplication.isUIThread()) {
					setWindowWidthHeight(width, height);
				} else {
					getMainHandler().obtainMessage(MSG_SET_WIDTH_HEIGHT, new Object[]{width, height}).sendToTarget();
				}
			}
		}
		super.setWidth(width);
	}

	@Override
	@Kroll.setProperty(retain=false) @Kroll.method
	public void setHeight(Object height)
	{
		// We know it's a HW window only when it's opening/opened.
		if ((opening || opened) && !lightweight) {
			Object current = getProperty(TiC.PROPERTY_HEIGHT);
			if (shouldFireChange(current, height)) {
				Object width = getProperty(TiC.PROPERTY_WIDTH);
				if (TiApplication.isUIThread()) {
					setWindowWidthHeight(width, height);
				} else {
					getMainHandler().obtainMessage(MSG_SET_WIDTH_HEIGHT, new Object[]{width, height}).sendToTarget();
				}
			}
		}
		super.setHeight(height);
	}

	@Override
	public boolean handleMessage(Message msg)
	{
		switch (msg.what) {
			case MSG_SET_PIXEL_FORMAT: {
				Activity activity = getWindowActivity();
				if (activity != null) {
					Window win = activity.getWindow();
					if (win != null) {
						win.setFormat(TiConvert.toInt((Object)(msg.obj), PixelFormat.UNKNOWN));
						win.getDecorView().invalidate();
					}
				}
				return true;
			}
			case MSG_SET_TITLE: {
				Activity activity = getWindowActivity();
				if (activity != null) {
					activity.setTitle(TiConvert.toString((Object)(msg.obj), ""));
				}
				return true;
			}
			case MSG_SET_WIDTH_HEIGHT: {
				Object[] obj = (Object[]) msg.obj;
				setWindowWidthHeight(obj[0], obj[1]);
				return true;
			}
			case MSG_REMOVE_LIGHTWEIGHT: {
				removeLightweightWindowFromStack();
				return true;
			}
		}
		return super.handleMessage(msg);
	}

	private void setWindowWidthHeight(Object width, Object height)
	{
		Activity activity = getWindowActivity();
		if (activity != null) {
			Window win = activity.getWindow();
			if (win != null) {
				View decorView = win.getDecorView();
				if (decorView != null) {
					int w = LayoutParams.MATCH_PARENT;
					if (!(width == null || width.equals(TiC.LAYOUT_FILL))) {
						TiDimension wDimension = TiConvert.toTiDimension(width, TiDimension.TYPE_WIDTH);
						if (!wDimension.isUnitPercent()) {
							w = wDimension.getAsPixels(decorView);
						}
					}
					int h = LayoutParams.MATCH_PARENT;
					if (!(height == null || height.equals(TiC.LAYOUT_FILL))) {
						TiDimension hDimension = TiConvert.toTiDimension(height, TiDimension.TYPE_HEIGHT);
						if (!hDimension.isUnitPercent()) {
							h = hDimension.getAsPixels(decorView);
						}
					}
					win.setLayout(w, h);
				}
			}
		}
	}

	@Kroll.method(name = "_getWindowActivityProxy")
	public ActivityProxy getWindowActivityProxy()
	{
		if (opened) {
			return super.getActivityProxy();
		} else {
			return null;
		}
	}

	@Kroll.method(name = "_isLightweight")
	public boolean isLightweight()
	{
		// We know whether a window is lightweight or not only after it opens.
		return (opened && lightweight);
	}

	@Override
	public String getApiName()
	{
		return "Ti.UI.Window";
	}
}
