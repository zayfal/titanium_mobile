function createModule(context) {
	var ti = {};

	var isApple = Ti.Platform.osname === 'ipad' || Ti.Platform.osname === 'iphone';

	function endsWith(str, suffix) {
		return str.indexOf(suffix, str.length - suffix.length) !== -1;
	}

	if (!Function.prototype.bind) {
		Function.prototype.bind = function(oThis) {
			if ( typeof this !== "function") {
				// closest thing possible to the ECMAScript 5 internal IsCallable function
				throw new TypeError("Function.prototype.bind - what is trying to be bound is not callable");
			}
			var aArgs = Array.prototype.slice.call(arguments, 1), fToBind = this, fNOP = function() {
			}, fBound = function() {
				return fToBind.apply(this instanceof fNOP && oThis ? this : oThis, aArgs.concat(Array.prototype.slice.call(arguments)));
			};
			fNOP.prototype = this.prototype;
			fBound.prototype = new fNOP();
			return fBound;
		};
	}

	module.constructors = {};

	var dipPropsToModify = ['left', 'right', 'top', 'bottom', 'width', 'height', 'font'];

	var visibleAlerts = {};

	module.alog = function(_string) {
		context.debug(_string);
	};

	module.openWindow = function(_window, _fromWindow) {
		if (_window === null || _window === undefined || _fromWindow === null || _fromWindow === undefined) {
			context.debug("can't open window");
			return;
		}
		if (!_window.modal || _window.modal === false) {
			if (_fromWindow.containingTab && context._.isFunction(_fromWindow.containingTab.openWindow)) {
				//custom tab group
				_fromWindow.containingTab.openWindow(_window);
			} else if (app.deviceinfo.isApple) {
				//Ti tabgroup
				_window.containingTab = _fromWindow.containingTab;
				_fromWindow.containingTab.open(_window);
			} else {
				_window.open({
					modal : true
				});
			}

		} else
			_window.open({
				modal : true
			});
	};

	module.defaultsModifier = function(selector, defaults) {
		if (isApple || defaults === null)
			return;
		var dipObj = _.pick(defaults, dipPropsToModify);
		for (var key in dipObj) {
			if (key === 'font') {
				if (dipObj[key].hasOwnProperty('fontSize') && typeof dipObj[key].fontSize === 'number') {
					defaults[key].fontSize = module.dPUnitsToPixels(dipObj[key].fontSize);
				}
			} else if ( typeof dipObj[key] === 'number') {
				defaults[key] = module.dPUnitsToPixels(dipObj[key]);
			}
		}
	};

	module.reduxApplyDPUnitsToPixels = function(_value) {
		if (_value === true) {
			context.redux.fn.dPUnitsToPixels = module.defaultsModifier;
		} else {
			context.redux.fn.dPUnitsToPixels = function(selector, defaults) {
			};
		}
	};

	module.adjustViewToView = function(_view, _viewRef) {
		var props = ['left', 'right', 'top', 'bottom', 'width', 'height'];
		_view.applyProperties(Object.select(_viewRef, props));
	};

	module.parseHTTPErrorMessage = function(_status, _error) {
		var result = {
			code : _status,
			title : 'Error',
			message : "There was an Error"
		};

		if (_status)
			title += ' ' + _status;

		if (_error && context._.isString(_error)) {
			result.message = _error;
			result.error = _error;
			try {
				var match = _error.match(/Code=[0-9]+(?=\s)/i);
				if (match && match.length > 0)
					result.code = match[0].replace(/Code=/i, '');
				match = _error.match(/NSLocalizedDescription=.*(?=})/i);
				if (match && match.length > 0)
					result.message = match[0].replace(/NSLocalizedDescription=/i, '');
			} catch(_error) {
				// result.message = _error;
			}
		}
		context.debug('parseHTTPErrorMessage(' + JSON.stringify(result) + ')');
		return result;
	};

	module.showAlert = function(_args) {
		_args = _args || {};
		_args.title = _args.title || 'Alert';
		_args.message = _args.message || 'This is an alert';

		var key = _args.key || (_args.title + _args.message);
		if (!Object.has(visibleAlerts, key)) {
			var alertDialog = new AlertDialog(_args);
			visibleAlerts[key] = alertDialog;
			alertDialog.addEventListener('click', function() {
				if (_args.callback)
					_args.callback();
				visibleAlerts[key] = null;
				delete visibleAlerts[key];
			});
			alertDialog.show();
		}
	};

	module.processRequestError = function(_event, _defaultMessage, _method) {
		_method = _method || ak.module.showAlert;
		_defaultMessage = _defaultMessage || 'There was an error';
		var result = module.parseHTTPErrorMessage(_event.status, _event.error ? _event.error : _defaultMessage);
		_method(result);
	};

	module.pointInRect = function(_point, _rect) {
		return (_point.x >= 0 && _point.x <= _rect.width && _point.y >= 0 && _point.y <= _rect.height );
	};

	module.rectToString = function(_rect) {
		return "{x:" + _rect.x + ",y:" + _rect.y + ",width:" + _rect.width + ",height:" + _rect.height + "}";
	};

	module.pointToString = function(_point) {
		return "{x:" + _point.x + ",y:" + _point.y + "}";
	};

	module.containsPoint = function(_args) {
		var pointInView = _args.source.convertPointToView(_args.point, _args.destination);
		if (pointInView === null)
			return false;
		return module.pointInRect(pointInView, _args.destination.rect);
	};
	module.getPlatformInfo = function() {
		var self = {};

		self.height = self.pixelHeight = Ti.Platform.displayCaps.platformHeight;
		self.width = self.pixelWidth = Ti.Platform.displayCaps.platformWidth;
		self.version = Ti.Platform.version;
		self.osname = Ti.Platform.osname;
		self.ostype = Ti.Platform.ostype;
		self.name = Ti.Platform.name;
		self.model = Ti.Platform.model;
		self.id = Ti.Platform.id;
		self.dpi = Ti.Platform.displayCaps.dpi;
		self.densityFactor = Math.round(self.dpi / 160);
		self.density = Ti.Platform.displayCaps.density;
		self.isSimulator = self.model === 'Simulator';
		self.isAndroid = self.osname === 'android';
		self.isApple = isApple;
		self.isTablet = self.osname === 'ipad';

		self.isIpad = self.osname === 'ipad';

		self.isIPhone5 = (Ti.Platform.displayCaps.platformHeight === 568);
		self.isIOS7 =self.isApple && (parseFloat(self.version)>=7);
		self.isRetina = (self.isApple && self.densityFactor === 2);
		if (self.isApple === true) {
			self.pixelWidth *= self.densityFactor;
			self.pixelHeight *= self.densityFactor;
		}
		return self;
	};
	module.getAppInfo = function() {
		var self = {};

		self.version = Ti.App.version;
		self.name = Ti.App.name;
		self.id = Ti.App.id;
		self.deployType = Ti.App.deployType;
		self.production = (Ti.App.deployType === 'production');
		self.adhoc = (Ti.App.deployType === 'test');
		self.guid = Ti.App.guid;
		self.publisher = Ti.App.publisher;
		self.guid = Ti.App.guid;

		if (this['_buildNumber'])
			self.buildNumber = _buildNumber;
		if (this['_buildDate'])
			self.buildDate = _buildDate;
		return self;
	};
	module.pixelsToDPUnits = function(ThePixels) {
		if (Ti.Platform.displayCaps.dpi > 160)
			return (ThePixels / (Ti.Platform.displayCaps.dpi / 160));
		else
			return ThePixels;
	};

	module.dPUnitsToPixels = function(TheDPUnits) {
		if (Ti.Platform.displayCaps.dpi > 160)
			return (TheDPUnits * (Ti.Platform.displayCaps.dpi / 160));
		else
			return TheDPUnits;
	};

	module.loadCreators = (function() {
		var args = Array.prototype.slice.call(arguments, 0);
		Ti.API.info('loadCreators' + JSON.stringify(args))
		for (var i = 0, l = args.length; i < l; i++) {
			if (args[i][0] !== '/')
				args[i] = '/' + args[i];
			if (!endsWith(args[i], '.js'))
				args[i] += '.js';
			var filenameWithExt = args[i].split('/').slice(-1)[0];
			var creatorName = filenameWithExt.split('.').slice(0, -1).join('.');

			context.debug('adding creator for ' + creatorName);
			{
				Ti.include(args[i]);
				context.redux.fn.addNaturalConstructor(context, module.constructors, creatorName, creatorName);
			}
		}
	}).bind(context);

	module.loadCreatorsFromDir = (function(_dir) {
		var separator = Ti.Filesystem.getSeparator();
		var dir = Ti.Filesystem.getFile(_dir);
		var dir_files = dir.getDirectoryListing();
		if (!dir_files || dir_files === null)
			return;
		var toLoad = [];
		for (var i = 0; i < dir_files.length; i++) {
			var dirFile = dir_files[i];
			if (!endsWith(dirFile, '.js'))
				continue;
			toLoad.push(_dir + separator + dirFile)
		}
		module.loadCreators.apply(null, toLoad);
	}).bind(context);

	module.loadUIModules = (function() {
		var args = Array.prototype.slice.call(arguments, 0);
		for (var i = 0, l = args.length; i < l; i++) {
			var path = args[i];
			if (path[0] !== '/')
				path = '/' + path;
			if (endsWith(path, '.js'))
				path = path.slice(0, -3);
			var creatorName = path.split('/').slice(-1)[0];

			var id = 'create' + creatorName;
			module.constructors[id] = require(path).create;

			context.debug('adding ui module for ' + creatorName);
			context.redux.fn.addNaturalConstructor(context, module.constructors, creatorName, creatorName);
		}
	}).bind(context);

	module.loadUIModulesFromDir = (function(_dir) {
		var separator = Ti.Filesystem.getSeparator();
		var dir = Ti.Filesystem.getFile(_dir);
		var dir_files = dir.getDirectoryListing();
		if (!dir_files || dir_files === null)
			return;
		var toLoad = [];
		for (var i = 0; i < dir_files.length; i++) {
			var dirFile = dir_files[i];
			if (!endsWith(dirFile, '.js'))
				continue;
			toLoad.push(_dir + separator + dirFile.slice(0, -3));
		}
		module.loadUIModules(toLoad);
	}).bind(context);

	module.loadRjssFromDir = (function(_dir) {
		Ti.API.info('loadRjssFromDir' + _dir);
		var separator = Ti.Filesystem.getSeparator();
		var dir = Ti.Filesystem.getFile(_dir);
		var dir_files = dir.getDirectoryListing();
		if (!dir_files || dir_files === null)
			return;
		for (var i = 0; i < dir_files.length; i++) {
			var dirFile = dir_files[i];
			dirFile = dirFile.replace('.rjss.compiled.js', '.rjss');
			if (!endsWith(dirFile, '.rjss'))
				continue;
			var filePath = _dir + separator + dirFile;
			ak.redux.fn.includeRJSS(filePath);
		}
	}).bind(context);

	module.loadRjss = (function() {
		var args = Array.prototype.slice.call(arguments, 0);
		for (var i = 0, l = args.length; i < l; i++) {
			if (!endsWith(args[i], '.rjss'))
				args[i] += '.rjss';
			ak.redux.fn.includeRJSS(args[i]);
		}
	}).bind(context);

	module.getOrientation = function(o) {
		switch (o) {
			case Ti.UI.PORTRAIT: {
				return 'portrait';
			}
			case Ti.UI.UPSIDE_PORTRAIT: {
				return 'portrait';
			}
			case Ti.UI.LANDSCAPE_LEFT: {
				return 'landscape';
			}
			case Ti.UI.LANDSCAPE_RIGHT: {
				return 'landscape';
			}
			default :
				return 'unknown';
		}
	};

	module.cleanUpPath = function(_path) {
		return Ti.Network.decodeURIComponent(_path).replace('file://localhost', '');
	};

	module.showNotification = function(_args) {
		_args = _args || {};
		var notif = new Notification(_args);
		notif.show();
	};
	module.addEventListener = (function(_type, _callback, _views) {
		if (_.isArray(_type) === false)
			_type = [_type];
		if (_.isArray(_views) === false)
			_views = [_views];
		for (var i = 0, len = _type.length; i < len; i++) {
			for (var j = 0, len2 = _views.length; j < len2; j++) {
				_views[j].addEventListener(_type[i], _callback);
			};
		};
	}).bind(context);

	module.removeEventListener = (function(_type, _callback, _views) {
		if (_.isArray(_type) === false)
			_type = [_type];
		if (_.isArray(_views) === false)
			_views = [_views];
		for (var i = 0, len = _type.length; i < len; i++) {
			for (var j = 0, len2 = _views.length; j < len2; j++) {
				_views[j].removeEventListener(_type[i], _callback);
			};
		};
	}).bind(context);

	module.addOpenCloseEvents = (function(_window, _array) {
		function onOpen(){
			for (var i = 0; i < _array.length; i++) {
				module.addEventListener.apply(this, _array[i]);
			};
		}
		function onClose(){
			for (var i = 0; i < _array.length; i++) {
				module.removeEventListener.apply(this, _array[i]);
			};
		}
		_window.addEventListener('open', onOpen);
		_window.addEventListener('close', onClose);
	}).bind(context);

	module.listenOnce = (function(_type, _callback, _views) {
		var realFunction = function(_event) {
			_callback(_event);
			module.removeEventListener(_type, _callback, _views);
		}
		if (_.isArray(_type) === false)
			_type = [_type];
		if (_.isArray(_views) === false)
			_views = [_views];
		for (var i = 0, len = _type.length; i < len; i++) {
			for (var j = 0, len2 = _views.length; j < len2; j++) {
				_views[j].addEventListener(_type[i], _callback);
			};
		};
	}).bind(context);

	function applyReduxToTemplate(_template, _defaultClass) {
		if (_.isObject(_template.properties)) {
			if (_template.type) {
				var realType = _.last(_template.type.split('.'));
				_template.properties = redux.fn.style(realType, _template.properties);
			} else
				_template.properties = redux.fn.style(_defaultClass, _template.properties);
		}
		if (_.isArray(_template.childTemplates)) {
			var childTemplates = _template.childTemplates;
			for (var i = 0, j = childTemplates.length; i < j; i++) {
				applyReduxToTemplate(childTemplates[i]);
			}
		}
	}


	module.prepareTemplate = function(_template) {
		applyReduxToTemplate(_template, 'View');
		return _template;
	}

	module.prepareListViewTemplate = function(_template) {
		applyReduxToTemplate(_template, 'ListItem');
		return _template;
	}

	return module;
}

if ( typeof exports === 'undefined') {
	var ti = createModule(this);
} else {
	exports.init = createModule;
}
