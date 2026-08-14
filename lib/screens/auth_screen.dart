import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../utils/country_phone_helper.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;
  bool _isExistingUser = false;
  String? _existingUsername;
  String? _existingDisplayName;
  String? _verificationId;
  String _errorMessage = '';

  void _verifyPhone() async {
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();

    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Introduce un número de teléfono válido con código (+34...)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final formattedPhone = CountryPhoneHelper.formatPhoneNumber(phone);

    // 1. Check if phone is already linked to an existing account (Login Mode)
    final existingUser = await _authService.getUserByPhone(formattedPhone);
    if (existingUser != null) {
      _isExistingUser = true;
      _existingUsername = existingUser['username'];
      _existingDisplayName = existingUser['display_name'];
    } else {
      _isExistingUser = false;
      // Register Mode: validate username
      if (username.isEmpty || username.length < 3) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'El nombre de usuario debe tener al menos 3 caracteres';
        });
        return;
      }

      final isAvailable = await _authService.isUsernameAvailable(username);
      if (!isAvailable) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'El nombre de usuario @$username ya está registrado. Elige otro.';
        });
        return;
      }
    }

    await _authService.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      onVerificationCompleted: (PhoneAuthCredential credential) async {
        setState(() => _isLoading = false);
      },
      onVerificationFailed: (FirebaseAuthException e) {
        setState(() {
          _isLoading = false;
          if (e.code == 'too-many-requests') {
            _errorMessage = '🚫 Dispositivo temporalmente bloqueado por demasiados intentos de SMS.\n\nSolución rápida:\n1. Ve a Firebase Console -> Authentication -> Método de acceso.\n2. Abre "Teléfono" -> "Números de teléfono para prueba".\n3. Añade tu número y el código para entrar al instante.';
          } else {
            _errorMessage = 'Error de verificación: ${e.message ?? e.code}';
          }
        });
      },
      onCodeSent: (String verificationId, int? resendToken) {
        setState(() {
          _isLoading = false;
          _codeSent = true;
          _verificationId = verificationId;
        });
      },
      onCodeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  void _submitOtp() async {
    final smsCode = _smsController.text.trim();
    if (smsCode.isEmpty || _verificationId == null) {
      setState(() => _errorMessage = 'Introduce el código SMS recibido');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final username = _isExistingUser ? (_existingUsername ?? '') : _usernameController.text.trim();
      final displayName = _isExistingUser
          ? (_existingDisplayName ?? username)
          : (_displayNameController.text.trim().isEmpty ? username : _displayNameController.text.trim());

      await _authService.signInWithOtp(
        verificationId: _verificationId!,
        smsCode: smsCode,
        username: username,
        displayName: displayName,
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Código incorrecto o expirado. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_person_outlined,
                  size: 72,
                  color: Color(0xFFFF1744),
                ),
                const SizedBox(height: 16),
                const Text(
                  'CrystalApp 🌸',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Identificador único + Verificación telefónica SMS',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white60,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                if (_errorMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (!_codeSent) ...[
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Número de Teléfono (con código de país)',
                      hintText: '+34600000000',
                      hintStyle: const TextStyle(color: Colors.white24),
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.phone_android, color: Color(0xFFFF1744)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario Único (si eres nuevo)',
                      hintText: 'ej: yuki_katsume',
                      hintStyle: const TextStyle(color: Colors.white24),
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFFFF1744)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _displayNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nombre visible (Opcional)',
                      hintText: 'ej: Yuki',
                      hintStyle: const TextStyle(color: Colors.white24),
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.badge_outlined, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyPhone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF1744),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Validar e Iniciar Verificación SMS',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Introduce el código de 6 dígitos enviado a\n${_phoneController.text}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _smsController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF1744),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Confirmar Código SMS',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _codeSent = false),
                    child: const Text(
                      'Cambiar datos de registro',
                      style: TextStyle(color: Colors.white60),
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
