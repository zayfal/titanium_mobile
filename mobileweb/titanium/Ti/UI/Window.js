define(["Ti/_/declare", "Ti/Gesture", "Ti/Locale", "Ti/_/UI/SuperView", "Ti/UI"],
	function(declare, Gesture, Locale, SuperView, UI) {

	var UI_FILL = UI.FILL,
		UI_SIZE = UI.SIZE;

	return declare("Ti.UI.Window", SuperView, {
	
		_defaultWidth: UI_FILL,

		_defaultHeight: UI_FILL,

		postscript: function() {
			if (this.url) {
				var prevWindow = UI.currentWindow;
				UI._setWindow(this);
				require("Ti/_/include!sandbox!" + this.url);
				UI._setWindow(prevWindow);
			}
		},

		_getTitle: function() {
			return Locale.getString(this.titleid, this.title);
		},

		constants: {
			url: void 0
		},

		properties: {
			modal: {
				set: function(value, oldValue) {
					if (value !== oldValue) {
						if (value) {
							var parentContainer = this._modalParentContainer = UI.createView();
							parentContainer.add(UI.createView({
								backgroundColor: "#000",
								opacity: 0.5
							}));
							parentContainer.add(this._modalContentContainer = UI.createView({
								width: UI_SIZE,
								height: UI_SIZE
							}));
							this._modalContentContainer.add(this);
						} else if (this._modalParentContainer) {
							this._modalParentContainer._opened && this._modalParentContainer.close();
							this._modalContentContainer.remove(this);
							this._modalParentContainer = null;
							if (this._opened) {
								this.close(); // Close to reset state...at this point it's not attached to the window anymore, but thinks it's still open
								this.open();
							}
						}
					}
					return value;
				}
			},

			orientation: {
				get: function() {
					return Gesture.orientation;
				}
			},

			title: void 0,

			titleid: void 0
		}

	});

});