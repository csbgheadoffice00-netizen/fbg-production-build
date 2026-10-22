import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          "App Works!",
          style: TextStyle(color: Colors.green, fontSize: 40, fontWeight: FontWeight.bold),
        ),
      ),
    ),
  ));
}