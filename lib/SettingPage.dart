import 'package:flutter/material.dart';

class SettingPage extends StatefulWidget {
  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  double threshold = 0.3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Threshold: $threshold'),
            Slider(
              value: threshold,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: threshold.toStringAsFixed(1),
              onChanged: (double value) {
                setState(() {
                  threshold = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
