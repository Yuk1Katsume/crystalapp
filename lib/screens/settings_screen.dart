import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
import '../services/supabase_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  String? _avatarUrl;
  File? _selectedImage;
  String _errorMessage = '';
  String _successMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  void _loadUserProfile() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final res = await SupabaseConfig.client
          .from('users')
          .select()
          .eq('id', user.uid)
          .maybeSingle();

      if (res != null) {
        _usernameController.text = res['username'] ?? '';
        _displayNameController.text = res['display_name'] ?? '';
        _avatarUrl = res['avatar_url'];
      }
    } catch (e) {
      // Ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPermissionsAndPickImage() async {
    setState(() {
      _errorMessage = '';
      _successMessage = '';
    });

    // Request permissions explicitly
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.photos.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        status = await Permission.storage.request();
      }
    } else {
      status = await Permission.photos.request();
    }

    // Open image picker regardless (as Android 13+ PhotoPicker manages its own permissions)
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

      if (pickedFile == null) return;

      setState(() {
        _selectedImage = File(pickedFile.path);
        _isSaving = true;
      });

      final user = _authService.currentUser;
      if (user == null) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Usuario no autenticado.';
        });
        return;
      }

      final fileBytes = await _selectedImage!.readAsBytes();
      final fileExt = pickedFile.path.split('.').last;
      final fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      try {
        await SupabaseConfig.client.storage.from('avatars').uploadBinary(
          fileName,
          fileBytes,
          fileOptions: const FileOptions(upsert: true),
        );

        final publicUrl = SupabaseConfig.client.storage.from('avatars').getPublicUrl(fileName);
        setState(() {
          _avatarUrl = publicUrl;
          _successMessage = 'Imagen cargada en Supabase. Haz clic en "Guardar Cambios".';
        });
      } catch (uploadError) {
        // Local preview fallback
        setState(() {
          _successMessage = 'Foto seleccionada de galería. Haz clic en "Guardar Cambios".';
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error al abrir la galería: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _saveProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      setState(() => _errorMessage = 'Sesión no iniciada. Vuelve a iniciar sesión.');
      return;
    }

    final newUsername = _usernameController.text.trim();
    final newDisplayName = _displayNameController.text.trim();

    if (newUsername.isEmpty) {
      setState(() => _errorMessage = 'El nombre de usuario no puede estar vacío');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      final e2ee = E2EEService();
      final keyPair = await e2ee.getOrCreateKeyPair();

      final cleanUsername = newUsername.replaceAll('@', '').toLowerCase();
      final cleanDisplayName = newDisplayName.isEmpty ? cleanUsername : newDisplayName;

      final updateData = <String, dynamic>{
        'id': user.uid,
        'username': cleanUsername,
        'display_name': cleanDisplayName,
        'public_key': keyPair['publicKey'],
        'last_seen': DateTime.now().toIso8601String(),
      };

      if (_avatarUrl != null) {
        updateData['avatar_url'] = _avatarUrl;
      }

      final res = await SupabaseConfig.client.from('users').upsert(updateData).select();

      if (res.isNotEmpty) {
        setState(() => _successMessage = '¡Guardado con éxito en Supabase! (@$cleanUsername - $cleanDisplayName) 🌸');
      } else {
        setState(() => _successMessage = '¡Datos actualizados con éxito! 🌸');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error al guardar en Supabase: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        title: const Text('Configuración de Perfil ⚙️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _requestPermissionsAndPickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 54,
                          backgroundColor: const Color(0xFF1E1E1E),
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (_avatarUrl != null && _avatarUrl!.startsWith('http')
                                  ? NetworkImage(_avatarUrl!)
                                  : null) as ImageProvider?,
                          child: (_selectedImage == null && (_avatarUrl == null || !_avatarUrl!.startsWith('http')))
                              ? const Icon(Icons.person, size: 54, color: Colors.white54)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF1744),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Toca la foto para cambiarla desde la galería', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 24),

                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ),

                  if (_successMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: Text(_successMessage, style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
                    ),

                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario Único (@username)',
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFFFF1744)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _displayNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nombre Visible (Nombre en chats)',
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.badge_outlined, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _isSaving
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Guardar Cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 36),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        await _authService.signOut();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
