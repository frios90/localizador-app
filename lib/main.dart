import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service_ios/flutter_background_service_ios.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// =============================================================================
// CONFIGURACIÓN
// =============================================================================

const notificationChannelId = 'location_service_channel';
const notificationId        = 888;

class AppConfig {
  static String get apiUrl =>
      dotenv.env['API_URL'] ?? 'https://www.friveloop.com/api/location';

  static String get authApiUrl =>
      dotenv.env['AUTH_API_URL'] ?? 'https://www.friveloop.com/api/v1/get-token';

  static int get sendIntervalSeconds =>
      int.tryParse(dotenv.env['SEND_INTERVAL_SECONDS'] ?? '60') ?? 60;

  static int get captureIntervalSeconds =>
      int.tryParse(dotenv.env['CAPTURE_INTERVAL_SECONDS'] ?? '1') ?? 1;
}

// =============================================================================
// TEMA PROFESIONAL MODERNO
// =============================================================================


class AppTheme {
  // Paleta principal - slate/blue profesional
  static const Color primaryDark = Color(0xFF1A2A3A);
  static const Color primary = Color(0xFF2C3E50);
  static const Color primaryLight = Color(0xFF4A6572);
  static const Color accent = Color(0xFF00A896);
  static const Color accentLight = Color(0xFF02C39A);
  static const Color accentSoft = Color(0xFFE8F5F0);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textLight = Color(0xFF94A3B8);
  static const Color error = Color(0xFFE53E3E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color info = Color(0xFF3B82F6);
  static const Color divider = Color(0xFFE2E8F0);
  static const Color cardBg = Color(0xFFFFFFFF);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: surface,
      cardTheme: CardThemeData(  // 👈 CAMBIADO: CardThemeData en lugar de CardTheme
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: divider.withOpacity(0.5)),
        ),
        color: cardBg,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
    );
  }
}

// =============================================================================
// MAIN
// =============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  if (!Platform.isLinux) {
    await _initializeService();
  }

  runApp(const MyApp());
}

// =============================================================================
// INICIALIZACIÓN DEL SERVICIO BACKGROUND
// =============================================================================

Future<void> _initializeService() async {
  final service = FlutterBackgroundService();

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            notificationChannelId,
            'Servicio de Localización',
            description: 'Canal para el servicio de localización en segundo plano',
            importance: Importance.low,
          ),
        );
  } else if (Platform.isIOS) {
    await notificationsPlugin.initialize(
      const InitializationSettings(iOS: DarwinInitializationSettings()),
    );
  }

  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Location Service',
      initialNotificationContent: 'Servicio inactivo',
      foregroundServiceNotificationId: notificationId,
    ),
  );
}

