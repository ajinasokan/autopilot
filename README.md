<a href="https://zerodha.tech"><img src="https://zerodha.tech/static/images/github-badge.svg" align="right" /></a>

# Autopilot

A test driver for Flutter to do QA testing without sharing app source code. It exposes a JSON API using an HTTP server running inside the app. Using these APIs you can write tests in any language for your Flutter app.

## Getting started

Add [package](https://pub.dev/packages/autopilot) to dependencies:

```
flutter pub add autopilot
```

Create `main_test.dart` along side of your `main.dart` file. Make AutoPilot widget parent of your MaterialApp or root widget like below:

```dart
import 'package:flutter/material.dart';
import 'package:autopilot/autopilot.dart';

import 'my_app.dart';

void main() {
  runApp(
    Autopilot(child: MyApp())
  );
}
```

Run your app on device/emulator:

```shell
flutter run --release --target lib/main_test.dart
```

On Android forward port `8080` so that you can access it via `localhost`:

```shell
adb forward tcp:8080 tcp:8080
```

Consider following example:

```dart
Text(
  "Hello World!",
  key: Key("txtGreet"),
)
```

Example of a test in python using `pytest`:

```python
# example_test.py
import requests

root = "http://localhost:8080"

def get(path):
    return requests.get(root + path).json()

def test_greet():
    greet = get("/texts?key=txtGreet")[0]
    assert greet["text"] == "Hello World!"
```

Run it:

```shell
python -m pytest example_test.py
```

## Inspiration

Flutter has a really amazing testing suite for Unit, UI and Integration testing. But one problem is that you need to know/learn Dart and you have to share the source code of the app to the person who writes tests. This doesn't work in every work environments.

But Flutter framework is so transparent I was able to tap into its internals and build a JSON API which can provide pretty much everything you need to write UI automation tests.

## APIs

**GET /widgets?parent=:widget_type**

Returns entire widget tree.

- `parent` (optional) - if provided, returns widget tree starting from the first widget of the specified type, otherwise considers the entire widget tree

**GET /keys?parent=:widget_type**

Returns list of all the keyed widgets.

- `parent` (optional) - if provided, returns only keyed widgets within the specified parent widget type, otherwise considers the entire widget tree

**GET /texts?text=:text&key=:key&parent=:widget_type**

Returns list of text widgets.

- `text` (optional) - filters widgets with matching text
- `key` (optional) - returns widget that matches key
- `parent` (optional) - if provided, searches only within the specified parent widget type, otherwise considers the entire widget tree

**GET /editables?parent=:widget_type**

Returns list of all text fields.

- `parent` (optional) - if provided, returns only text fields within the specified parent widget type, otherwise considers the entire widget tree

**GET /type?text=:text**

Types given text to the focused text field

**GET /tap?x=:x&y=:y&key=:key&text=:text&center=:center&parent=:widget_type**

Taps on screen at an offset, a key or a text.

- `x`,`y` (optional) - taps at given offset
- `key` (optional) - taps on widget with given key
- `text` (optional) - taps on text widget with given text
- `center` (optional) - set to `true` to tap at center of the widget
- `parent` (optional) - if provided, searches only within the specified parent widget type, otherwise considers the entire widget tree

**GET /hold?x=:x&y=:y**

Tap and hold on given offset

**GET /drag?x=:x&y=:y&dx=:dx&dy=:dy**

Taps at (x,y) and drags (dx, dy) offset

**GET /scroll?key=:key&dx=:dx&dy=:dy&parent=:widget_type**

Taps inside scrollable and drags.

- `key` - key of scrollable widget
- `dx`,`dy` - drag offset
- `parent` (optional) - if provided, searches only within the specified parent widget type, otherwise considers the entire widget tree

**GET /scroll-into?scrollable-key=:key&key=:key&dx=:dx&dy=:dy&delay=:delay&timeout=:timeout&parent=:widget_type**

Scrolls until target widget becomes visible.

- `scrollable-key` - key of scrollable widget
- `key` - key of widget to scroll into view
- `dx`,`dy` - drag offset
- `delay` (optional) - milliseconds between drags (default: 500)
- `timeout` (optional) - timeout in milliseconds (default: 5000)
- `parent` (optional) - if provided, searches only within the specified parent widget type, otherwise considers the entire widget tree

**GET /screenshot**

Returns screenshot of app in PNG

**GET /keyboard**

Shows keyboard

**DELETE /keyboard**

Hides keyboard

**POST /keyboard?type=:type**

Submits a keyboard action.

Some actions may not be available on all platforms. See [TextInputAction](https://api.flutter.dev/flutter/services/TextInputAction-class.html) for more information.