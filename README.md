# Autopilot

A test driver for Flutter to do QA testing without sharing app source code. It exposes a JSON API using an HTTP server running inside the app. Using these APIs you can write tests in any language for your Flutter app.

## Getting started

Add to pubspec:

```
dependencies:
  autopilot:
```

Create `main_test.dart` along side of your main file like this:

```dart
import 'main.dart' as app;
import 'package:autopilot/autopilot.dart';

final autopilot = Autopilot();

void main() {
    autopilot.init();
    app.main();
}
```

Run on device/emulator:

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

Writing tests in python using `pytest`:

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

Flutter has a really amazing testing suite for Unit, UI and Integration testing. But one problem is that you need to know/learn Dart and you have to share the source code of the app to the person who writes tests. This is doesn't work in every work environments.

But Flutter framework is so transparent I was able to tap into its internal and build an API which can provide pretty much everything you need to write UI automation tests.

## APIs

`root`/widgets

`root`/keys

`root`/texts

`root`/texts?text=<text>

`root`/texts?key=<key>

`root`/editables

`root`/type?text=<text>

`root`/tap?x=<x>&y=<y>

`root`/tap?key=<key>

`root`/tap?text=<text>

`root`/hold?x=<x>&y=<y>

`root`/drag?x=<x>&y=<y>&dx=<dx>&dy=<dy>

`root`/screenshot

`root`/keyboard - GET, DELETE
