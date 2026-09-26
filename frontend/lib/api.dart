import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the backend lives.
///
/// Override with `flutter run --dart-define=API_URL=http://your-host:3000`.
/// Defaults: the Android emulator reaches the host PC at 10.0.2.2;
/// web and desktop builds use localhost.
String defaultApiUrl() {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class User {
  User({required this.id, required this.username, required this.email});
  final String id;
  final String username;
  final String email;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'].toString(),
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

class Service {
  Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.price,
  });
  final String id;
  final String name;
  final int durationMinutes;
  final num price;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'].toString(),
        name: json['name'] as String,
        durationMinutes: (json['durationMinutes'] as num).toInt(),
        price: json['price'] as num,
      );
}

class Appointment {
  Appointment({required this.id, required this.serviceName, required this.startsAt});
  final String id;
  final String serviceName;
  final DateTime startsAt;

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'].toString(),
        serviceName: json['serviceName'] as String? ?? 'Massage',
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
      );
}

class AuthResult {
  AuthResult(this.user, this.token);
  final User user;
  final String token;
}

/// Thin wrapper over the backend REST API.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultApiUrl(),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response res;
    try {
      res = method == 'POST'
          ? await _client.post(uri, headers: _headers, body: jsonEncode(body ?? {}))
          : await _client.get(uri, headers: _headers);
    } catch (_) {
      throw ApiException(
        "Can't reach the server at $baseUrl. Is the backend running?",
      );
    }
    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (res.statusCode >= 400) {
      throw ApiException(data['message'] as String? ?? 'Request failed (${res.statusCode}).');
    }
    return data;
  }

  Future<AuthResult> register(String username, String email, String password) async {
    final data = await _send('POST', '/register', {
      'username': username,
      'email': email,
      'password': password,
    });
    return _auth(data);
  }

  Future<AuthResult> login(String email, String password) async {
    final data = await _send('POST', '/login', {'email': email, 'password': password});
    return _auth(data);
  }

  AuthResult _auth(Map<String, dynamic> data) {
    token = data['token'] as String;
    return AuthResult(User.fromJson(data['user'] as Map<String, dynamic>), token!);
  }

  void logout() => token = null;

  Future<List<Service>> services() async {
    final data = await _send('GET', '/services');
    return (data['services'] as List)
        .map((e) => Service.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Appointment>> appointments() async {
    final data = await _send('GET', '/appointments');
    final list = (data['appointments'] as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return list;
  }

  Future<Appointment> book(String serviceId, DateTime startsAt) async {
    final data = await _send('POST', '/appointments', {
      'serviceId': serviceId,
      'startsAt': startsAt.toUtc().toIso8601String(),
    });
    return Appointment.fromJson(data['appointment'] as Map<String, dynamic>);
  }
}
