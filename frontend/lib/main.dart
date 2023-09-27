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

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;

  Future<void> registerUser(String username, String email, String password) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
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
    } catch (e) {
      // Handle exception
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    ga.sendScreenView('HomeScreen');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: _isLoading ? null : () {
            registerUser('username', 'email@example.com', 'password');
            ga.sendEvent('User Interaction', 'Button Click', label: 'Register Button');
          },
          child: _isLoading ? CircularProgressIndicator() : Text('Register'),
        ),
      ),
    );
  }
}

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
