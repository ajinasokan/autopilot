# Autopilot

A test driver for Flutter to do QA testing without sharing app source code. It exposes a JSON API using an HTTP server running inside the app. Using these APIs you can write tests in any language for your Flutter app.

## Getting started

Create `main_test.dart` along side of your main file like this:

```dart
import 'main.dart' as app;
import 'package:autopilot/autopilot.dart';

final autopilot = Autopilot();

void main() {
    WidgetsFlutterBinding.ensureInitialized();
    
    autopilot.init();

    app.main();
}

```

Run on device/emulator:

```shell
flutter run --release --target lib/main_test.dart
```

On Android forward port 8080 so that you can access it:

```shell
adb forward tcp:8080 tcp:8080
```

Get all texts shown in app:

```shell
curl localhost:8080/texts
```

Writing tests in python using pytest:

```python
def test_answer():
    assert func(3) == 4
```

Run it:

```shell
python -m pytest flutter_test.py

================ test session starts ================
platform darwin -- Python 2.7.15, pytest-4.6.9, py-1.8.1, pluggy-0.13.1
rootdir: /Users/ajinasokan/Desktop/Tests
collected 1 item

flutter_test.py .                                        [100%]

================ 1 passed in 0.01 seconds ================
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
