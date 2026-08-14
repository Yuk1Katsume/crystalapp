import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import '../services/group_chat_service.dart';
import '../services/supabase_config.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final GroupChatService _groupService = GroupChatService();
  final AuthService _authService = AuthService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();

  List<MatchedContact> _registeredContacts = [];
  List<Map<String, dynamic>> _allRegisteredUsers = [];
  final Set<String> _selectedUserIds = {};
  final Map<String, String> _selectedUserNames = {};

  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadUsersAndContacts();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsersAndContacts() async {
    setState(() => _isLoading = true);

    try {
      final currentUid = _authService.currentUser?.uid;

      // 1. Load phone contacts
      final contactsRes = await _contactsService.syncContacts();
      _registeredContacts = contactsRes['registered'] ?? [];

      // 2. Load all Supabase users
      final List<dynamic> usersRes = await SupabaseConfig.client
          .from('users')
          .select('id, username, display_name, phone, avatar_url, is_online');

      _allRegisteredUsers = usersRes
          .where((u) => u['id'] != currentUid)
          .map((u) => u as Map<String, dynamic>)
          .toList();
    } catch (e) {
      // Ignore
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _toggleUser(String uid, String name) {
    setState(() {
      if (_selectedUserIds.contains(uid)) {
        _selectedUserIds.remove(uid);
        _selectedUserNames.remove(uid);
      } else {
        _selectedUserIds.add(uid);
        _selectedUserNames[uid] = name;
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E1E1E),
          content: Text('Por favor escribe un nombre para el grupo.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E1E1E),
          content: Text('Selecciona al menos un miembro para el grupo.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    final currentUid = _authService.currentUser?.uid ?? '';
    final allMembers = [currentUid, ..._selectedUserIds];

    final group = await _groupService.createGroup(
      name: name,
      memberIds: allMembers,
    );

    if (mounted) {
      setState(() => _isCreating = false);
      if (group != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(groupId: group.id, groupName: group.name),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al crear el grupo. Inténtalo de nuevo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuevo Grupo 👥', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              _selectedUserIds.isEmpty
                  ? 'Añadir miembros'
                  : '${_selectedUserIds.length} miembros seleccionados',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)))
          : Column(
              children: [
                // Group Name Input
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF141414),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.deepPurpleAccent,
                        child: const Icon(Icons.group_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _groupNameController,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          decoration: const InputDecoration(
                            hintText: 'Nombre del grupo...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                            border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF1744), width: 2)),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF1744), width: 2)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Selected members chips
                if (_selectedUserIds.isNotEmpty)
                  Container(
                    height: 80,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    color: const Color(0xFF181818),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _selectedUserIds.map((uid) {
                        final name = _selectedUserNames[uid] ?? 'Usuario';
                        return Container(
                          margin: const EdgeInsets.only(right: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFFFF1744),
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: GestureDetector(
                                      onTap: () => _toggleUser(uid, name),
                                      child: const CircleAvatar(
                                        radius: 9,
                                        backgroundColor: Colors.white70,
                                        child: Icon(Icons.close, size: 12, color: Colors.black),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  name,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar participantes...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFF1744)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),

                // Members List
                Expanded(
                  child: ListView(
                    children: [
                      // 1. Phone Contacts registered
                      if (_registeredContacts.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Text(
                            'Contactos de tu Teléfono en CrystalApp:',
                            style: TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        ..._registeredContacts.where((c) {
                          if (query.isEmpty) return true;
                          return c.contactName.toLowerCase().contains(query) ||
                              (c.appUsername ?? '').toLowerCase().contains(query) ||
                              c.rawPhoneNumber.contains(query);
                        }).map((c) {
                          final uid = c.appUserId!;
                          final isSelected = _selectedUserIds.contains(uid);
                          return CheckboxListTile(
                            activeColor: const Color(0xFFFF1744),
                            checkColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            secondary: CircleAvatar(
                              backgroundColor: const Color(0xFFFF1744),
                              child: Text(
                                c.contactName.isNotEmpty ? c.contactName[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    c.contactName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF1744).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Agenda 📱', style: TextStyle(color: Color(0xFFFF1744), fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              c.appUsername != null && c.appUsername!.isNotEmpty
                                  ? '@${c.appUsername} • ${c.rawPhoneNumber}'
                                  : c.rawPhoneNumber,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            value: isSelected,
                            onChanged: (_) => _toggleUser(uid, c.contactName),
                          );
                        }).toList(),
                        const Divider(color: Colors.white12, height: 24),
                      ],

                      // 2. All other registered users
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          'Todos los Usuarios Registrados:',
                          style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      ..._allRegisteredUsers.where((u) {
                        final name = u['display_name'] ?? u['username'] ?? '';
                        final username = u['username'] ?? '';
                        final phone = u['phone'] ?? '';
                        // Avoid duplicates if already in phone contacts
                        if (_registeredContacts.any((c) => c.appUserId == u['id'])) {
                          return false;
                        }
                        if (query.isEmpty) return true;
                        return name.toLowerCase().contains(query) ||
                            username.toLowerCase().contains(query) ||
                            phone.contains(query);
                      }).map((u) {
                        final uid = u['id'].toString();
                        final name = u['display_name'] ?? u['username'] ?? 'Usuario';
                        final username = u['username'] ?? '';
                        final phone = u['phone'] ?? '';
                        final isSelected = _selectedUserIds.contains(uid);

                        return CheckboxListTile(
                          activeColor: Colors.blueAccent,
                          checkColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          secondary: CircleAvatar(
                            backgroundColor: Colors.blueAccent.withOpacity(0.8),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text(
                            username.isNotEmpty ? '@$username • $phone' : phone,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          value: isSelected,
                          onChanged: (_) => _toggleUser(uid, name),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectedUserIds.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFFFF1744),
              onPressed: _isCreating ? null : _createGroup,
              icon: _isCreating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(
                _isCreating ? 'Creando grupo...' : 'Crear Grupo (${_selectedUserIds.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}
