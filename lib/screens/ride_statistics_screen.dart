import 'package:flutter/material.dart';

// Screens - Ride Statistics screen
class RideStatisticsScreen extends StatefulWidget {
  const RideStatisticsScreen({Key? key}) : super(key: key);

  @override
  State<RideStatisticsScreen> createState() => _RideStatisticsScreenState();
}

class _RideStatisticsScreenState extends State<RideStatisticsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Statistics'),
      ),
      body: const Center(
        child: Text('Ride Statistics Screen - TODO'),
      ),
    );
  }
}
