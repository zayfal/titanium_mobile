/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2012 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
package ti.modules.titanium.ui.widget;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.TiBaseActivity;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.TiDimension;
import org.appcelerator.titanium.TiLifecycle.OnLifecycleEvent;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiUIView;

import ti.modules.titanium.ui.SearchBarProxy;
import ti.modules.titanium.ui.TableViewProxy;
import ti.modules.titanium.ui.widget.searchbar.TiUISearchBar;
import ti.modules.titanium.ui.widget.searchview.TiUISearchView;
import ti.modules.titanium.ui.widget.tableview.TableViewModel;
import ti.modules.titanium.ui.widget.tableview.TiTableView;
import ti.modules.titanium.ui.widget.tableview.TiTableView.OnItemClickedListener;
import ti.modules.titanium.ui.widget.tableview.TiTableView.OnItemLongClickedListener;
import android.annotation.TargetApi;
import android.app.Activity;
import android.os.Build;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.ListView;
import android.widget.RelativeLayout;

@TargetApi(Build.VERSION_CODES.GINGERBREAD)
public class TiUITableView extends TiUIView
	implements OnItemClickedListener, OnItemLongClickedListener, OnLifecycleEvent
{
	private static final String TAG = "TitaniumTableView";
	
	public static final int SEPARATOR_NONE = 0;
	public static final int SEPARATOR_SINGLE_LINE = 1;

	protected TiTableView tableView;

	public TiUITableView(TiViewProxy proxy)
	{
		super(proxy);
		getLayoutParams().autoFillsHeight = true;
		getLayoutParams().autoFillsWidth = true;

		Log.d(TAG, "Creating a tableView", Log.DEBUG_MODE);
		tableView = new TiTableView((TableViewProxy) proxy) {
			@Override
			public boolean dispatchTouchEvent(MotionEvent event) {
				if (touchPassThrough == true)
					return false;
				return super.dispatchTouchEvent(event);
			}
		};
		Activity activity = proxy.getActivity();
		if (activity instanceof TiBaseActivity) {
			((TiBaseActivity) activity).addOnLifecycleEventListener(this);
		}
		tableView.setOnItemClickListener(this);
		tableView.setOnItemLongClickListener(this);
	}

	@Override
	public void onClick(KrollDict data)
	{
		proxy.fireEvent(TiC.EVENT_CLICK, data);
	}

	@Override
	public boolean onLongClick(KrollDict data)
	{
		return proxy.fireEvent(TiC.EVENT_LONGCLICK, data);
	}

	public void setModelDirty()
	{
		tableView.getTableViewModel().setDirty();
	}
	
	public TableViewModel getModel()
	{
		return tableView.getTableViewModel();
	}

	public void updateView()
	{
		tableView.dataSetChanged();
	}

	public void scrollToIndex(final int index)
	{
		tableView.getListView().smoothScrollToPosition(index);
	}

	public void scrollToTop(final int y, boolean animated)
	{
		if (animated) {
			tableView.getListView().smoothScrollToPosition(0);
		}
		else {
			tableView.getListView().setSelectionFromTop(0, y);
		}
	}

	public void scrollToBottom(final int y, boolean animated)
	{
		if (animated) {
			tableView.getListView().smoothScrollToPosition(tableView.getCount() - 1);
		}
		else {
			tableView.getListView().setSelection(tableView.getCount() - 1);
		}
	}

	public void selectRow(final int row_id)
	{
		tableView.getListView().setSelection(row_id);
	}

	public TiTableView getTableView()
	{
		return tableView;
	}

	public CustomListView getListView()
	{
		return tableView.getListView();
	}
	
	@Override
	public void processProperties(KrollDict d)
	{
		// Don't create a new table view if one already exists
		if (tableView == null) {
			tableView = new TiTableView((TableViewProxy) proxy);
		}
		Activity activity = proxy.getActivity();
		if (activity instanceof TiBaseActivity) {
			((TiBaseActivity) activity).addOnLifecycleEventListener(this);
		}

		boolean clickable = true;
		if (d.containsKey(TiC.PROPERTY_TOUCH_ENABLED)) {
			clickable = TiConvert.toBoolean(proxy.getProperty(TiC.PROPERTY_TOUCH_ENABLED), true);
		}
		if (clickable) {
			tableView.setOnItemClickListener(this);
			tableView.setOnItemLongClickListener(this);

		}
		
		ListView list = getListView();
		if (d.containsKey(TiC.PROPERTY_FOOTER_DIVIDERS_ENABLED)) {
			boolean enabled = TiConvert.toBoolean(d, TiC.PROPERTY_FOOTER_DIVIDERS_ENABLED, false);
			list.setFooterDividersEnabled(enabled);
		} else {
			list.setFooterDividersEnabled(false);
		}
		
		if (d.containsKey(TiC.PROPERTY_HEADER_DIVIDERS_ENABLED)) {
			boolean enabled = TiConvert.toBoolean(d, TiC.PROPERTY_HEADER_DIVIDERS_ENABLED, false);
			list.setHeaderDividersEnabled(enabled);
		} else {
			list.setHeaderDividersEnabled(false);
		}
	
		if (d.containsKey(TiC.PROPERTY_SEARCH)) {
			TiViewProxy searchView = (TiViewProxy) d.get(TiC.PROPERTY_SEARCH);
			TiUIView search = searchView.getOrCreateView();
			if (searchView instanceof SearchBarProxy) {
				((TiUISearchBar)search).setOnSearchChangeListener(tableView);
			} else {
				((TiUISearchView)search).setOnSearchChangeListener(tableView);
			}
			if (!(d.containsKey(TiC.PROPERTY_SEARCH_AS_CHILD) && !TiConvert.toBoolean(d.get(TiC.PROPERTY_SEARCH_AS_CHILD)))) {


				search.getNativeView().setId(102);

				RelativeLayout layout = new RelativeLayout(proxy.getActivity());
				layout.setGravity(Gravity.NO_GRAVITY);
				layout.setPadding(0, 0, 0, 0);

				RelativeLayout.LayoutParams p = new RelativeLayout.LayoutParams(
						RelativeLayout.LayoutParams.MATCH_PARENT,
						RelativeLayout.LayoutParams.MATCH_PARENT);
				p.addRule(RelativeLayout.ALIGN_PARENT_TOP);
				p.addRule(RelativeLayout.ALIGN_PARENT_LEFT);
				p.addRule(RelativeLayout.ALIGN_PARENT_RIGHT);

				TiDimension rawHeight;
				if (searchView.hasProperty("height")) {
					rawHeight = TiConvert.toTiDimension(searchView.getProperty("height"), 0);
				} else {
					rawHeight = TiConvert.toTiDimension("52dp", 0);
				}
				p.height = rawHeight.getAsPixels(layout);

				layout.addView(search.getNativeView(), p);

				p = new RelativeLayout.LayoutParams(
						RelativeLayout.LayoutParams.MATCH_PARENT,
						RelativeLayout.LayoutParams.MATCH_PARENT);
				p.addRule(RelativeLayout.ALIGN_PARENT_LEFT);
				p.addRule(RelativeLayout.ALIGN_PARENT_BOTTOM);
				p.addRule(RelativeLayout.ALIGN_PARENT_RIGHT);
				p.addRule(RelativeLayout.BELOW, 102);
				layout.addView(tableView, p);
				setNativeView(layout);
			} else {
				setNativeView(tableView);
			}
		} else {
			setNativeView(tableView);
		}

		if (d.containsKey(TiC.PROPERTY_FILTER_ATTRIBUTE)) {
			tableView.setFilterAttribute(TiConvert.toString(d, TiC.PROPERTY_FILTER_ATTRIBUTE));
		} else {
			// Default to title to match iPhone default.
			proxy.setProperty(TiC.PROPERTY_FILTER_ATTRIBUTE, TiC.PROPERTY_TITLE, false);
			tableView.setFilterAttribute(TiC.PROPERTY_TITLE);
		}

		if (d.containsKey(TiC.PROPERTY_OVER_SCROLL_MODE)) {
			if (Build.VERSION.SDK_INT >= 9) {
				getListView().setOverScrollMode(TiConvert.toInt(d.get(TiC.PROPERTY_OVER_SCROLL_MODE), View.OVER_SCROLL_ALWAYS));
			}
		}
		
		if (d.containsKey(TiC.PROPERTY_SEPARATOR_COLOR)) {
			tableView.setSeparatorColor(TiConvert.toString(d, TiC.PROPERTY_SEPARATOR_COLOR));
		}
		if (d.containsKey(TiC.PROPERTY_SEPARATOR_STYLE)) {
			tableView.setSeparatorStyle(TiConvert.toInt(d, TiC.PROPERTY_SEPARATOR_STYLE));
		}
		
		if (d.containsKey(TiC.PROPERTY_SCROLLING_ENABLED)) {
			getListView().setScrollingEnabled(d.get(TiC.PROPERTY_SCROLLING_ENABLED));
		}
		
		boolean filterCaseInsensitive = true;
		if (d.containsKey(TiC.PROPERTY_FILTER_CASE_INSENSITIVE)) {
			filterCaseInsensitive = TiConvert.toBoolean(d, TiC.PROPERTY_FILTER_CASE_INSENSITIVE);
		}
		tableView.setFilterCaseInsensitive(filterCaseInsensitive);
		boolean filterAnchored = false;
		if (d.containsKey(TiC.PROPERTY_FILTER_ANCHORED)) {
			filterAnchored = TiConvert.toBoolean(d, TiC.PROPERTY_FILTER_ANCHORED);
		}
		tableView.setFilterAnchored(filterAnchored);
		super.processProperties(d);
	}

	@Override
	public void onResume(Activity activity) {
		if (tableView != null) {
			tableView.dataSetChanged();
		}
	}

	@Override public void onStop(Activity activity) {}
	@Override public void onStart(Activity activity) {}
	@Override public void onPause(Activity activity) {}
	@Override public void onDestroy(Activity activity) {}

	@Override
	public void release()
	{
		// Release search bar if there is one
		if (nativeView instanceof RelativeLayout) {
			((RelativeLayout) nativeView).removeAllViews();
			TiViewProxy searchView = (TiViewProxy) (proxy.getProperty(TiC.PROPERTY_SEARCH));
			searchView.release();
		}

		if (tableView != null) {
			tableView.release();
			tableView  = null;
		}
		if (proxy != null && proxy.getActivity() != null) {
			((TiBaseActivity)proxy.getActivity()).removeOnLifecycleEventListener(this);
		}
		nativeView  = null;
		super.release();
	}

	@Override
	public void propertyChanged(String key, Object oldValue, Object newValue, KrollProxy proxy)
	{
		if (Log.isDebugModeEnabled()) {
			Log.d(TAG, "Property: " + key + " old: " + oldValue + " new: " + newValue, Log.DEBUG_MODE);
		}

		if (key.equals(TiC.PROPERTY_TOUCH_ENABLED)) {
			boolean clickable = TiConvert.toBoolean(newValue);
			if (clickable) {
				tableView.setOnItemClickListener(this);
				tableView.setOnItemLongClickListener(this);

			} else {
				tableView.setOnItemClickListener(null);
				tableView.setOnItemLongClickListener(null);
			}

		} else if (key.equals(TiC.PROPERTY_SEPARATOR_COLOR)) {
			tableView.setSeparatorColor(TiConvert.toString(newValue));
		} else if (key.equals(TiC.PROPERTY_SCROLLING_ENABLED)) {
			getListView().setScrollingEnabled(newValue);
		} else if (key.equals(TiC.PROPERTY_SEPARATOR_STYLE)) {
			tableView.setSeparatorStyle(TiConvert.toInt(newValue));
		} else if (TiC.PROPERTY_OVER_SCROLL_MODE.equals(key)){
			if (Build.VERSION.SDK_INT >= 9) {
				getListView().setOverScrollMode(TiConvert.toInt(newValue, View.OVER_SCROLL_ALWAYS));
			}
		} else if (TiC.PROPERTY_MIN_ROW_HEIGHT.equals(key)) {
			updateView();
		} else if (TiC.PROPERTY_HEADER_VIEW.equals(key)) {
			if (oldValue != null) {
				tableView.removeHeaderView((TiViewProxy) oldValue);
			}
			tableView.setHeaderView();
		} else if (TiC.PROPERTY_FOOTER_VIEW.equals(key)) {
			if (oldValue != null) {
				tableView.removeFooterView((TiViewProxy) oldValue);
			}
			tableView.setFooterView();
		} else if (key.equals(TiC.PROPERTY_FILTER_ANCHORED)) {
			tableView.setFilterAnchored(TiConvert.toBoolean(newValue));
		} else if (key.equals(TiC.PROPERTY_FILTER_CASE_INSENSITIVE)) {
			tableView.setFilterCaseInsensitive(TiConvert.toBoolean(newValue));
		} else {
			super.propertyChanged(key, oldValue, newValue, proxy);
		}
	}

	@Override
	public void registerForTouch() {
		registerForTouch(tableView.getListView());
	}
}
