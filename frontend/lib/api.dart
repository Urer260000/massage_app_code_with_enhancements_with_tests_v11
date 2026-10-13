import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'session_storage.dart';

/// Where the backend lives.
///
/// Override with `flutter run --dart-define=API_URL=https://your-host`.
/// Defaults: the Android emulator reaches the host PC at 10.0.2.2;
/// web and desktop builds use localhost. Production builds should always
/// pass an https:// URL.
String defaultApiUrl() {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.sessionExpired = false});
  final String message;
  final int? statusCode;

  /// The guest has been signed out and needs to log in again.
  final bool sessionExpired;

  @override
  String toString() => message;
}

class User {
  User({
    required this.id,
    required this.username,
    required this.email,
    this.role = 'guest',
    this.emailVerified = false,
  });
  final String id;
  final String username;
  final String email;
  final String role;
  final bool emailVerified;

  bool get isStaff => role == 'admin';

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    username: json['username'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? 'guest',
    emailVerified: json['emailVerified'] as bool? ?? false,
  );
}

class Service {
  Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.price,
    this.signature,
    this.description,
    this.active = true,
  });
  final String id;
  final String name;
  final int durationMinutes;
  final num price;

  /// House name for the treatment, e.g. "The Gatsby".
  final String? signature;
  final String? description;
  final bool active;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
    id: json['id'].toString(),
    name: json['name'] as String,
    durationMinutes: (json['durationMinutes'] as num).toInt(),
    price: json['price'] as num,
    signature: json['signature'] as String?,
    description: json['description'] as String?,
    active: json['active'] as bool? ?? true,
  );
}

class Therapist {
  Therapist({required this.id, required this.name, this.bio});
  final String id;
  final String name;
  final String? bio;

  factory Therapist.fromJson(Map<String, dynamic> json) =>
      Therapist(id: json['id'].toString(), name: json['name'] as String, bio: json['bio'] as String?);
}

/// A bookable start time. [time] is the spa's local time, e.g. "14:30".
class Slot {
  Slot({required this.time, required this.startsAt, required this.available, this.past = false});
  final String time;
  final String startsAt;
  final bool available;

  /// Too soon to book (or already gone), as opposed to taken by someone else.
  final bool past;

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
    time: json['time'] as String,
    startsAt: json['startsAt'] as String,
    available: json['available'] as bool,
    past: json['past'] as bool? ?? false,
  );
}

class DayAvailability {
  DayAvailability({required this.date, required this.available});

  /// Spa-local date, `YYYY-MM-DD`.
  final String date;
  final bool available;

  factory DayAvailability.fromJson(Map<String, dynamic> json) =>
      DayAvailability(date: json['date'] as String, available: json['available'] as bool);
}

class Review {
  Review({required this.rating, this.comment});
  final int rating;
  final String? comment;

  factory Review.fromJson(Map<String, dynamic> json) =>
      Review(rating: (json['rating'] as num).toInt(), comment: json['comment'] as String?);
}

class Appointment {
  Appointment({
    required this.id,
    required this.serviceName,
    required this.startsAt,
    this.serviceId,
    this.kind = 'booking',
    this.price,
    this.durationMinutes,
    this.therapistId,
    this.therapistName,
    this.localDate,
    this.localTime,
    this.status = 'confirmed',
    this.notes,
    this.pressure,
    this.review,
    this.isPast = false,
    this.canChange = false,
    this.guestName,
    this.guestEmail,
  });

  final String id;
  final String kind;
  final String? serviceId;
  final String serviceName;
  final num? price;
  final int? durationMinutes;
  final String? therapistId;
  final String? therapistName;
  final DateTime startsAt;

  /// Spa-local date (`YYYY-MM-DD`) and time (`HH:mm`), so times read the same on every phone.
  final String? localDate;
  final String? localTime;
  final String status;
  final String? notes;
  final String? pressure;
  final Review? review;
  final bool isPast;
  final bool canChange;
  final String? guestName;
  final String? guestEmail;

