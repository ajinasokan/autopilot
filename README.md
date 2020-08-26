# Autopilot

A test driver for Flutter to do QA testing without sharing app source code. It exposes a JSON API using an HTTP server running inside the app. Using these APIs you can write tests in any language for your Flutter app.

## Getting started

Add [package](https://pub.dev/packages/autopilot) to pubspec:

```
dependencies:
  autopilot:
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

**GET /widgets**

Returns entire widget tree

**GET /keys**

Returns list of all the keyed widgets

**GET /texts**

Returns list of all text widgets

**GET /texts?text=&lt;text&gt;**

Returns list of all text widgets with matching text

**GET /texts?key=&lt;key&gt;**

Returns text widget that matches key

**GET /editables**

Returns list of all text fields

**GET /type?text=&lt;text&gt;**

Types given text to the focused text field

**GET /tap?x=&lt;x&gt;&y=&lt;y&gt;**

Taps at given offset

**GET /tap?key=&lt;key&gt;**

Taps on widget with given key

**GET /tap?text=&lt;text&gt;**

Taps on text widget with given text

**GET /hold?x=&lt;x&gt;&y=&lt;y&gt;**

Tap and hold on given offset

**GET /drag?x=&lt;x&gt;&y=&lt;y&gt;&dx=&lt;dx&gt;&dy=&lt;dy&gt;**

Taps at (x,y) and drags (dx, dy) offset

**GET /screenshot**

Returns screenshot of app in PNG

**GET /keyboard**

Shows keyboard

**DELETE /keyboard**

Hides keyboard

**POST /keyboard?type=&lt;type&gt;**

Submits a keyboard action.

Some actions may not be available on all platforms. See [TextInputAction](https://api.flutter.dev/flutter/services/TextInputAction-class.html) for more information.