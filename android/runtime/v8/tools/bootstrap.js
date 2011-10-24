/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2011 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
var customProperties = {};

function lazyGet(object, binding, name, namespace) {
	delete object[name];
	delete object.__proto__[name];

	// deal with "value" here so we don't accidentally re-invoke the getter
	var value = object[name] = object.__proto__[name] = kroll.binding(binding)[name];
	if (namespace && namespace in customProperties) {
		Object.defineProperties(value, customProperties[namespace]);
	}
	return value;
}
exports.lazyGet = lazyGet;

exports.defineProperties = function(namespace, properties) {
	if (!(namespace in customProperties)) {
		customProperties[namespace] = {};
	}

	customProperties[namespace].extend(properties);
}

function defineLazyGetter(namespace, name, getter) {
	if (!(namespace in customProperties)) {
		customProperties[namespace] = {};
	}

	var descriptor = {
		get: function() {
			var self = this;
			while (!self.hasOwnProperty(name) && self !== null) {
				self = Object.getPrototypeOf(this);
			}
			if (self === null) {
				throw new Error("Unable to find property on prototype chain.");
			}

			delete self[name];
			var value = self[name] = getter.call(self);
			return value;
		},
		configurable: true
	};

	customProperties[namespace][name] = descriptor;
}
exports.defineLazyGetter = defineLazyGetter;

exports.defineLazyBinding = function(object, binding) {
	Object.defineProperty(object, binding, {
		get: function() {
			return lazyGet(object, binding, binding);
		},
		configurable: true
	});
}

exports.bootstrap = function(Titanium) {
	// Below this is where the generated code
	// from genBootstrap.py goes
	// ----
	%(bootstrap)s
}
