module.exports = new function() {
	var finish;
	var valueOf;
	this.init = function(testUtils) {
		finish = testUtils.finish;
		valueOf = testUtils.valueOf;
	}

	this.name = "ui_clipboard";
	this.tests = [
		{name: "setAndGetText"},
		{name: "clearText"},
		{name: "setAndGetHTML"},
		{name: "setAndGetText"}
	]

	this.setAndGetText = function() {
		Ti.UI.Clipboard.setText('hello');
        valueOf(Ti.UI.Clipboard.hasText()).shouldBeTrue();
        valueOf(Ti.UI.Clipboard.getText()).shouldBe('hello');

		finish();
	}

	this.clearText = function() {
		 valueOf(function() {
            Ti.UI.Clipboard.clearText();
        }).shouldNotThrowException();
            valueOf(Ti.UI.Clipboard.hasText()).shouldBeFalse();
            // Return value of getText() varies by platform: TIMOB-9224
            // So we can't test it, but at least it shouldn't throw an exception.
        valueOf(function() {
            Ti.UI.Clipboard.getText();
        }).shouldNotThrowException();

		finish();
	}

    // Using setData to store text with a mime type.
	this.setAndGetHTML = function() {
		// Clear all data first.
        Ti.UI.Clipboard.clearData();
        Ti.UI.Clipboard.setData('text/html', "<p>How is <em>this</em> for data?</p>");
        valueOf(Ti.UI.Clipboard.hasData('text/html')).shouldBeTrue();
        valueOf(Ti.UI.Clipboard.getData('text/html'))
            .shouldBe("<p>How is <em>this</em> for data?</p>");

		finish();
	}

    // Data with mimeType 'text/url-list' or 'url' is treated as a URL on iOS, so 
    // follows a different code path than plain text or images.
	this.setAndGetText = function() {
		Ti.UI.Clipboard.clearData();
        Ti.UI.Clipboard.setData('text/url-list', "http://www.appcelerator.com");
        valueOf(Ti.UI.Clipboard.getData('text/url-list')).shouldBe("http://www.appcelerator.com");

		finish();
	}
}