  bool get isBlock => kind == 'block';
  bool get isUpcoming => status == 'confirmed' && !isPast;

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
    id: json['id'].toString(),
    kind: json['kind'] as String? ?? 'booking',
    serviceId: json['serviceId'] as String?,
    serviceName: json['serviceName'] as String? ?? 'Massage',
    price: json['price'] as num?,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
    therapistId: json['therapistId'] as String?,
    therapistName: json['therapistName'] as String?,
    startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
    localDate: json['localDate'] as String?,
    localTime: json['localTime'] as String?,
    status: json['status'] as String? ?? 'confirmed',
    notes: json['notes'] as String?,
    pressure: json['pressure'] as String?,
    review: json['review'] == null ? null : Review.fromJson(json['review'] as Map<String, dynamic>),
    isPast: json['isPast'] as bool? ?? false,
    canChange: json['canChange'] as bool? ?? false,
    guestName: json['guestName'] as String?,
    guestEmail: json['guestEmail'] as String?,
  );
}

class SpaInfo {
  SpaInfo({
    required this.name,
    required this.timezone,
    required this.openHour,
    required this.closeHour,
    required this.cancelCutoffHours,
    required this.address,
    required this.phone,
    required this.email,
    required this.about,
    this.closedWeekdays = const [],
  });
  final String name;
  final String timezone;
  final int openHour;
  final int closeHour;
  final int cancelCutoffHours;
  final String address;
  final String phone;
  final String email;
  final String about;
  final List<int> closedWeekdays;

