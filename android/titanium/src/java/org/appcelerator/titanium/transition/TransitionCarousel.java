package org.appcelerator.titanium.transition;

import java.util.ArrayList;
import java.util.List;

import org.appcelerator.titanium.animation.RotationProperty;
import org.appcelerator.titanium.animation.ScaleProperty;
import org.appcelerator.titanium.animation.TranslationProperty;
import org.appcelerator.titanium.util.TiViewHelper;

import android.view.View;
import android.view.animation.AccelerateDecelerateInterpolator;

import com.nineoldandroids.animation.ObjectAnimator;
import com.nineoldandroids.animation.PropertyValuesHolder;
import com.nineoldandroids.view.ViewHelper;

public class TransitionCarousel extends Transition {
	private static final float translation = 0.8f;
	private static final float scale = 0.5f;
	
	private int nbFaces = 7;

	public TransitionCarousel(int subtype, boolean isOut, int duration) {
		super(subtype, isOut, duration, 400);
	}
	
	public int getType(){
		return TransitionHelper.Types.kTransitionCarousel.ordinal();
	}
	
	protected void prepareAnimators() {
		float destTranslation = translation;
		float destAngle = - (360 / nbFaces);
		
		String rotateProp = "y";
		String translateProp = "x";
		if (!TransitionHelper.isPushSubType(subType)) {
			destTranslation = -destTranslation;
			destAngle = -destAngle;
		}
		if (TransitionHelper.isVerticalSubType(subType)) {
			translateProp = "y";
			rotateProp = "x";
		}
		
		List<PropertyValuesHolder> propertiesList = new ArrayList<PropertyValuesHolder>();
		propertiesList.add(PropertyValuesHolder.ofFloat(new TranslationProperty(translateProp), destTranslation, 0.0f));
		propertiesList.add(PropertyValuesHolder.ofFloat(new ScaleProperty(), scale, 1.0f));
		propertiesList.add(PropertyValuesHolder.ofFloat(new RotationProperty(rotateProp), destAngle, 0.0f));
		inAnimator = ObjectAnimator.ofPropertyValuesHolder(null,
				propertiesList.toArray(new PropertyValuesHolder[0]));
		inAnimator.setInterpolator(new AccelerateDecelerateInterpolator());
		inAnimator.setDuration(duration);

		propertiesList = new ArrayList<PropertyValuesHolder>();
		propertiesList.add(PropertyValuesHolder.ofFloat(new TranslationProperty(translateProp), 0, -destTranslation));
		propertiesList.add(PropertyValuesHolder.ofFloat(new ScaleProperty(), 1, scale));
		propertiesList.add(PropertyValuesHolder.ofFloat(new RotationProperty(rotateProp), 0,
				-destAngle));
		outAnimator = ObjectAnimator.ofPropertyValuesHolder(null,
				propertiesList.toArray(new PropertyValuesHolder[0]));
		outAnimator.setInterpolator(new AccelerateDecelerateInterpolator());
		outAnimator.setDuration(duration);
	};

	public void setTargets(boolean reversed, View inTarget, View outTarget) {
		super.setTargets(reversed, inTarget, outTarget);
		
		float destTranslation = translation;
		float destAngle = (360 / nbFaces);
		if (reversed) {
			destTranslation = -destTranslation;
			destAngle = -destAngle;
		}
		TiViewHelper.setScale(inTarget, scale, scale);
		TiViewHelper.setTranslationFloatX(inTarget, destTranslation);
		ViewHelper.setRotationY(inTarget, destAngle);
		
	}
	
	@Override
	public void transformView(View view, float position, boolean adjustScroll) {
		float percent = Math.abs(position);
		if (percent >= nbFaces - 1)
	    {
			ViewHelper.setAlpha(view, 0);
	        return;
	    }
		double currentPercent = percent - Math.floor(percent); // between 0 and 1
		double middlePercent = 2* ((currentPercent <= 0.5)?currentPercent:1-currentPercent);
		ViewHelper.setAlpha(view, 1);
		boolean out = (position < 0);
		float multiplier = 1;
		if (!TransitionHelper.isPushSubType(subType)) {
			multiplier = -1;
			out = !out;
		}
		float angle = (360 / nbFaces);
		float rot = angle * position;
		float alpha = (Math.abs(rot) < 90.0f)?1.0f:0.0f;
		ViewHelper.setAlpha(view, alpha);
		if (TransitionHelper.isVerticalSubType(subType)) {
			TiViewHelper.setPivotFloat(view, 0.5f, out?0.0f:1.0f);
			ViewHelper.setRotationX(view, rot);
			if (!adjustScroll) TiViewHelper.setTranslationFloatY(view, position * multiplier);
		}
		else {
			TiViewHelper.setPivotFloat(view, out?0.0f:1.0f, 0.5f);
			if (!adjustScroll) TiViewHelper.setTranslationFloatX(view, position * multiplier);
			ViewHelper.setRotationY(view, rot);
		}
		TiViewHelper.setScale(view, (float) (1 - middlePercent * 0.3f));
	}
}