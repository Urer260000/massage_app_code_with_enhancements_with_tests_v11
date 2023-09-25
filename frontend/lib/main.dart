import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_analytics/google_analytics.dart';

final GoogleAnalytics ga = GoogleAnalytics(trackingId: 'ACTUAL_TRACKING_ID');

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (context) => HomeScreen(),
        '/profile': (context) => ProfileScreen(),
        '/booking': (context) => BookingScreen(),
      },
      initialRoute: '/',
    );
  }
}

class HomeScreen extends StatelessWidget {
  Future<void> registerUser(String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('http://actual_backend_url/register'),
      body: {
        'username': username,
        'email': email,
        'password': password,
      },
    );

    if (response.statusCode == 201) {
      // User registered successfully
    } else {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            registerUser('username', 'email@example.com', 'password');
            ga.sendEvent('User Interaction', 'Button Click', label: 'Register Button');
          },
          child: Text('Register'),
        ),
      ),
    );
  }
}

// ... rest of your code


class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: Center(
        child: Text('Profile Screen'),
      ),
    );
  }
}
// Screen Tracking in initState
@override
void initState() {
  super.initState();
  ga.sendScreenView('HomeScreen');
}

class BookingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Booking')),
      body: Center(
        child: Text('Booking Screen'),
      ),
    );
  }
}