  factory SpaInfo.fromJson(Map<String, dynamic> json) => SpaInfo(
    name: json['name'] as String? ?? 'the20sspa',
    timezone: json['timezone'] as String? ?? '',
    openHour: (json['openHour'] as num?)?.toInt() ?? 10,
    closeHour: (json['closeHour'] as num?)?.toInt() ?? 20,
    cancelCutoffHours: (json['cancelCutoffHours'] as num?)?.toInt() ?? 24,
    address: json['address'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    about: json['about'] as String? ?? '',
    closedWeekdays: ((json['closedWeekdays'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
  );
}

class AuthResult {
  AuthResult(this.user, this.token, {this.devCode});
  final User user;
  final String token;

  /// Local testing only: the emailed code, when the server has no real email set up.
  final String? devCode;
}

/// A staff view of one spa day.
class StaffDay {
  StaffDay({required this.date, required this.therapists, required this.appointments});
  final String date;
  final List<Therapist> therapists;
  final List<Appointment> appointments;
}

/// Thin wrapper over the backend REST API.
///
/// Access tokens last 15 minutes. When one expires, the client swaps the
/// refresh token for a new pair and retries once, so guests aren't bounced
/// to the login screen mid-booking. The refresh token is saved in
/// [SessionStorage] so the app opens signed in.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client, SessionStorage? storage})
    : baseUrl = baseUrl ?? defaultApiUrl(),
      _client = client ?? http.Client(),
      _storage = storage ?? MemorySessionStorage();

  final String baseUrl;
  final http.Client _client;
  final SessionStorage _storage;
  String? token;
  String? _refreshToken;
  Future<bool>? _refreshing;

  /// Local testing only: the last emailed code the server handed back.
  String? lastDevCode;

  /// Called when the session can't be renewed and the guest must log in again.
  VoidCallback? onSessionExpired;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool retry = true,
  }) async {
    final uri = Uri.parse('$baseUrl/v1$path');
    http.Response res;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      res = switch (method) {
        'POST' => await _client.post(uri, headers: _headers, body: encoded ?? '{}'),
        'PATCH' => await _client.patch(uri, headers: _headers, body: encoded ?? '{}'),
        'DELETE' => await _client.delete(uri, headers: _headers, body: encoded),
        _ => await _client.get(uri, headers: _headers),
      };
    } catch (_) {
      throw ApiException("Can't reach the spa right now. Check your connection and try again.");
    }
    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (res.statusCode == 401 && retry && token != null && _refreshToken != null) {
      if (await _refresh()) return _send(method, path, body: body, retry: false);
      await _endSession();
      onSessionExpired?.call();
      throw ApiException('Your session has ended. Please log in again.', statusCode: 401, sessionExpired: true);
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        data['message'] as String? ?? 'Something went wrong (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    return data;
  }

  /// Swaps the refresh token for a new pair. Concurrent callers share one request.
  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final data = await _send('POST', '/auth/refresh', body: {'refreshToken': _refreshToken}, retry: false);
        await _auth(data);
        return true;
      } on ApiException {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<AuthResult> _auth(Map<String, dynamic> data) async {
    token = data['token'] as String;
    _refreshToken = data['refreshToken'] as String?;
    if (_refreshToken != null) await _storage.write(_refreshToken!);
    lastDevCode = data['devCode'] as String? ?? lastDevCode;
    return AuthResult(User.fromJson(data['user'] as Map<String, dynamic>), token!, devCode: data['devCode'] as String?);
  }

  Future<void> _endSession() async {
    token = null;
    lastDevCode = null;
    _refreshToken = null;
    await _storage.clear();
  }

  // ---------- Sessions ----------

  /// Signs back in with the saved refresh token, or returns null.
  Future<User?> restoreSession() async {
    final saved = await _storage.read();
    if (saved == null) return null;
    _refreshToken = saved;
    try {
      final data = await _send('POST', '/auth/refresh', body: {'refreshToken': saved}, retry: false);
      return (await _auth(data)).user;
    } on ApiException catch (e) {
      // Offline: keep the saved token for next time. Rejected: forget it.
      if (e.statusCode != null) await _endSession();
      return null;
    }
  }

  Future<AuthResult> register(String username, String email, String password) async {
    final data = await _send('POST', '/register', body: {'username': username, 'email': email, 'password': password});
    return _auth(data);
  }

  Future<AuthResult> login(String email, String password) async {
    final data = await _send('POST', '/login', body: {'email': email, 'password': password});
    return _auth(data);
  }

  Future<void> logout() async {
    if (token != null) {
      try {
        await _send('POST', '/logout', retry: false);
      } on ApiException {
        // Signing out locally is what matters.
      }
    }
    await _endSession();
  }

  /// Returns the code itself in local testing mode, otherwise null.
  Future<String?> forgotPassword(String email) async {
    final data = await _send('POST', '/password/forgot', body: {'email': email});
    return data['devCode'] as String?;
  }

  Future<AuthResult> resetPassword(String email, String code, String newPassword) async {
    final data = await _send(
      'POST',
      '/password/reset',
      body: {'email': email, 'code': code, 'newPassword': newPassword},
    );
    return _auth(data);
  }

  // ---------- Account ----------

  Future<User> me() async => User.fromJson((await _send('GET', '/me'))['user'] as Map<String, dynamic>);

  Future<User> updateName(String username) async =>
      User.fromJson((await _send('PATCH', '/me', body: {'username': username}))['user'] as Map<String, dynamic>);

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final data = await _send(
      'POST',
      '/me/password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    await _auth(data);
  }

  Future<User> verifyEmail(String code) async =>
      User.fromJson((await _send('POST', '/me/verify-email', body: {'code': code}))['user'] as Map<String, dynamic>);

  /// Returns the code itself in local testing mode, otherwise null.
  Future<String?> resendVerification() async {
    final code = (await _send('POST', '/me/verify-email/resend'))['devCode'] as String?;
    return lastDevCode = code ?? lastDevCode;
  }

  Future<void> deleteAccount(String password) async {
    await _send('DELETE', '/me', body: {'password': password});
    await _endSession();
  }

  // ---------- Menu and availability ----------

  Future<List<Service>> services() async {
    final data = await _send('GET', '/services');
    return (data['services'] as List).map((e) => Service.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SpaInfo> spaInfo() async => SpaInfo.fromJson((await _send('GET', '/spa'))['spa'] as Map<String, dynamic>);

  Future<List<Therapist>> therapists(String serviceId) async {
    final data = await _send('GET', '/therapists?serviceId=${Uri.encodeQueryComponent(serviceId)}');
    return (data['therapists'] as List).map((e) => Therapist.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _who(String? therapistId) =>
      therapistId == null ? '' : '&therapistId=${Uri.encodeQueryComponent(therapistId)}';

  Future<List<DayAvailability>> availabilityDays(String serviceId, {String? therapistId}) async {
    final data = await _send(
      'GET',
      '/availability/days?serviceId=${Uri.encodeQueryComponent(serviceId)}${_who(therapistId)}',
    );
    return (data['days'] as List).map((e) => DayAvailability.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Slot>> availability(String serviceId, String date, {String? therapistId}) async {
    final data = await _send(
      'GET',
      '/availability?serviceId=${Uri.encodeQueryComponent(serviceId)}&date=$date${_who(therapistId)}',
    );
    return (data['slots'] as List).map((e) => Slot.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------- Reservations ----------

  /// [scope] is `upcoming`, `past` or `all`.
  Future<List<Appointment>> appointments({String scope = 'all'}) async {
    final data = await _send('GET', '/appointments?scope=$scope&limit=100');
    return (data['appointments'] as List).map((e) => Appointment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Appointment> book(
    String serviceId,
    String startsAt, {
    String? therapistId,
    String? notes,
    String? pressure,
  }) async {
    final data = await _send(
      'POST',
      '/appointments',
      body: {
        'serviceId': serviceId,
        'startsAt': startsAt,
        if (therapistId != null) 'therapistId': therapistId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (pressure != null) 'pressure': pressure,
      },
    );
    return Appointment.fromJson(data['appointment'] as Map<String, dynamic>);
  }

  Future<Appointment> reschedule(String id, String startsAt, {String? therapistId}) async {
    final data = await _send(
      'PATCH',
      '/appointments/$id',
      body: {'startsAt': startsAt, if (therapistId != null) 'therapistId': therapistId},
    );
    return Appointment.fromJson(data['appointment'] as Map<String, dynamic>);
  }

  Future<Appointment> cancel(String id) async =>
      Appointment.fromJson((await _send('DELETE', '/appointments/$id'))['appointment'] as Map<String, dynamic>);

  Future<Appointment> review(String id, int rating, {String? comment}) async {
    final data = await _send(
      'POST',
      '/appointments/$id/review',
      body: {'rating': rating, if (comment != null && comment.isNotEmpty) 'comment': comment},
    );
    return Appointment.fromJson(data['appointment'] as Map<String, dynamic>);
  }

  Future<String> joinWaitlist(String serviceId, String date) async {
    final data = await _send('POST', '/waitlist', body: {'serviceId': serviceId, 'date': date});
    return data['message'] as String? ?? "You're on the waitlist.";
  }

  // ---------- Staff ----------

  Future<StaffDay> staffDay(String date) async {
    final data = await _send('GET', '/admin/appointments?date=$date');
    return StaffDay(
      date: data['date'] as String,
      therapists: (data['therapists'] as List).map((e) => Therapist.fromJson(e as Map<String, dynamic>)).toList(),
      appointments: (data['appointments'] as List).map((e) => Appointment.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> setStatus(String id, String status) async {
    await _send('PATCH', '/admin/appointments/$id', body: {'status': status});
  }

  /// Blocks a therapist's time from a spa-local [date] (`YYYY-MM-DD`) and [time] (`HH:mm`).
  Future<void> blockTime(String therapistId, String date, String time, int durationMinutes, {String? reason}) async {
    await _send(
      'POST',
      '/admin/blocks',
      body: {
        'therapistId': therapistId,
        'date': date,
        'time': time,
        'durationMinutes': durationMinutes,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  Future<List<Service>> allServices() async {
    final data = await _send('GET', '/admin/services');
    return (data['services'] as List).map((e) => Service.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Service> updateService(String id, {num? price, bool? active}) async {
    final data = await _send(
      'PATCH',
      '/admin/services/$id',
      body: {if (price != null) 'price': price, if (active != null) 'active': active},
    );
    return Service.fromJson(data['service'] as Map<String, dynamic>);
  }
}