// =============================================================================
// ENTRY POINTS DEL SERVICIO
// =============================================================================

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Leer configuración persistida
  final prefs           = await SharedPreferences.getInstance();
  final deviceId        = prefs.getString('device_uuid')            ?? 'unknown';
  final apiUrl          = prefs.getString('api_url')                ?? AppConfig.apiUrl;
  final authApiUrl      = prefs.getString('auth_api_url')           ?? AppConfig.authApiUrl;
  final sendInterval    = prefs.getInt('send_interval_seconds')     ?? AppConfig.sendIntervalSeconds;
  final captureInterval = prefs.getInt('capture_interval_seconds')  ?? AppConfig.captureIntervalSeconds;
  final userRut         = prefs.getString('user_rut')               ?? '';
  final userPassword    = prefs.getString('user_password')          ?? '';
  final userConsent     = prefs.getBool('user_consent')             ?? false;
  final consentVersion  = prefs.getString('consent_version')        ?? '1.0';

  // Buffer de posiciones pendientes
  final List<Map<String, dynamic>> pendingLocations = [];
  Position? lastCapturedPosition;
  bool isSending = false;

  // ── Notificación inicial ──────────────────────────────────────────────────
  void updateNotification(String content) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: '📍 Location Service',
        content: content,
      );
    }
  }

  updateNotification(
    'Capturando cada ${captureInterval}s · enviando cada ${sendInterval}s',
  );

  // ── Captura de ubicación ──────────────────────────────────────────────────
  Future<void> captureLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      final now = DateTime.now();

      // Si es la misma posición, solo actualizar el timestamp del último punto
      if (lastCapturedPosition != null &&
          (pos.latitude  - lastCapturedPosition!.latitude).abs()  < 0.000001 &&
          (pos.longitude - lastCapturedPosition!.longitude).abs() < 0.000001 &&
          pendingLocations.isNotEmpty) {
        final last = pendingLocations.last;
        last['timestamp'] = now.toIso8601String();
        last['speed']     = pos.speed;
        last['accuracy']  = pos.accuracy;
        last['heading']   = pos.heading;
        last['altitude']  = pos.altitude;
        return;
      }

      // Nueva posición
      pendingLocations.add({
        'device_uuid': deviceId,
        'latitude':    pos.latitude,
        'longitude':   pos.longitude,
        'accuracy':    pos.accuracy,
        'altitude':    pos.altitude,
        'speed':       pos.speed,
        'heading':     pos.heading,
        'timestamp':   now.toIso8601String(),
        'device_info': Platform.operatingSystem,
      });

      lastCapturedPosition = pos;

      updateNotification(
        'Buffer: ${pendingLocations.length} pts · enviando cada ${sendInterval}s',
      );
    } catch (e) {
      print('❌ Error capturando ubicación: $e');
    }
  }

  // ── Obtener token fresco (siempre, sin caché) ─────────────────────────────
  Future<String?> fetchFreshToken() async {
    try {
      final response = await http.post(
        Uri.parse(authApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_rut':      userRut,
          'user_password': userPassword,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['error'] == false) {
        return data['token'] as String?;
      }

      print('⚠️ Error obteniendo token: ${data['message']}');
      return null;
    } catch (e) {
      print('❌ fetchFreshToken error: $e');
      return null;
    }
  }

  // ── Envío del lote ────────────────────────────────────────────────────────
  Future<void> sendBatch() async {
    if (isSending || pendingLocations.isEmpty) return;
    isSending = true;

    try {
      // 1. Obtener token fresco SIEMPRE
      final token = await fetchFreshToken();
      if (token == null) {
        print('❌ No se pudo obtener token. Se reintentará en el próximo ciclo.');
        updateNotification('⚠️ Sin token – reintentando en ${sendInterval}s');
        return;
      }

      // 2. Preparar payload
      final snapshot   = List<Map<String, dynamic>>.from(pendingLocations);
      final batchSize  = snapshot.length;

      final payload = {
        'device_uuid':     deviceId,
        'batch_size':      batchSize,
        'capture_interval': captureInterval,
        'user_consent':    userConsent,
        'consent_version': consentVersion,
        'locations':       snapshot,
        'sent_at':         DateTime.now().toIso8601String(),
      };

      // 3. Enviar
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        pendingLocations.clear();
        print('✅ Lote de $batchSize posiciones enviado');
        updateNotification('✅ Enviados $batchSize pts');
      } else {
        print('⚠️ Error HTTP ${response.statusCode}: ${response.body}');
        updateNotification('⚠️ Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ sendBatch error: $e');
      updateNotification('❌ Error de envío');
    } finally {
      isSending = false;
    }
  }

  // ── Timers ────────────────────────────────────────────────────────────────
  final captureTimer = Timer.periodic(
    Duration(seconds: captureInterval),
    (_) => captureLocation(),
  );

  final sendTimer = Timer.periodic(
    Duration(seconds: sendInterval),
    (_) => sendBatch(),
  );

  // ── Detener el servicio limpiamente ──────────────────────────────────────
  service.on('stopService').listen((_) {
    captureTimer.cancel();
    sendTimer.cancel();
    service.stopSelf();
  });

  // Primera captura inmediata al arrancar
  await captureLocation();
}

// =============================================================================
// APP PRINCIPAL
// =============================================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Localizador de Dispositivo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

