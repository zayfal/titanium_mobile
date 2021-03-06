/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2013 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
package ti.modules.titanium.ui.widget;

import java.util.HashMap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.util.TiUIHelper;
import org.appcelerator.titanium.view.TiUINonViewGroupView;
import org.appcelerator.titanium.view.TiUIView;
import org.appcelerator.titanium.view.TiCompositeLayout;

import ti.modules.titanium.ui.UIModule;
import br.com.sapereaude.maskedEditText.MaskedEditText;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Build;
import android.text.Editable;
import android.text.InputType;
import android.text.TextUtils.TruncateAt;
import android.text.TextWatcher;
import android.text.method.DialerKeyListener;
import android.text.method.DigitsKeyListener;
import android.text.method.NumberKeyListener;
import android.text.method.PasswordTransformationMethod;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.View.OnFocusChangeListener;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.TextView.OnEditorActionListener;
import android.content.res.ColorStateList;

public class TiUIText extends TiUINonViewGroupView
	implements TextWatcher, OnEditorActionListener, OnFocusChangeListener
{
	private static final String TAG = "TiUIText";

	
	

	private int selectedColor, color, disabledColor;
	private boolean field;
	private int maxLength = -1;
	private boolean isTruncatingText = false;
	private boolean disableChangeEvent = false;
    protected boolean isEditable = true;
    private boolean suppressReturn = true;

	protected FocusFixedEditText tv;
	protected TiEditText realtv;

	public class TiEditText extends MaskedEditText 
	{
	    
		public TiEditText(Context context) 
		{
			super(context);
		}
		
		@Override
		protected void drawableStateChanged() {
			if (hasFocus()) propagateDrawableState(TiUIHelper.BACKGROUND_SELECTED_STATE);
			else propagateChildDrawableState(this);
		}
		
		@Override
		public View focusSearch(int direction) {
			View result = super.focusSearch(direction);
	        return result;
	    }
		
		/** 
		 * Check whether the called view is a text editor, in which case it would make sense to 
		 * automatically display a soft input window for it.
		 */
		@Override
		public boolean onCheckIsTextEditor () {
			if (proxy.hasProperty(TiC.PROPERTY_SOFT_KEYBOARD_ON_FOCUS)
					&& TiConvert.toInt(proxy.getProperty(TiC.PROPERTY_SOFT_KEYBOARD_ON_FOCUS)) == TiUIView.SOFT_KEYBOARD_HIDE_ON_FOCUS) {
					return false;
			}
			if (!isEditable) {
				return false;
			}
			return true;
		}
		
		@Override
	    protected void onMeasure(int widthMeasureSpec,int heightMeasureSpec) {
			
			//In the TextView when using AT_MOST,
			//it would size to Math.min(widthSize, width); which is NOT what we want
		    // when using FILL
			int widthMode = MeasureSpec.getMode(widthMeasureSpec);
	        int heightMode = MeasureSpec.getMode(heightMeasureSpec);
	        int widthSize = MeasureSpec.getSize(widthMeasureSpec);
	        int heightSize = MeasureSpec.getSize(heightMeasureSpec);
	        
	        if (widthMode == MeasureSpec.AT_MOST && layoutParams.autoFillsWidth) {
	        	widthMeasureSpec = MeasureSpec.makeMeasureSpec(widthSize, MeasureSpec.EXACTLY);
	        }
	        if (heightMode == MeasureSpec.AT_MOST && layoutParams.autoFillsHeight) {
	        	heightMeasureSpec = MeasureSpec.makeMeasureSpec(heightSize, MeasureSpec.EXACTLY);
	        }
			 super.onMeasure(widthMeasureSpec, heightMeasureSpec);
	    }

		@Override
		protected void onLayout(boolean changed, int left, int top, int right, int bottom)
		{
			super.onLayout(changed, left, top, right, bottom);
			TiUIHelper.firePostLayoutEvent(TiUIText.this);
		}

		@Override
		public boolean dispatchTouchEvent(MotionEvent event) {
			if (touchPassThrough == true)
				return false;
			return super.dispatchTouchEvent(event);
		}
		

        @Override
        public void dispatchSetPressed(boolean pressed) {
            if (childrenHolder != null && dispatchPressed) {
                childrenHolder.setPressed(pressed);
            }
        }
        

        @Override
        public void clearFocus() {
            //clear focused is called in setInputType and clearfocus request the focus
            //in root even if we didnt have the focus. DUMB!
            if (!hasFocus()) {
                return;
            } else {
                super.clearFocus();
            }
        }
        
        @Override
        public boolean dispatchKeyEventPreIme(KeyEvent event) {
                InputMethodManager imm = getIMM();
                if (imm != null && imm.isActive() && 
                        event.getAction() == KeyEvent.ACTION_UP && event.getKeyCode() == KeyEvent.KEYCODE_BACK) {
                    //when hiding the keyboard with the back button also blur
                    blur();
                    return true;
                }
            return super.dispatchKeyEventPreIme(event);
        }
	}

	public class FocusFixedEditText extends LinearLayout {
		TiEditText editText;
		LinearLayout layout;
		protected TiCompositeLayout leftPane;
		protected TiCompositeLayout rightPane;
		private TiViewProxy leftView;
		private TiViewProxy rightView;

		private LinearLayout.LayoutParams createBaseParams()
		{
			return new LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT);
		}

		private void init(Context context) {
			layout = this;
			this.setFocusableInTouchMode(true);
			this.setFocusable(true);
			this.setDescendantFocusability(ViewGroup.FOCUS_BEFORE_DESCENDANTS);
			this.requestFocus();
			this.setOrientation(LinearLayout.HORIZONTAL);

			LinearLayout.LayoutParams params;

			leftPane = new TiCompositeLayout(context);
			leftPane.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
			leftPane.setFocusable(false);
			leftPane.setId(100);
			leftPane.setVisibility(View.GONE);
			leftPane.setTag("leftPane");
			params = createBaseParams();
			params.gravity = Gravity.CENTER;
			this.addView(leftPane, params);

			editText = new TiEditText(context);
			editText.setId(200);
			params = new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT);
			this.addView(editText, params);

			rightPane = new TiCompositeLayout(context);
			rightPane.setId(300);
			rightPane.setVisibility(View.GONE);
			rightPane.setTag("rightPane");
			rightPane.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
			rightPane.setFocusable(false);
			params = createBaseParams();
			params.gravity = Gravity.CENTER;
			layout.addView(rightPane, params);

		}

		public FocusFixedEditText(Context context) {
			super(context);
			init(context);
		}

		public void setLeftView(Object leftView) {
			leftPane.removeAllViews();
			if (this.leftView != null) {
                this.leftView.releaseViews(false);
                this.leftView.setParent(null);
                this.leftView = null;
            }
			if (leftView instanceof HashMap) {
                this.leftView = (TiViewProxy)proxy.createProxyFromTemplate((HashMap) leftView,
                       proxy, true);
                if (this.leftView != null) {
                    this.leftView.updateKrollObjectProperties();
                }
            }
            else if (leftView instanceof TiViewProxy) {
                this.leftView = (TiViewProxy)leftView;
            }
            
            if (this.leftView != null) {
                leftPane.addView((this.leftView.getOrCreateView()).getOuterView());
                leftPane.setVisibility(View.VISIBLE);
            }
            else if (leftView instanceof View) {
                leftPane.addView((View)leftView);
                leftPane.setVisibility(View.VISIBLE);
            } else {
                leftPane.setVisibility(View.GONE);
            }
		}

		public TiViewProxy getLeftView()
		{
			return leftView;
		}

		public TiViewProxy getRightView()
		{
			return rightView;
		}

		public void setRightView(Object rightView) {
			rightPane.removeAllViews();
            if (this.rightView != null) {
                this.rightView.releaseViews(false);
                this.rightView.setParent(null);
                this.rightView = null;
            }
            if (rightView instanceof HashMap) {
                this.rightView = (TiViewProxy)proxy.createProxyFromTemplate((HashMap) rightView,
                       proxy, true);
                if (this.rightView != null) {
                    this.rightView.updateKrollObjectProperties();
                }
            }
            else if (rightView instanceof TiViewProxy) {
                this.rightView = (TiViewProxy)rightView;
            }
            
            if (this.rightView != null) {
                rightPane.addView((this.rightView.getOrCreateView()).getOuterView());
                rightPane.setVisibility(View.VISIBLE);
            }
            else if (rightView instanceof View) {
                rightPane.addView((View)rightView);
                rightPane.setVisibility(View.VISIBLE);
            } else {
                rightPane.setVisibility(View.GONE);
            }
		}

		public void hideLeftView()
		{
			leftPane.setVisibility(View.GONE);
		}

		public void showLeftView()
		{
			if (leftView != null){
				leftPane.setVisibility(View.VISIBLE);
			}
		}

		public void hideRightView()
		{
			rightPane.setVisibility(View.GONE);
		}

		public void showRightView()
		{
			if (rightView != null){
				rightPane.setVisibility(View.VISIBLE);
			}
		}

		public void onFocusChange(View v, boolean hasFocus)
		{
			Log.d(TAG, "onFocusChange "  + hasFocus + "  for FocusFixedEditText with text " + editText.getText(), Log.DEBUG_MODE);

		}
		
		@Override
		public boolean dispatchTouchEvent(MotionEvent event) {
			if (touchPassThrough == true)
				return false;
			return super.dispatchTouchEvent(event);
		}

		@Override
		public boolean onCheckIsTextEditor () {
			return editText.onCheckIsTextEditor();
		}

		public TiEditText getRealEditText() {
			return editText;
		}
		
		public boolean hasFocus() {
			return editText.hasFocus();
		}

		public void setOnFocusChangeListener(OnFocusChangeListener l) {
			editText.setOnFocusChangeListener(l);
		}
		
		@Override
	    public void clearFocus() {
		    //clear focused is called in setInputType and clearfocus request the focus
            //in root even if we didnt have the focus. DUMB!
	        if (!hasFocus()) {
	            return;
	        } else {
                super.clearFocus();
	        }
	    }
	}

	public TiUIText(final TiViewProxy proxy, boolean field)
	{
		super(proxy);
		Log.d(TAG, "Creating a text field2", Log.DEBUG_MODE);
		this.focusKeyboardState = TiUIView.SOFT_KEYBOARD_SHOW_ON_FOCUS;
		this.isFocusable = true; //default to true
		this.field = field;
		tv = new FocusFixedEditText(getProxy().getActivity());
		realtv = tv.getRealEditText();
        realtv.setSingleLine(field);
		if (field) {
			realtv.setMaxLines(1);
		}
		else {
//            realtv.setMaxLines(1000);
//            realtv.setMinLines(2);
//            realtv.setHorizontallyScrolling(false);
//            realtv.setEllipsize(null);
//            realtv.setInputType(InputType.TYPE_TEXT_FLAG_MULTI_LINE);
		}
		realtv.addTextChangedListener(this);
		realtv.setOnEditorActionListener(this);
		realtv.setIncludeFontPadding(true); 
		if (field) {
			realtv.setGravity(Gravity.CENTER_VERTICAL | Gravity.LEFT);
		} else {
			realtv.setGravity(Gravity.TOP | Gravity.LEFT);
		}
		color = disabledColor = selectedColor = realtv.getCurrentTextColor();
		setNativeView(tv);
	}


	private void updateTextColors() {
		int[][] states = new int[][] {
			TiUIHelper.BACKGROUND_DISABLED_STATE, // disabled
			TiUIHelper.BACKGROUND_SELECTED_STATE, // pressed
			TiUIHelper.BACKGROUND_FOCUSED_STATE,  // pressed
			TiUIHelper.BACKGROUND_CHECKED_STATE,  // pressed
			new int [] {android.R.attr.state_pressed},  // pressed
			new int [] {android.R.attr.state_focused},  // pressed
			new int [] {}
		};

		ColorStateList colorStateList = new ColorStateList(
			states,
			new int[] {disabledColor, selectedColor, selectedColor, selectedColor, selectedColor, selectedColor, color}
		);

		realtv.setTextColor(colorStateList);
	}

	@Override
	public void processProperties(KrollDict d)
	{
	 // Disable change event temporarily as we are setting the default value
        disableChangeEvent = true;
        
		super.processProperties(d);
		
		if (d.containsKey(TiC.PROPERTY_ENABLED)) {
			realtv.setEnabled(d.optBoolean(TiC.PROPERTY_ENABLED, true));
		}

		if (d.containsKey(TiC.PROPERTY_MAX_LENGTH)) {
			maxLength = TiConvert.toInt(d.get(TiC.PROPERTY_MAX_LENGTH), -1);
		}
		
		if (d.containsKey(TiC.PROPERTY_SUPPRESS_RETURN)) {
            suppressReturn = d.optBoolean(TiC.PROPERTY_SUPPRESS_RETURN, true);
        }
		
		if (d.containsKey(TiC.PROPERTY_MASK_CHAR)) {
		    String charRep = d.getString(TiC.PROPERTY_MASK_CHAR);
		    if (d!=null && d.size() > 0) {
	            realtv.setCharRepresentation(charRep.charAt(0));
		    }
		    else {
                realtv.setCharRepresentation('#');
		    }
        }

		boolean needsColors = false;
		if(d.containsKey(TiC.PROPERTY_COLOR)) {
			needsColors = true;
			color = selectedColor = disabledColor = d.optColor(TiC.PROPERTY_COLOR, this.color);
		}
		if(d.containsKey(TiC.PROPERTY_SELECTED_COLOR)) {
			needsColors = true;
			selectedColor = d.optColor(TiC.PROPERTY_SELECTED_COLOR, this.selectedColor);
		}
		if(d.containsKey(TiC.PROPERTY_DISABLED_COLOR)) {
			needsColors = true;
			disabledColor = d.optColor(TiC.PROPERTY_DISABLED_COLOR, this.disabledColor);
		}
		if (needsColors) {
			updateTextColors();
		}

        if (d.containsKey(TiC.PROPERTY_HINT_TEXT)) {
            realtv.setHint(d.getString(TiC.PROPERTY_HINT_TEXT));
        }
        
        //set the mask after the hintText as it looks for its value
        if (d.containsKey(TiC.PROPERTY_MASK)) {
            realtv.setMask(d.getString(TiC.PROPERTY_MASK));
        }

        if (d.containsKey(TiC.PROPERTY_VALUE)) {
            realtv.setText(d.getString(TiC.PROPERTY_VALUE));
            int pos = realtv.getText().length();
            realtv.setSelection(pos);
        }
		
		if (d.containsKey(TiC.PROPERTY_HINT_COLOR)) {
			realtv.setHintTextColor(d.optColor(TiC.PROPERTY_HINT_COLOR, Color.GRAY));
		}

		if (d.containsKey(TiC.PROPERTY_ELLIPSIZE)) {
			if (TiConvert.toBoolean(d, TiC.PROPERTY_ELLIPSIZE)) {
				realtv.setEllipsize(TruncateAt.END);
			} else {
				realtv.setEllipsize(null);
			}
		}
		
        if (d.containsKey(TiC.PROPERTY_FONT)) {
            TiUIHelper.styleText(realtv, d.getKrollDict(TiC.PROPERTY_FONT));
        }

		
		if (d.containsKey(TiC.PROPERTY_TEXT_ALIGN) || d.containsKey(TiC.PROPERTY_VERTICAL_ALIGN)) {
			String textAlign = d.optString(TiC.PROPERTY_TEXT_ALIGN, "left");
			String verticalAlign = d.optString(TiC.PROPERTY_VERTICAL_ALIGN, "middle");
			TiUIHelper.setAlignment(realtv, textAlign, verticalAlign);
		}

		if (!field || d.containsKey(TiC.PROPERTY_KEYBOARD_TYPE) || d.containsKey(TiC.PROPERTY_AUTOCORRECT)
			|| d.containsKey(TiC.PROPERTY_PASSWORD_MASK) || d.containsKey(TiC.PROPERTY_AUTOCAPITALIZATION)) {
			handleKeyboard(d);
		}
		
		
		if (d.containsKey(TiC.PROPERTY_EDITABLE)) {
		    isEditable = d.optBoolean(TiC.PROPERTY_EDITABLE, true);
		}
		boolean focusable = isEditable && isEnabled;
		TiUIView.setFocusable(realtv, focusable);
        TiUIView.setFocusable(tv, focusable);
        realtv.setCursorVisible(focusable);
		
		//the order is important because returnKeyType must overload keyboard return key defined
		// by keyboardType
		if (d.containsKey(TiC.PROPERTY_RETURN_KEY_TYPE)) {
			handleReturnKeyType(TiConvert.toInt(d.get(TiC.PROPERTY_RETURN_KEY_TYPE), UIModule.RETURNKEY_DEFAULT));
		}
		
		if (d.containsKey(TiC.PROPERTY_PADDING)) {
			RectF padding = TiConvert.toPaddingRect(d, TiC.PROPERTY_PADDING);
			TiUIHelper.setPadding(realtv, padding);
		}

		if (d.containsKey(TiC.PROPERTY_AUTO_LINK)) {
			TiUIHelper.linkifyIfEnabled(realtv, d.get(TiC.PROPERTY_AUTO_LINK));
		}

		if (d.containsKey(TiC.PROPERTY_LEFT_BUTTON)) {
			tv.setLeftView(d.get(TiC.PROPERTY_LEFT_BUTTON));
		}

		if (d.containsKey(TiC.PROPERTY_RIGHT_BUTTON)) {
			tv.setRightView(d.get(TiC.PROPERTY_RIGHT_BUTTON));
		}
        disableChangeEvent = false;
	}


	@Override
	public void propertyChanged(String key, Object oldValue, Object newValue, KrollProxy proxy)
	{
		if (Log.isDebugModeEnabled()) {
			Log.d(TAG, "Property: " + key + " old: " + oldValue + " new: " + newValue, Log.DEBUG_MODE);
		}
		if (key.equals(TiC.PROPERTY_ENABLED)) {
			realtv.setEnabled(TiConvert.toBoolean(newValue));
		} else if (key.equals(TiC.PROPERTY_VALUE)) {
			realtv.setText(TiConvert.toString(newValue));
			int pos = realtv.getText().length();
			realtv.setSelection(pos);
		} else if (key.equals(TiC.PROPERTY_MAX_LENGTH)) {
			maxLength = TiConvert.toInt(newValue);
			//truncate if current text exceeds max length
			Editable currentText = realtv.getText();
			if (maxLength >= 0 && currentText.length() > maxLength) {
				CharSequence truncateText = currentText.subSequence(0, maxLength);
				int cursor = realtv.getSelectionStart() - 1;
				if (cursor > maxLength) {
					cursor = maxLength;
				}
				realtv.setText(truncateText);
				realtv.setSelection(cursor);
			}
		} else if (key.equals(TiC.PROPERTY_COLOR)) {
			this.color = TiConvert.toColor(newValue);
			updateTextColors();
		} else if (key.equals(TiC.PROPERTY_SELECTED_COLOR)) {
			this.selectedColor = TiConvert.toColor(newValue);
			updateTextColors();
		} else if (key.equals(TiC.PROPERTY_DISABLED_COLOR)) {
			this.disabledColor = TiConvert.toColor(newValue);
			updateTextColors();
		} else if (key.equals(TiC.PROPERTY_HINT_TEXT)) {
			realtv.setHint(TiConvert.toString(newValue));
		} else if (key.equals(TiC.PROPERTY_ELLIPSIZE)) {
			if (TiConvert.toBoolean(newValue)) {
				realtv.setEllipsize(TruncateAt.END);
			} else {
				realtv.setEllipsize(null);
			}
		} else if (key.equals(TiC.PROPERTY_TEXT_ALIGN)) {
			TiUIHelper.setAlignment(realtv, TiConvert.toString(newValue), null);
			tv.requestLayout();
		} else if (key.equals(TiC.PROPERTY_VERTICAL_ALIGN)) {
			TiUIHelper.setAlignment(realtv, null, TiConvert.toString(newValue));
			tv.requestLayout();
		} else if (key.equals(TiC.PROPERTY_KEYBOARD_TYPE)
			|| (key.equals(TiC.PROPERTY_AUTOCORRECT) || key.equals(TiC.PROPERTY_AUTOCAPITALIZATION)
				|| key.equals(TiC.PROPERTY_PASSWORD_MASK))) {
			KrollDict d = proxy.getProperties();
			handleKeyboard(d);
		} else if (key.equals(TiC.PROPERTY_EDITABLE)) {
		    isEditable = TiConvert.toBoolean(newValue);
		    boolean focusable = isEditable && isEnabled;
            TiUIView.setFocusable(realtv, focusable);
            TiUIView.setFocusable(tv, focusable);
            realtv.setCursorVisible(focusable);
		} else if (key.equals(TiC.PROPERTY_RETURN_KEY_TYPE)) {
            handleReturnKeyType(TiConvert.toInt(newValue));
		} else if (key.equals(TiC.PROPERTY_FONT)) {
			TiUIHelper.styleText(realtv, (HashMap) newValue);
		} else if (key.equals(TiC.PROPERTY_AUTO_LINK)){
			TiUIHelper.linkifyIfEnabled(realtv, newValue);
		} else if (key.equals(TiC.PROPERTY_AUTO_LINK)){
            suppressReturn = TiConvert.toBoolean(newValue);
		} else if (key.equals(TiC.PROPERTY_LEFT_BUTTON)){
			tv.setLeftView(newValue);
		} else if (key.equals(TiC.PROPERTY_RIGHT_BUTTON)){
			tv.setRightView(newValue);
		} else if (key.equals(TiC.PROPERTY_PADDING)) {
			RectF padding = TiConvert.toPaddingRect(newValue);
			TiUIHelper.setPadding(realtv, padding);
			realtv.requestLayout();
		} else {
			super.propertyChanged(key, oldValue, newValue, proxy);
		}
	}

	@Override
	public void afterTextChanged(Editable editable)
	{
		if (maxLength >= 0 && editable.length() > maxLength) {
			// The input characters are more than maxLength. We need to truncate the text and reset text.
			isTruncatingText = true;
			String newText = editable.subSequence(0, maxLength).toString();
			int cursor = realtv.getSelectionStart();
			if (cursor > maxLength) {
				cursor = maxLength;
			}
			realtv.setText(newText); // This method will invoke onTextChanged() and afterTextChanged().
			realtv.setSelection(cursor);
		} else {
			isTruncatingText = false;
		}
	}
	
    private boolean oldTextRequestLayout = false;
	@Override
    public void beforeTextChanged(CharSequence s, int start, int count,
            int after) {
        CharSequence oldText = s.subSequence(start, start + count);
        boolean newLine = oldText.toString().contains("\n");
        oldTextRequestLayout = (newLine && layoutParams.sizeOrFillHeightEnabled && !layoutParams.autoFillsHeight);
    }

	@Override
	public void onTextChanged(CharSequence s, int start, int before, int count)
	{
	    //onTextChanged can be called when reusing a TiUIText in listview
	    //In that case we dont want to report.
	    if (disableChangeEvent || realtv.willMaskText()) {
	        Log.d(TAG, "onTextChanged ignore as configuring", Log.DEBUG_MODE);
	        return;
	    }
		//Since Jelly Bean, pressing the 'return' key won't trigger onEditorAction callback
		//http://stackoverflow.com/questions/11311790/oneditoraction-is-not-called-after-enter-key-has-been-pressed-on-jelly-bean-em
		//So here we need to handle the 'return' key manually
		if (Build.VERSION.SDK_INT >= 16 && before == 0 && s.length() > start && s.charAt(start) == '\n' && hasListeners(TiC.EVENT_RETURN)) {
			//We use the previous value to make it consistent with pre Jelly Bean behavior (onEditorAction is called before 
			//onTextChanged.
			String value = TiConvert.toString(proxy.getProperty(TiC.PROPERTY_VALUE));
			KrollDict data = new KrollDict();
			data.put(TiC.PROPERTY_VALUE, value);
			fireEvent(TiC.EVENT_RETURN, data, false, false);
		}
		/**
		 * There is an Android bug regarding setting filter on EditText that impacts auto completion.
		 * Therefore we can't use filters to implement "maxLength" property. Instead we manipulate
		 * the text to achieve perfect parity with other platforms.
		 * Android bug url for reference: http://code.google.com/p/android/issues/detail?id=35757
		 */
		if (maxLength >= 0 && s.length() > maxLength) {
			// Can only set truncated text in afterTextChanged. Otherwise, it will crash.
			return;
		}
		
		boolean newLine = oldTextRequestLayout;
		if (!newLine) {
		    CharSequence newText = s.subSequence(start, start + count);
	        newLine  = newText.toString().contains("\n");
		}
        
		if (newLine && layoutParams.sizeOrFillHeightEnabled && !layoutParams.autoFillsHeight) {
		    nativeView.requestLayout();
		}
		String text = realtv.getText().toString();
		if (!isTruncatingText 
			&& proxy.shouldFireChange(proxy.getProperty(TiC.PROPERTY_VALUE), text)) {
            proxy.setProperty(TiC.PROPERTY_VALUE, text);
		    if (hasListeners(TiC.EVENT_CHANGE)) {
		        KrollDict data = new KrollDict();
	            data.put(TiC.PROPERTY_VALUE, text);
	            fireEvent(TiC.EVENT_CHANGE, data, false, false);
		    }
			
		}
	}

	@Override
	public void applyCustomBackground()
	{
		super.applyCustomBackground();
		realtv.setBackgroundDrawable(null);
		realtv.postInvalidate();
	}
	
    @Override
    public View getFocusView()
    {
    	return realtv;
    }
    
    @Override
    protected View getTouchView()
    {
        return realtv;
    }

	@Override
	public void setVisibility(int visibility)
	{
		if ((visibility == View.INVISIBLE))
			this.blur();
		super.setVisibility(visibility);
	}

	@Override
	public void onFocusChange(View v, boolean hasFocus)
	{
		
		if (v == realtv)
			Log.d(TAG, "onFocusChange "  + hasFocus + "  for FocusFixedEditText with text " + realtv.getText(), Log.DEBUG_MODE);
		else
			Log.d(TAG, "onFocusChange "  + hasFocus + "  for FocusFixedEditText  layout with text " + realtv.getText(), Log.DEBUG_MODE);
		if (!v.isFocusable()) return;
		if (hasFocus) {
			Boolean clearOnEdit = (Boolean) proxy.getProperty(TiC.PROPERTY_CLEAR_ON_EDIT);
			if (clearOnEdit != null && clearOnEdit) {
				realtv.setText("");
			}
			Rect r = new Rect();
			nativeView.getFocusedRect(r);
			nativeView.requestRectangleOnScreen(r);

		}
		else {
			tv.setDescendantFocusability(ViewGroup.FOCUS_BEFORE_DESCENDANTS);
			tv.requestFocus();
		}
		super.onFocusChange(v, hasFocus);
	}

	@Override
	protected KrollDict getFocusEventObject(boolean hasFocus)
	{
		KrollDict event = new KrollDict();
		event.put(TiC.PROPERTY_VALUE, realtv.getText().toString());
		return event;
	}

	@Override
	public boolean onEditorAction(TextView v, int actionId, KeyEvent keyEvent)
	{
		String value = realtv.getText().toString();
		

		proxy.setProperty(TiC.PROPERTY_VALUE, value);
		Log.d(TAG, "ActionID: " + actionId + " KeyEvent: " + (keyEvent != null ? keyEvent.getKeyCode() : null),
			Log.DEBUG_MODE);
		
        boolean result = false;
        boolean shouldBlur = (actionId != EditorInfo.IME_ACTION_NEXT);
        if (keyEvent == null) {
        } else if (actionId == EditorInfo.IME_NULL) {
            if (!suppressReturn) {
                shouldBlur = false;
            }
        }
		
		//This is to prevent 'return' event from being fired twice when return key is hit. In other words, when return key is clicked,
		//this callback is triggered twice (except for keys that are mapped to EditorInfo.IME_ACTION_NEXT or EditorInfo.IME_ACTION_DONE). The first check is to deal with those keys - filter out
		//one of the two callbacks, and the next checks deal with 'Next' and 'Done' callbacks, respectively.
		//Refer to TiUIText.handleReturnKeyType(int) for a list of return keys that are mapped to EditorInfo.IME_ACTION_NEXT and EditorInfo.IME_ACTION_DONE.
		if (((actionId == EditorInfo.IME_NULL && keyEvent != null) || 
				actionId == EditorInfo.IME_ACTION_NEXT || 
				actionId == EditorInfo.IME_ACTION_DONE )) {
			if (hasListeners(TiC.EVENT_RETURN)) 
			{
				KrollDict data = new KrollDict();
				data.put(TiC.PROPERTY_VALUE, value);
				fireEvent(TiC.EVENT_RETURN, data, false, false);
			}
			if (shouldBlur) {
	            blur();
	        }
		}		

		Boolean enableReturnKey = proxy.getProperties().optBoolean(TiC.PROPERTY_ENABLE_RETURN_KEY, false);
		if (enableReturnKey && value.length() == 0) {
			result = true;
		}
		
		tv.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
		return result;
	}

	public void handleKeyboard(KrollDict d) 
	{
		int type = UIModule.KEYBOARD_ASCII;
		boolean passwordMask = false;
		int autocorrect = InputType.TYPE_TEXT_FLAG_AUTO_CORRECT;
		int autoCapValue = 0;

		if (d.containsKey(TiC.PROPERTY_AUTOCORRECT) && !TiConvert.toBoolean(d, TiC.PROPERTY_AUTOCORRECT, true)) {
			autocorrect = 0;
		}

		if (d.containsKey(TiC.PROPERTY_AUTOCAPITALIZATION)) {

			switch (TiConvert.toInt(d.get(TiC.PROPERTY_AUTOCAPITALIZATION), UIModule.TEXT_AUTOCAPITALIZATION_NONE)) {
				case UIModule.TEXT_AUTOCAPITALIZATION_NONE:
					autoCapValue = 0;
					break;
				case UIModule.TEXT_AUTOCAPITALIZATION_ALL:
					autoCapValue = InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS | 
						InputType.TYPE_TEXT_FLAG_CAP_SENTENCES |
						InputType.TYPE_TEXT_FLAG_CAP_WORDS
						;
					break;
				case UIModule.TEXT_AUTOCAPITALIZATION_SENTENCES:
					autoCapValue = InputType.TYPE_TEXT_FLAG_CAP_SENTENCES;
					break;
				
				case UIModule.TEXT_AUTOCAPITALIZATION_WORDS:
					autoCapValue = InputType.TYPE_TEXT_FLAG_CAP_WORDS;
					break;
				default:
					Log.w(TAG, "Unknown AutoCapitalization Value ["+d.getString(TiC.PROPERTY_AUTOCAPITALIZATION)+"]");
				break;
			}
		}

		if (d.containsKey(TiC.PROPERTY_PASSWORD_MASK)) {
			passwordMask = TiConvert.toBoolean(d, TiC.PROPERTY_PASSWORD_MASK, false);
		}

		if (d.containsKey(TiC.PROPERTY_KEYBOARD_TYPE)) {
			type = TiConvert.toInt(d.get(TiC.PROPERTY_KEYBOARD_TYPE), UIModule.KEYBOARD_DEFAULT);
		}

		int typeModifiers = autocorrect | autoCapValue;
		int textTypeAndClass = typeModifiers;
		
		if (type != UIModule.KEYBOARD_DECIMAL_PAD) {
			textTypeAndClass = textTypeAndClass | InputType.TYPE_CLASS_TEXT;
		}

		realtv.setCursorVisible(true);
		switch(type) {
			case UIModule.KEYBOARD_DEFAULT:
			case UIModule.KEYBOARD_ASCII:
				// Don't need a key listener, inputType handles that.
				break;
			case UIModule.KEYBOARD_NUMBERS_PUNCTUATION:
				textTypeAndClass |= (InputType.TYPE_CLASS_NUMBER | InputType.TYPE_CLASS_TEXT);
				realtv.setKeyListener(new NumberKeyListener()
				{
					@Override
					public int getInputType() {
						return InputType.TYPE_CLASS_NUMBER | InputType.TYPE_CLASS_TEXT;
					}

					@Override
					protected char[] getAcceptedChars() {
						return new char[] {
							'0', '1', '2','3','4','5','6','7','8','9',
							'.','-','+','_','*','-','!','@', '#', '$',
							'%', '^', '&', '*', '(', ')', '=',
							'{', '}', '[', ']', '|', '\\', '<', '>',
							',', '?', '/', ':', ';', '\'', '"', '~'
						};
					}
				});
				break;
			case UIModule.KEYBOARD_URL:
				Log.d(TAG, "Setting keyboard type URL-3", Log.DEBUG_MODE);
				realtv.setImeOptions(EditorInfo.IME_ACTION_GO);
				textTypeAndClass |= InputType.TYPE_TEXT_VARIATION_URI;
				break;
			case UIModule.KEYBOARD_DECIMAL_PAD:
				textTypeAndClass |= (InputType.TYPE_NUMBER_FLAG_DECIMAL | InputType.TYPE_NUMBER_FLAG_SIGNED);
			case UIModule.KEYBOARD_NUMBER_PAD:
				realtv.setKeyListener(DigitsKeyListener.getInstance(true,true));
				textTypeAndClass |= InputType.TYPE_CLASS_NUMBER;
				break;
			case UIModule.KEYBOARD_PHONE_PAD:
				realtv.setKeyListener(DialerKeyListener.getInstance());
				textTypeAndClass |= InputType.TYPE_CLASS_PHONE;
				break;
			case UIModule.KEYBOARD_EMAIL:
				textTypeAndClass |= InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS;
				break;
		}
		
		if (!field) {
            textTypeAndClass |= InputType.TYPE_TEXT_FLAG_MULTI_LINE;
		}

		if (passwordMask) {
			textTypeAndClass |= InputType.TYPE_TEXT_VARIATION_PASSWORD;
			Typeface origTF = realtv.getTypeface();
			// Sometimes password transformation does not work properly when the input type is set after the transformation method.
			// This issue has been filed at http://code.google.com/p/android/issues/detail?id=7092
			realtv.setInputType(textTypeAndClass);
			// Workaround for https://code.google.com/p/android/issues/detail?id=55418 since setInputType
			// with InputType.TYPE_TEXT_VARIATION_PASSWORD sets the typeface to monospace.
            realtv.setTransformationMethod(PasswordTransformationMethod.getInstance());
			realtv.setTypeface(origTF);

			//turn off text UI in landscape mode b/c Android numeric passwords are not masked correctly in landscape mode.
			if (type == UIModule.KEYBOARD_NUMBERS_PUNCTUATION || type == UIModule.KEYBOARD_DECIMAL_PAD || type == UIModule.KEYBOARD_NUMBER_PAD) {
				realtv.setImeOptions(EditorInfo.IME_FLAG_NO_EXTRACT_UI);
			}

		} else {
			realtv.setInputType(textTypeAndClass);
			if (realtv.getTransformationMethod() instanceof PasswordTransformationMethod) {
				realtv.setTransformationMethod(null);
			}
		}
        
		
		//setSingleLine() append the flag TYPE_TEXT_FLAG_MULTI_LINE to the current inputType, so we want to call this
		//after we set inputType.
		if (!field) {
			realtv.setSingleLine(false);
		}

	}

	public void setSelection(int start, int end) 
	{
		int textLength = realtv.length();
		if (start < 0 || start > textLength || end < 0 || end > textLength) {
			Log.w(TAG, "Invalid range for text selection. Ignoring.");
			return;
		}
		realtv.setSelection(start, end);
	}
	
	public KrollDict getSelection() {
		KrollDict result = new KrollDict(2);
		int start = realtv.getSelectionStart();
		result.put(TiC.PROPERTY_LOCATION, start);
		if (start != -1) {
			int end = realtv.getSelectionEnd();
			result.put(TiC.PROPERTY_LENGTH, end - start);
		} else {
			result.put(TiC.PROPERTY_LENGTH, -1);
		}
		
		return result;
	}

	public void handleReturnKeyType(int type)
	{
		switch(type) {
			case UIModule.RETURNKEY_GO:
				realtv.setImeOptions(EditorInfo.IME_ACTION_GO);
				break;
			case UIModule.RETURNKEY_GOOGLE:
				realtv.setImeOptions(EditorInfo.IME_ACTION_GO);
				break;
			case UIModule.RETURNKEY_JOIN:
				realtv.setImeOptions(EditorInfo.IME_ACTION_DONE);
				break;
			case UIModule.RETURNKEY_NEXT:
				realtv.setImeOptions(EditorInfo.IME_ACTION_NEXT);
				break;
			case UIModule.RETURNKEY_ROUTE:
				realtv.setImeOptions(EditorInfo.IME_ACTION_DONE);
				break;
			case UIModule.RETURNKEY_SEARCH:
				realtv.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
				break;
			case UIModule.RETURNKEY_YAHOO:
				realtv.setImeOptions(EditorInfo.IME_ACTION_GO);
				break;
			case UIModule.RETURNKEY_DONE:
				realtv.setImeOptions(EditorInfo.IME_ACTION_DONE);
				break;
			case UIModule.RETURNKEY_EMERGENCY_CALL:
				realtv.setImeOptions(EditorInfo.IME_ACTION_GO);
				break;
			case UIModule.RETURNKEY_DEFAULT:
				realtv.setImeOptions(EditorInfo.IME_ACTION_UNSPECIFIED);
				break;
			case UIModule.RETURNKEY_SEND:
				realtv.setImeOptions(EditorInfo.IME_ACTION_SEND);
				break;
		}
		
		//Set input type caches ime options, so whenever we change ime options, we must reset input type
		realtv.setInputType(realtv.getInputType());
	}

	@Override
	public boolean focus()
	{
		if (!isEditable || (tv != null && tv.getVisibility() == View.INVISIBLE)) {
			return false;
		}
		return super.focus();
	}

//	@Override
//	public boolean blur()
//	{
//		if (tv != null) {
//			return tv.blur();
//		}
//		return false;
//	}
}
