part of 'driver.dart';

class Autopilot extends StatefulWidget {
  final String host;
  final int port;
  final Map<String, Handler> extraHandlers;
  final Widget child;
  final bool hideBanner;

  Autopilot({
    this.host = "localhost",
    this.port = 8080,
    this.extraHandlers = const {},
    required this.child,
    this.hideBanner = false,
  });

  @override
  _AutopilotState createState() => _AutopilotState();
}

class _AutopilotState extends State<Autopilot> {
  _Driver? driver;

  @override
  void initState() {
    super.initState();
    driver = _Driver(
      host: widget.host,
      port: widget.port,
      extraHandlers: widget.extraHandlers,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideBanner) return widget.child;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: widget.child),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ExcludeSemantics(
              child: IgnorePointer(
                ignoring: true,
                child: Container(
                  height: 20,
                  color: Colors.red.withAlpha(180),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Text(
                        "Driven by Autopilot",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