// =============================================================================
// AUTH GATE – decide qué pantalla mostrar al abrir la app
// =============================================================================

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    final prefs      = await SharedPreferences.getInstance();
    final token      = prefs.getString('auth_token') ?? '';
    final hasConsent = prefs.getBool('user_consent') ?? false;

    if (!mounted) return;

    if (token.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else if (!hasConsent) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConsentPage()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LocationPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// =============================================================================
// LOGIN PAGE - Rediseñada profesional
// =============================================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _rutController      = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading       = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _rutController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final rut      = _rutController.text.trim();
    final password = _passwordController.text;

    if (rut.isEmpty || password.isEmpty) {
      _showSnack('Completa todos los campos', AppTheme.warning);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse(AppConfig.authApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_rut': rut, 'user_password': password}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['error'] == false) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token',   data['token'] as String);
        await prefs.setString('user_id',      data['user_id'].toString());
        await prefs.setString('user_rut',     rut);
        await prefs.setString('user_password', password);
        await prefs.setString('api_url',       AppConfig.apiUrl);
        await prefs.setString('auth_api_url',  AppConfig.authApiUrl);
        await prefs.setInt('send_interval_seconds',    AppConfig.sendIntervalSeconds);
        await prefs.setInt('capture_interval_seconds', AppConfig.captureIntervalSeconds);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ConsentPage()),
        );
      } else {
        _showSnack(data['message'] as String? ?? 'Error al iniciar sesión', AppTheme.error);
      }
    } on TimeoutException {
      _showSnack('Tiempo de espera agotado', AppTheme.error);
    } catch (e) {
      _showSnack('Error de conexión: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 80),
              // Logo / Icono
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Bienvenido',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Inicia sesión para continuar',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 48),

              // RUT
              TextField(
                controller: _rutController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'RUT',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // Contraseña
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Botón
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('INICIAR SESIÓN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CONSENT PAGE - Rediseñada
// =============================================================================

class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _acceptTerms   = false;
  bool _acceptPrivacy = false;
  bool _isLoading     = false;

  Future<void> _accept() async {
    if (!_acceptTerms || !_acceptPrivacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Debes aceptar todos los términos para continuar'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('user_consent',       true);
    await prefs.setString('consent_version',  '1.0');
    await prefs.setString('consent_timestamp', DateTime.now().toIso8601String());

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LocationPage()),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ', style: TextStyle(fontSize: 15, color: AppTheme.accent, fontWeight: FontWeight.w500)),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aviso de Privacidad'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.accentSoft, AppTheme.accentSoft.withOpacity(0.5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Consentimiento Informado',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 32),

            Text(
              'Términos y Condiciones',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 20),

            // Términos
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(children: [
                _bullet('📱 Recopilación de ubicación GPS en segundo plano mientras el servicio esté activo.'),
                _bullet('🎯 Datos EXCLUSIVOS para análisis propios. Sin publicidad ni perfilamiento comercial.'),
                _bullet('🔒 Sin compartir datos personales con terceros sin consentimiento explícito.'),
                _bullet('🗑️ Datos anonimizados/eliminados tras 30 días.'),
                _bullet('⚖️ Derechos ARCO: acceso, rectificación, cancelación y oposición.'),
                _bullet('✅ Uso VOLUNTARIO. Sin coacción.'),
                _bullet('📋 Responsabilidad del usuario sobre su dispositivo y credenciales.'),
                _bullet('⚠️ Sin responsabilidad por uso indebido, pérdida o robo del dispositivo.'),
                _bullet('🌐 Transmisión cifrada (HTTPS). Sin garantía absoluta ante ataques externos.'),
                _bullet('🚫 Prohibido uso ilegal o vigilancia no consentida.'),
                _bullet('📜 Actualizaciones del aviso requieren nuevo consentimiento.'),
                _bullet('🏛️ Sujeto a legislación de protección de datos aplicable.'),
                _bullet('🔋 Servicio continuo en segundo plano. Detenible desde la app o sistema.'),
                _bullet('💼 Al aceptar, liberas al desarrollador de responsabilidades por uso voluntario.'),
              ]),
            ),
            const SizedBox(height: 32),

            // Checkboxes
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(children: [
                CheckboxListTile(
                  value: _acceptTerms,
                  onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                  title: Text(
                    'Acepto los Términos y Condiciones',
                    style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.accent,
                  checkColor: Colors.white,
                ),
                Divider(height: 0, color: AppTheme.divider),
                CheckboxListTile(
                  value: _acceptPrivacy,
                  onChanged: (v) => setState(() => _acceptPrivacy = v ?? false),
                  title: Text(
                    'Acepto la Política de Privacidad',
                    style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.accent,
                  checkColor: Colors.white,
                ),
              ]),
            ),
            const SizedBox(height: 32),

            // Botón
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'ACEPTO Y CONTINUAR',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LOCATION PAGE - Rediseñada
// =============================================================================

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final List<_LogEntry> _logs = [];
  final ScrollController _scroll = ScrollController();

  String _deviceId  = '';
  bool _hasGps      = false;
  bool _isRunning   = false;
  bool _isSending   = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString('device_uuid');
    if (uuid == null) {
      uuid = const Uuid().v4();
      await prefs.setString('device_uuid', uuid);
      _log('🆕 UUID generado: $uuid', _LogType.success);
    } else {
      _log('📱 UUID: $uuid', _LogType.info);
    }

    _deviceId = uuid;
    _log('🌐 API: ${AppConfig.apiUrl}',                       _LogType.info);
    _log('⏱ Captura cada: ${AppConfig.captureIntervalSeconds}s', _LogType.info);
    _log('📦 Envío cada:   ${AppConfig.sendIntervalSeconds}s',   _LogType.info);

    await _checkGps();
    await _checkServiceStatus();
  }

  Future<void> _checkGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) { _log('❌ GPS desactivado', _LogType.error); setState(() => _hasGps = false); return; }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      _log('❌ Permiso denegado permanentemente', _LogType.error);
      setState(() => _hasGps = false);
      return;
    }

    setState(() => _hasGps = true);
    _log('✅ Permisos GPS OK', _LogType.success);
  }

  Future<void> _checkServiceStatus() async {
    if (Platform.isLinux) { setState(() => _isRunning = false); return; }
    final running = await FlutterBackgroundService().isRunning();
    setState(() => _isRunning = running);
  }

  void _toggleService() async {
    if (Platform.isLinux) {
      _log('❌ Servicio no disponible en Linux', _LogType.error);
      return;
    }

    final service = FlutterBackgroundService();
    if (_isRunning) {
      service.invoke('stopService');
      _log('🛑 Servicio detenido', _LogType.warning);
    } else {
      await service.startService();
      _log('▶️ Servicio iniciado', _LogType.success);
    }

    await Future.delayed(const Duration(milliseconds: 500));
    await _checkServiceStatus();
  }

  Future<String?> _fetchFreshToken() async {
    final prefs    = await SharedPreferences.getInstance();
    final rut      = prefs.getString('user_rut')      ?? '';
    final password = prefs.getString('user_password') ?? '';

    _log('🔑 Solicitando token...', _LogType.info);

    try {
      final response = await http.post(
        Uri.parse(AppConfig.authApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_rut': rut, 'user_password': password}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['error'] == false) {
        _log('✅ Token obtenido', _LogType.success);
        return data['token'] as String?;
      }

      _log('❌ Error token: ${data['message']}', _LogType.error);
      return null;
    } catch (e) {
      _log('❌ Error solicitando token: $e', _LogType.error);
      return null;
    }
  }

  Future<void> _sendManual() async {
    if (_isSending) { _log('⏳ Envío en curso...', _LogType.warning); return; }
    setState(() => _isSending = true);

    try {
      await _checkGps();
      if (!_hasGps) return;

      _log('📡 Obteniendo ubicación...', _LogType.info);

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));

      final token = await _fetchFreshToken();
      if (token == null) {
        _log('❌ Sin token válido. Verifica tu sesión.', _LogType.error);
        return;
      }

      final prefs          = await SharedPreferences.getInstance();
      final userConsent    = prefs.getBool('user_consent')    ?? false;
      final consentVersion = prefs.getString('consent_version') ?? '1.0';

      final payload = {
        'device_uuid':     _deviceId,
        'batch_size':      1,
        'capture_interval': AppConfig.captureIntervalSeconds,
        'user_consent':    userConsent,
        'consent_version': consentVersion,
        'locations': [
          {
            'device_uuid': _deviceId,
            'latitude':    pos.latitude,
            'longitude':   pos.longitude,
            'accuracy':    pos.accuracy,
            'altitude':    pos.altitude,
            'speed':       pos.speed,
            'heading':     pos.heading,
            'timestamp':   DateTime.now().toIso8601String(),
            'device_info': Platform.operatingSystem,
          }
        ],
        'sent_at': DateTime.now().toIso8601String(),
      };

      _log('📤 Enviando payload...', _LogType.data);

      final response = await http.post(
        Uri.parse(AppConfig.apiUrl),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log('✅ Envío exitoso (${response.statusCode})', _LogType.success);
      } else {
        _log('⚠️ Error HTTP ${response.statusCode}: ${response.body}', _LogType.warning);
      }
    } on TimeoutException {
      _log('❌ Timeout al enviar', _LogType.error);
    } catch (e) {
      _log('❌ Error: $e', _LogType.error);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _logout() async {
    if (!Platform.isLinux && _isRunning) {
      FlutterBackgroundService().invoke('stopService');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _log(String text, [_LogType type = _LogType.info]) {
    setState(() {
      _logs.insert(0, _LogEntry(text: text, type: type, ts: DateTime.now()));
      if (_logs.length > 60) _logs.removeLast();
    });
  }

  Color _logColor(_LogType t) {
    switch (t) {
      case _LogType.error:   return AppTheme.error;
      case _LogType.success: return AppTheme.success;
      case _LogType.warning: return AppTheme.warning;
      case _LogType.data:    return AppTheme.info;
      case _LogType.info:    return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Control'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión', onPressed: _logout),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Limpiar logs', onPressed: () => setState(() => _logs.clear())),
        ],
      ),
      body: Column(
        children: [
          // Panel de estado
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _chip(Icons.devices,   'Device',   _deviceId.isNotEmpty ? '${_deviceId.substring(0, 8)}…' : '—', AppTheme.primary),
                        _chip(Icons.gps_fixed, 'GPS',      _hasGps ? 'Activo' : 'Inactivo', _hasGps ? AppTheme.success : AppTheme.error),
                        _chip(Icons.timer,     'Captura',  '${AppConfig.captureIntervalSeconds}s', AppTheme.info),
                        _chip(Icons.send,      'Envío',    '${AppConfig.sendIntervalSeconds}s',    AppTheme.accent),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (!Platform.isLinux)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _toggleService,
                          icon: Icon(_isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                          label: Text(_isRunning ? 'Detener Servicio' : 'Iniciar Servicio'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRunning ? AppTheme.error : AppTheme.success,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),

                    if (!Platform.isLinux) const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSending ? null : _sendManual,
                        icon: _isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: const Text('Envío Manual'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryLight,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),

                    if (Platform.isLinux) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '🐧 Modo Linux - Servicio background no disponible',
                          style: TextStyle(fontSize: 12, color: AppTheme.warning),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Badge de consentimiento
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.verified_user, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Consentimiento activo',
                          style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.w500),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Lista de logs
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: _logs.length,
                itemBuilder: (_, i) {
                  final e = _logs[i];
                  final h = e.ts.hour.toString().padLeft(2, '0');
                  final m = e.ts.minute.toString().padLeft(2, '0');
                  final s = e.ts.second.toString().padLeft(2, '0');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _logColor(e.type).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$h:$m:$s', style: TextStyle(fontSize: 10, color: AppTheme.textLight)),
                        const SizedBox(height: 4),
                        SelectableText(e.text, style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value, Color color) => Column(
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 6),
      Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ],
  );
}

// =============================================================================
// MODELOS INTERNOS
// =============================================================================

enum _LogType { info, success, warning, error, data }

class _LogEntry {
  final String   text;
  final _LogType type;
  final DateTime ts;
  const _LogEntry({required this.text, required this.type, required this.ts});
}