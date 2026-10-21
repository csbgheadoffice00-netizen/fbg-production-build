import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  int? savedUserId;
  String? savedEmail;

  // Safety try-catch for Huawei/HarmonyOS
  try {
    final prefs = await SharedPreferences.getInstance();
    savedUserId = prefs.getInt('user_id');
    savedEmail = prefs.getString('user_email');
  } catch (e) {
    // If Huawei blocks the storage, we just ignore it and show the login screen
    print("Storage blocked: $e");
  }

  runApp(MyApp(
    initialUserId: savedUserId,
    initialEmail: savedEmail,
  ));
}

class MyApp extends StatelessWidget {
  final int? initialUserId;
  final String? initialEmail;

  const MyApp({super.key, this.initialUserId, this.initialEmail});

  @override
  Widget build(BuildContext context) {
    const Color neonGreen = Color(0xFF00FF41);
    const Color darkBg = Color(0xFF0F0F0F);
    const Color darkCard = Color(0xFF1A1A1A);

    return MaterialApp(
      title: 'FBG SMS',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: neonGreen,
        scaffoldBackgroundColor: darkBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkCard,
          foregroundColor: neonGreen,
          elevation: 0,
        ),
        cardColor: darkCard,
        cardTheme: CardThemeData(
          color: darkCard,
          elevation: 8,
          shadowColor: neonGreen.withOpacity(0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: neonGreen.withOpacity(0.3), width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: neonGreen,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: neonGreen,
            side: const BorderSide(color: neonGreen),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: neonGreen.withOpacity(0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: neonGreen.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: neonGreen, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIconColor: neonGreen,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkCard,
          selectedItemColor: neonGreen,
          unselectedItemColor: Colors.grey,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        colorScheme: const ColorScheme.dark(
          primary: neonGreen,
          secondary: neonGreen,
          surface: darkCard,
        ),
      ),
      // Auto-login if session exists
      home: initialUserId != null && initialEmail != null
          ? HomeScreen(userId: initialUserId!, email: initialEmail!)
          : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============== SERVICE ICON MAPPER ==============
FaIconData getServiceIcon(String code) {
  final Map<String, FaIconData> map = {
    "wa": FontAwesomeIcons.whatsapp, "tg": FontAwesomeIcons.telegram,
    "fb": FontAwesomeIcons.facebookF, "ig": FontAwesomeIcons.instagram,
    "lf": FontAwesomeIcons.tiktok, "tw": FontAwesomeIcons.xTwitter,
    "ds": FontAwesomeIcons.discord, "go": FontAwesomeIcons.google,
    "am": FontAwesomeIcons.amazon, "mm": FontAwesomeIcons.microsoft,
    "ub": FontAwesomeIcons.uber, "nf": FontAwesomeIcons.play,
    "dr": FontAwesomeIcons.robot, "wb": FontAwesomeIcons.weixin,
    "ccu": FontAwesomeIcons.google, "sp": FontAwesomeIcons.spotify,
    "pn": FontAwesomeIcons.pinterest, "rd": FontAwesomeIcons.reddit,
    "sc": FontAwesomeIcons.snapchat, "li": FontAwesomeIcons.linkedin,
    "sk": FontAwesomeIcons.skype, "vb": FontAwesomeIcons.viber,
    "ap": FontAwesomeIcons.apple, "sh": FontAwesomeIcons.shopify,
    "eb": FontAwesomeIcons.ebay, "sf": FontAwesomeIcons.salesforce,
    "py": FontAwesomeIcons.paypal, "st": FontAwesomeIcons.steam,
    "gh": FontAwesomeIcons.github, "yt": FontAwesomeIcons.youtube,
    "yahoo": FontAwesomeIcons.yahoo, "mb": FontAwesomeIcons.yahoo,
    "bt": FontAwesomeIcons.bitcoin, "eth": FontAwesomeIcons.ethereum,
    "sl": FontAwesomeIcons.slack, "zm": FontAwesomeIcons.video,
    "ts": FontAwesomeIcons.twitch, "wp": FontAwesomeIcons.whatsapp,
    "wd": FontAwesomeIcons.microsoft,
  };
  return map[code] ?? FontAwesomeIcons.globe;
}

Color getServiceColor(String code) {
  final map = <String, Color>{
    "wa": const Color(0xFF25D366), "tg": const Color(0xFF229ED9),
    "fb": const Color(0xFF1877F2), "ig": const Color(0xFFE1306C),
    "lf": const Color(0xFF000000), "tw": const Color(0xFF000000),
    "ds": const Color(0xFF5865F2), "go": const Color(0xFF4285F4),
    "am": const Color(0xFFFF9900), "mm": const Color(0xFF00A4EF),
    "ub": const Color(0xFF000000), "nf": const Color(0xFFE50914),
    "wb": const Color(0xFF07C160), "sp": const Color(0xFF1DB954),
    "py": const Color(0xFF003087), "eb": const Color(0xFFE53238),
    "st": const Color(0xFF171A21), "yt": const Color(0xFFFF0000),
    "li": const Color(0xFF0077B5), "rd": const Color(0xFFFF4500),
    "sc": const Color(0xFFFFFC00),
  };
  return map[code] ?? Colors.grey[700]!;
}

// ============== LOGIN / REGISTER SCREEN ==============
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _referralController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";
  bool _showReferralField = false;

  Future<void> _submit(bool isRegister, {bool withReferral = false}) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final referral = withReferral ? _referralController.text.trim().toUpperCase() : "";

    if (email.isEmpty) { setState(() => _errorMessage = "Please enter your email."); return; }
    if (!email.contains("@") || !email.contains(".")) { setState(() => _errorMessage = "Please enter a valid email address."); return; }
    if (password.isEmpty) { setState(() => _errorMessage = "Please enter a password."); return; }
    if (password.length < 6) { setState(() => _errorMessage = "Password must be at least 6 characters."); return; }
    if (withReferral && referral.isEmpty) { setState(() => _errorMessage = "Please enter the referral code."); return; }

    setState(() { _isLoading = true; _errorMessage = ""; });
    final endpoint = isRegister ? '/api/register' : '/api/login';
    final url = Uri.parse('https://grizzly-sms-backend.onrender.com$endpoint');
    
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password, "referral_code": referral}),
      );
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        // SAVE SESSION
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', data['user_id']);
          await prefs.setString('user_email', data['email']);
        } catch (e) {
          print("Could not save session: $e");
        }

        if (isRegister) {
          await http.post(
            Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/request-code'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email": email}),
          );
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => VerifyEmailScreen(email: email)));
        } else {
          if (data['is_verified'] == false) {
            await http.post(
              Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/request-code'),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"email": email}),
            );
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => VerifyEmailScreen(email: email)));
          } else {
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(userId: data['user_id'], email: data['email'])));
          }
        }
      } else {
        setState(() => _errorMessage = data['detail'] ?? "Something went wrong");
      }
    } catch (e) {
      setState(() => _errorMessage = "Connection failed. Is your server running?");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPassword() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Reset Password", style: TextStyle(color: Color(0xFF00FF41))),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Enter your email"),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Send Code"),
          ),
        ],
      ),
    );

    if (email != null && email.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/forgot-password'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"email": email}),
        );
        if (res.statusCode == 200) {
          if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => ResetPasswordScreen(email: email)));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email not found"), backgroundColor: Colors.red));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection error"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/icon.png'),
            fit: BoxFit.cover,
            opacity: 0.15,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sms, size: 80, color: Color(0xFF00FF41)),
                const SizedBox(height: 20),
                const Text("FBG SMS", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00FF41), letterSpacing: 2)),
                const SizedBox(height: 40),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 15),
                TextField(controller: _passwordController, decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)), obscureText: true),
                if (_showReferralField) ...[
                  const SizedBox(height: 15),
                  TextField(
                    controller: _referralController,
                    decoration: const InputDecoration(
                      labelText: "Referral Code",
                      hintText: "FBG-XXXXXX",
                      prefixIcon: Icon(Icons.card_giftcard, color: Colors.orange),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPassword,
                    child: const Text("Forgot Password?", style: TextStyle(color: Colors.grey)),
                  ),
                ),
                if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                if (_isLoading) const CircularProgressIndicator(color: Color(0xFF00FF41)),
                if (!_isLoading) ...[
                  ElevatedButton(onPressed: () => _submit(false), style: ElevatedButton.styleFrom(minimumSize: const Size(250, 50)), child: const Text("Login")),
                  const SizedBox(height: 10),
                  if (!_showReferralField)
                    OutlinedButton.icon(
                      onPressed: () => _submit(true),
                      icon: const Icon(Icons.person_add),
                      label: const Text("Create Account"),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(250, 50)),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _submit(true, withReferral: true),
                      icon: const Icon(Icons.card_giftcard),
                      label: const Text("Create Account with Referral"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(250, 50),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() {
                      _showReferralField = !_showReferralField;
                      _errorMessage = "";
                    }),
                    child: Text(
                      _showReferralField ? "Back to normal signup" : "Have a referral code? Tap here",
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============== VERIFY EMAIL SCREEN ==============
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) { setState(() => _errorMessage = "Enter the 6-digit code."); return; }

    setState(() { _isLoading = true; _errorMessage = ""; });
    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/verify-code'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.email, "code": code}),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account Verified! Please log in."), backgroundColor: Colors.green));
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() => _errorMessage = data['detail'] ?? "Invalid code");
      }
    } catch (e) {
      setState(() => _errorMessage = "Connection failed.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread, size: 80, color: Color(0xFF00FF41)),
              const SizedBox(height: 20),
              Text("We sent a code to ${widget.email}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: "6-Digit Code"),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              if (_isLoading) const CircularProgressIndicator(color: Color(0xFF00FF41)),
              if (!_isLoading)
                ElevatedButton(
                  onPressed: _verify,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(250, 50)),
                  child: const Text("Verify & Continue"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== RESET PASSWORD SCREEN ==============
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";

  Future<void> _reset() async {
    final code = _codeController.text.trim();
    final newPass = _passController.text;

    if (code.isEmpty || newPass.length < 6) {
      setState(() => _errorMessage = "Enter code and a password (min 6 chars).");
      return;
    }

    setState(() { _isLoading = true; _errorMessage = ""; });
    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/reset-password'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.email, "code": code, "new_password": newPass}),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password Reset! Please log in."), backgroundColor: Colors.green));
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() => _errorMessage = data['detail'] ?? "Invalid code");
      }
    } catch (e) {
      setState(() => _errorMessage = "Connection failed.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_reset, size: 80, color: Color(0xFF00FF41)),
              const SizedBox(height: 20),
              Text("Enter the code sent to ${widget.email}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: "6-Digit Code"),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passController,
                decoration: const InputDecoration(labelText: "New Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              if (_isLoading) const CircularProgressIndicator(color: Color(0xFF00FF41)),
              if (!_isLoading)
                ElevatedButton(
                  onPressed: _reset,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(250, 50)),
                  child: const Text("Reset Password"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== SHARED APP STATE ==============
class ActiveNumber {
  String activationId;
  String phoneNumber;
  String service;
  int country;
  int secondsRemaining;
  String smsCode;
  Timer? countdownTimer;
  Timer? pollingTimer;
  Timer? timeoutTimer;

  ActiveNumber({
    required this.activationId,
    required this.phoneNumber,
    required this.service,
    required this.country,
    this.secondsRemaining = 120,
    this.smsCode = "",
  });

  void disposeTimers() {
    countdownTimer?.cancel();
    pollingTimer?.cancel();
    timeoutTimer?.cancel();
  }
}

class MainAppState extends ChangeNotifier {
  int userId;
  String email;
  double balance = 0.0;
  String referralCode = "";
  int referralCount = 0;
  double referralEarnings = 0.0;
  List<ActiveNumber> activeNumbers = [];
  int historyVersion = 0;

  MainAppState({required this.userId, required this.email});

  Future<void> refreshBalance() async {
    try {
      final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/user/$userId');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        balance = (data['balance'] ?? 0).toDouble();
        referralCode = data['referral_code'] ?? "";
        referralCount = data['referral_count'] ?? 0;
        referralEarnings = (data['referral_earnings'] ?? 0).toDouble();
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> checkForActiveNumbers() async {
    try {
      final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/active/$userId');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['has_active'] == true) {
          List<dynamic> activations = data['activations'] ?? [];
          for (var act in activations) {
            var newActive = ActiveNumber(
              activationId: act['activation_id'].toString(),
              phoneNumber: act['phone_number'].toString(),
              service: act['service'].toString(),
              country: int.tryParse(act['country'].toString()) ?? 0,
            );
            activeNumbers.add(newActive);
            _startTimers(newActive);
          }
          notifyListeners();
        }
      }
    } catch (e) {}
  }

  void startNewActivation({required String phone, required String activationId, required String service, required int country}) {
    var newActive = ActiveNumber(
      activationId: activationId,
      phoneNumber: phone,
      service: service,
      country: country,
    );
    activeNumbers.add(newActive);
    historyVersion++;
    _startTimers(newActive);
    notifyListeners();
  }

  void _startTimers(ActiveNumber active) {
    active.countdownTimer?.cancel();
    active.pollingTimer?.cancel();
    active.timeoutTimer?.cancel();

    active.countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (active.secondsRemaining <= 1) { timer.cancel(); }
      else { active.secondsRemaining--; notifyListeners(); }
    });

    active.pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (active.activationId.isEmpty || active.smsCode.isNotEmpty) { timer.cancel(); return; }
      final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/check-sms/${active.activationId}');
      try {
        final response = await http.get(url);
        if (response.body.contains("STATUS_OK")) {
          final code = response.body.split(":").last.replaceAll('"', '').replaceAll('}', '');
          active.smsCode = code;
          historyVersion++;
          active.pollingTimer?.cancel();
          active.timeoutTimer?.cancel();
          active.countdownTimer?.cancel();
          notifyListeners();
        }
      } catch (e) {}
    });

    active.timeoutTimer = Timer(const Duration(seconds: 120), () {
      if (active.smsCode.isEmpty && active.activationId.isNotEmpty) {
        cancelActivation(active);
      }
    });
  }

  Future<void> cancelActivation(ActiveNumber active) async {
    active.pollingTimer?.cancel();
    active.timeoutTimer?.cancel();
    active.countdownTimer?.cancel();
    if (active.activationId.isEmpty) return;
    
    final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/cancel/${active.activationId}');
    try { await http.post(url); } catch (e) {}
    
    activeNumbers.remove(active);
    historyVersion++;
    await refreshBalance();
    notifyListeners();
  }

  void clearActive(ActiveNumber active) {
    activeNumbers.remove(active);
    active.disposeTimers();
    historyVersion++;
    notifyListeners();
  }

  String formatTime(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  void dispose() {
    for (var active in activeNumbers) {
      active.disposeTimers();
    }
    super.dispose();
  }
}

// ============== HOME SCREEN ==============
class HomeScreen extends StatefulWidget {
  final int userId;
  final String email;
  const HomeScreen({super.key, required this.userId, required this.email});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  late MainAppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = MainAppState(userId: widget.userId, email: widget.email);
    _appState.refreshBalance();
    _appState.checkForActiveNumbers();
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('FBG SMS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            actions: [
              Center(child: Text("💰 \$${_appState.balance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00FF41)))),
              const SizedBox(width: 10),
            ],
          ),
          body: IndexedStack(
            index: _currentTab,
            children: [
              HomeTab(appState: _appState),
              MyNumbersTab(appState: _appState),
              ProfileTab(appState: _appState),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (index) {
              setState(() => _currentTab = index);
              if (index == 0) _appState.refreshBalance();
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
              BottomNavigationBarItem(icon: Icon(Icons.phone_android), label: "My Numbers"),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
            ],
          ),
        );
      },
    );
  }
}

// ============== HOME TAB ==============
class HomeTab extends StatefulWidget {
  final MainAppState appState;
  const HomeTab({super.key, required this.appState});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _searchQuery = "";
  String _selectedCategory = "All";
  bool _isLoading = true;
  String _errorMessage = "";
  List<Map<String, String>> _allServices = [];
  Map<int, String> _countries = {};
  bool _countriesLoaded = false;

  final List<String> _popularCodes = ["wa", "tg", "fb", "ig", "lf", "go", "tw", "ds", "ub", "am"];

  final Map<String, List<String>> _categoryKeywords = {
    "Messengers": ["whatsapp", "telegram", "wechat", "chat", "signal", "viber"],
    "Social": ["facebook", "instagram", "tiktok", "twitter", "reddit", "snapchat", "threads", "douyin"],
    "Google": ["google", "gmail", "youtube"],
    "Entertainment": ["netflix", "spotify", "twitch", "ticketmaster"],
    "Shopping": ["amazon", "shopee", "ebay", "aliexpress", "etsy"],
    "Gaming": ["discord", "steam", "roblox", "epic"],
    "Dating": ["tinder", "bumble", "hinge", "badoo"],
    "Finance": ["paypal", "revolut", "wise", "cash"],
  };

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  String _categorize(String name) {
    final lower = name.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) return entry.key;
      }
    }
    return "Other";
  }

  Future<void> _loadServices() async {
    setState(() { _isLoading = true; _errorMessage = ""; });
    try {
      final response = await http.get(Uri.parse('https://grizzly-sms-backend.onrender.com/api/services'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> list = data['services'] ?? [];
        final services = list.map((s) {
          final code = s['code'].toString();
          final name = s['name'].toString();
          return <String, String>{
            "code": code,
            "name": name,
            "category": _categorize(name),
          };
        }).toList();

        services.sort((a, b) {
          final aPop = _popularCodes.indexOf(a["code"]!);
          final bPop = _popularCodes.indexOf(b["code"]!);
          if (aPop != -1 && bPop != -1) return aPop.compareTo(bPop);
          if (aPop != -1) return -1;
          if (bPop != -1) return 1;
          return a["name"]!.compareTo(b["name"]!);
        });

        setState(() { _allServices = services; _isLoading = false; });
      } else {
        setState(() { _errorMessage = "Could not load services."; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = "Connection failed. Is the server running?"; _isLoading = false; });
    }
  }

  Future<void> _loadCountriesOnce() async {
    if (_countriesLoaded) return;
    try {
      final response = await http.get(Uri.parse('https://grizzly-sms-backend.onrender.com/api/countries'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        Map<int, String> loaded = {};
        data.forEach((key, value) {
          if (value is Map) {
            final int countryId = int.parse(key);
            final String countryName = (value['eng'] ?? value['rus'] ?? "Country $key").toString();
            
            // Force include USA (ID 1) and normally visible countries
            if (countryId == 1 || value['visible'] == 1 || value['visible'] == null) {
              loaded[countryId] = countryName;
            }
          }
        });
        _countries = loaded;
        _countriesLoaded = true;
      }
    } catch (e) {}
  }

  List<Map<String, String>> get _filteredServices {
    return _allServices.where((s) {
      final matchCategory = _selectedCategory == "All" || s["category"] == _selectedCategory;
      final matchSearch = _searchQuery.isEmpty ||
          s["name"]!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s["code"]!.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchCategory && matchSearch;
    }).toList();
  }

  Future<void> _onServiceTap(String serviceKey, String serviceName) async {
    await _loadCountriesOnce();

    Map<int, double> prices = {};
    try {
      final pResp = await http.get(Uri.parse('https://grizzly-sms-backend.onrender.com/api/prices?service=$serviceKey'));
      if (pResp.statusCode == 200) {
        final data = jsonDecode(pResp.body);
        data.forEach((countryCode, serviceData) {
          if (serviceData[serviceKey] != null) {
            prices[int.parse(countryCode)] = (serviceData[serviceKey]['cost'] as num).toDouble();
          }
        });
      }
    } catch (e) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => CountryPickerSheet(
        countries: _countries,
        popularNames: const ["United States", "United Kingdom", "Indonesia", "India", "Philippines", "Russia", "Nigeria", "South Africa"],
        selectedId: null,
        prices: prices.map((k, v) => MapEntry(k.toString(), v)),
        onSelected: (id, name) async {
          await _buyNumber(serviceKey, serviceName, id);
        },
      ),
    );
  }

  Future<void> _buyNumber(String serviceKey, String serviceName, int country) async {
    try {
      final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/buy-number');
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.appState.userId, "service": serviceKey, "country": country}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        widget.appState.startNewActivation(
          phone: data['phone_number'],
          activationId: data['activation_id'],
          service: serviceKey,
          country: country,
        );
        await widget.appState.refreshBalance();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$serviceName number bought! Check 'My Numbers' tab."), backgroundColor: Colors.green),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        if (data['detail'] == 'INSUFFICIENT_BALANCE') {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Not enough balance. Refer a friend to earn \$0.50!"), backgroundColor: Colors.red));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] ?? "Could not buy. Try another country."), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection failed."), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _filteredServices;
    final Set<String> cats = {"All"};
    for (final s in _allServices) {
      if (s["category"] != null) cats.add(s["category"]!);
    }
    final categories = cats.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search ${_allServices.length} services",
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final cat = categories[i];
              final selected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  selectedColor: const Color(0xFF00FF41),
                  backgroundColor: const Color(0xFF1A1A1A),
                  labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF41)))
              : _errorMessage.isNotEmpty
                  ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
                  : services.isEmpty
                      ? const Center(child: Text("No services found.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          itemCount: services.length,
                          itemBuilder: (context, i) {
                            final s = services[i];
                            final code = s["code"]!;
                            final icon = getServiceIcon(code);
                            final color = getServiceColor(code);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Container(
                                  width: 45, height: 45,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: FaIcon(icon, color: color, size: 22),
                                ),
                                title: Text(s["name"]!, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF00FF41)),
                                onTap: () => _onServiceTap(code, s["name"]!),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ============== MY NUMBERS TAB ==============
class MyNumbersTab extends StatefulWidget {
  final MainAppState appState;
  const MyNumbersTab({super.key, required this.appState});
  @override
  State<MyNumbersTab> createState() => _MyNumbersTabState();
}

class _MyNumbersTabState extends State<MyNumbersTab> {
  List<dynamic> _history = [];
  bool _isLoadingHistory = true;
  int _lastHistoryVersion = -1;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChange);
    _loadHistory();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChange);
    super.dispose();
  }

  void _onAppStateChange() {
    if (widget.appState.historyVersion != _lastHistoryVersion) {
      _lastHistoryVersion = widget.appState.historyVersion;
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/history/${widget.appState.userId}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _history = data['history']);
      }
    } catch (e) {} finally { setState(() => _isLoadingHistory = false); }
  }

  Color _statusColor(String status) {
    if (status == "COMPLETED") return const Color(0xFF00FF41);
    if (status == "CANCELLED") return Colors.red;
    return Colors.orange;
  }

  String _statusLabel(String status) {
    if (status == "COMPLETED") return "Used";
    if (status == "CANCELLED") return "Cancelled";
    return "Pending";
  }

  IconData _statusIcon(String status) {
    if (status == "COMPLETED") return Icons.check_circle;
    if (status == "CANCELLED") return Icons.cancel;
    return Icons.hourglass_top;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final a = widget.appState;

        return Column(
          children: [
            if (a.activeNumbers.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 15, 20, 5),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top, size: 20, color: Color(0xFF00FF41)),
                    SizedBox(width: 8),
                    Text("Active Numbers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  ],
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    itemCount: a.activeNumbers.length,
                    itemBuilder: (context, i) {
                      final active = a.activeNumbers[i];
                      final hasCode = active.smsCode.isNotEmpty;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Service: ${active.service}",
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                                  ),
                                  if (!hasCode)
                                    Text(
                                      a.formatTime(active.secondsRemaining),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: active.secondsRemaining > 30 ? const Color(0xFF00FF41) : Colors.red,
                                      ),
                                    )
                                  else
                                    const Text("COMPLETED", style: TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(active.phoneNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  IconButton(
                                    icon: const Icon(Icons.copy, color: Color(0xFF00FF41)),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: active.phoneNumber));
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Number copied!")));
                                    },
                                  ),
                                ],
                              ),
                              if (hasCode) ...[
                                const SizedBox(height: 10),
                                Text("Code: ${active.smsCode}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00FF41))),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  if (!hasCode)
                                    ElevatedButton.icon(
                                      onPressed: () => a.cancelActivation(active),
                                      icon: const Icon(Icons.cancel),
                                      label: const Text("Cancel"),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    )
                                  else
                                    ElevatedButton.icon(
                                      onPressed: () => a.clearActive(active),
                                      icon: const Icon(Icons.check),
                                      label: const Text("Done"),
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF41), foregroundColor: Colors.black),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 15, 20, 5),
              child: Row(
                children: [
                  Icon(Icons.history, size: 20, color: Color(0xFF00FF41)),
                  SizedBox(width: 8),
                  Text("History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: _isLoadingHistory
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF41)))
                  : _history.isEmpty
                      ? const Center(child: Text("No past numbers yet.", style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            itemCount: _history.length,
                            itemBuilder: (context, i) {
                              final tx = _history[i];
                              final status = tx['status'].toString();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: Icon(_statusIcon(status), color: _statusColor(status), size: 32),
                                  title: Text(tx['phone_number'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _statusColor(status).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text("Service: ${tx['service']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                      if (tx['sms_code'] != null && tx['sms_code'].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text("Code: ${tx['sms_code']}", style: const TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold, fontSize: 13)),
                                        ),
                                    ],
                                  ),
                                  trailing: Text("\$${tx['cost']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

// ============== PROFILE TAB ==============
class ProfileTab extends StatelessWidget {
  final MainAppState appState;
  const ProfileTab({super.key, required this.appState});

  Future<void> _showTopUpDialog(BuildContext context) async {
    final controller = TextEditingController(text: "5");
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Add Funds", style: TextStyle(color: Color(0xFF00FF41))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter amount in USD (min \$1.00):"),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: "\$ ",
              ),
            ),
            const SizedBox(height: 10),
            const Text("You will be redirected to a secure crypto payment page (NOWPayments).", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val >= 1.0) {
                Navigator.pop(context, val);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Minimum is \$1.00"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Pay"),
          ),
        ],
      ),
    );

    if (amount == null) return;

    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/payment/create-invoice'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": appState.userId, "amount": amount}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final url = Uri.parse(data['invoice_url']);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          Future.delayed(const Duration(seconds: 5), () => appState.refreshBalance());
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open payment page"), backgroundColor: Colors.red));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to create invoice"), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection error"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 45,
                backgroundColor: const Color(0xFF00FF41).withOpacity(0.2),
                child: Text(
                  appState.email.isNotEmpty ? appState.email[0].toUpperCase() : "?",
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF00FF41)),
                ),
              ),
              const SizedBox(height: 15),
              Text(appState.email, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white)),
              const SizedBox(height: 30),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text("Wallet Balance", style: TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 10),
                      Text("\$${appState.balance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF00FF41))),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showTopUpDialog(context),
                              icon: const Icon(Icons.currency_bitcoin),
                              label: const Text("Crypto"),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50), 
                                backgroundColor: Colors.orange, 
                                foregroundColor: Colors.white
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Card payments coming soon! Please use Crypto for now."), backgroundColor: Colors.blue),
                                );
                              },
                              icon: const Icon(Icons.credit_card),
                              label: const Text("Card"),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50), 
                                backgroundColor: Colors.grey[800], 
                                foregroundColor: Colors.white
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                color: const Color(0xFF1A1A1A),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.card_giftcard, color: Colors.orange, size: 28),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text("Refer & Earn", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text("\$0.50 / friend", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      const Text("Share your code with friends. When they sign up, you both get \$0.50!", style: TextStyle(fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                appState.referralCode.isEmpty ? "Loading..." : appState.referralCode,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.orange),
                              onPressed: () {
                                if (appState.referralCode.isNotEmpty) {
                                  Clipboard.setData(ClipboardData(text: appState.referralCode));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Referral code copied!")));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: _statBox("Friends Invited", "${appState.referralCount}", Colors.orange)),
                          const SizedBox(width: 10),
                          Expanded(child: _statBox("Total Earned", "\$${appState.referralEarnings.toStringAsFixed(2)}", const Color(0xFF00FF41))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email_outlined, color: Color(0xFF00FF41)),
                      title: const Text("Email", style: TextStyle(color: Colors.grey)),
                      subtitle: Text(appState.email, style: const TextStyle(color: Colors.white)),
                    ),
                    const Divider(height: 1, color: Colors.grey),
                    ListTile(
                      leading: const Icon(Icons.support_agent, color: Color(0xFF00FF41)),
                      title: const Text("Contact Support", style: TextStyle(color: Colors.grey)),
                      subtitle: const Text("Chat with us on Telegram", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () async {
                        final Uri telegramUrl = Uri.parse('https://t.me/FBG_Support');
                        if (await canLaunchUrl(telegramUrl)) {
                          await launchUrl(telegramUrl, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Could not open Telegram."), backgroundColor: Colors.red),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text("Logout", style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), side: const BorderSide(color: Colors.red)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ============== COUNTRY PICKER BOTTOM SHEET ==============
class CountryPickerSheet extends StatefulWidget {
  final Map<int, String> countries;
  final List<String> popularNames;
  final int? selectedId;
  final Map<String, double> prices;
  final Function(int, String) onSelected;

  const CountryPickerSheet({
    super.key,
    required this.countries,
    required this.popularNames,
    required this.selectedId,
    required this.prices,
    required this.onSelected,
  });

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final popularEntries = <MapEntry<int, String>>[];
    for (final name in widget.popularNames) {
      final match = widget.countries.entries.where((e) => e.value == name).firstOrNull;
      if (match != null) popularEntries.add(match);
    }

    final filtered = _query.isEmpty
        ? widget.countries.entries.toList()
        : widget.countries.entries.where((e) => e.value.toLowerCase().contains(_query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
            const Text("Select Country", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00FF41))),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: "Search countries...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (_query.isEmpty && popularEntries.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 5), child: Text("⭐ Popular", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FF41), fontSize: 14))),
                    ...popularEntries.map((e) => _buildTile(e.key, e.value)),
                    const Divider(thickness: 2),
                    const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 5), child: Text("🌍 All Countries", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14))),
                  ],
                  ...filtered.map((e) => _buildTile(e.key, e.value)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTile(int id, String name) {
    final isSelected = widget.selectedId == id;
    final price = widget.prices[id.toString()];
    final isOutOfStock = price == null;

    return ListTile(
      enabled: !isOutOfStock,
      title: Text(
        name, 
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, 
          color: isOutOfStock 
              ? Colors.grey[600] 
              : (isSelected ? const Color(0xFF00FF41) : Colors.white),
        )
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOutOfStock)
            Text("Out of stock", style: TextStyle(color: Colors.red[300], fontSize: 12))
          else
            Text("\$${(price + 0.20).toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold, fontSize: 13)),
          
          if (isSelected && !isOutOfStock)
            const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check, color: Color(0xFF00FF41), size: 20)),
        ],
      ),
      selected: isSelected && !isOutOfStock,
      onTap: isOutOfStock ? null : () {
        widget.onSelected(id, name);
        Navigator.pop(context);
      },
    );
  }
}