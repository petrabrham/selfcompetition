import 'package:flutter/material.dart';

// Screens - Route Management screen
class RouteManagementScreen extends StatefulWidget {
  const RouteManagementScreen({Key? key}) : super(key: key);

  @override
  State<RouteManagementScreen> createState() => _RouteManagementScreenState();
}

class _RouteManagementScreenState extends State<RouteManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Management'),
      ),
      body: const Center(
        child: Text('Route Management Screen - TODO'),
      ),
    );
  }
}
