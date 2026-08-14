import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import '../services/supabase_config.dart';
import 'chat_screen.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AuthService _authService = AuthService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();

  List<MatchedContact> _registeredContacts = [];
  List<MatchedContact> _unregisteredContacts = [];
  List<Map<String, dynamic>> _globalSearchResults = [];
  
  bool _isLoadingContacts = true;
  bool _isSearchingGlobal = false;
  bool _hasSearched = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _syncPhoneContacts();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncPhoneContacts() async {
    setState(() => _isLoadingContacts = true);

    final perm = await _contactsService.requestPermission();
    setState(() => _hasPermission = perm);

    if (perm) {
      final res = await _contactsService.syncContacts();
      if (mounted) {
        setState(() {
          _registeredContacts = res['registered'] ?? [];
          _unregisteredContacts = res['unregistered'] ?? [];
          _isLoadingContacts = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingContacts = false);
      }
    }
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _hasSearched = false;
          _globalSearchResults = [];
        });
      }
      return;
    }

    _performGlobalSearch(q);
  }

  void _performGlobalSearch(String query) async {
    setState(() {
      _hasSearched = true;
      _isSearchingGlobal = true;
    });

    final results = await _authService.searchUsers(query);

    if (mounted) {
      setState(() {
        _isSearchingGlobal = false;
        _globalSearchResults = results;
      });
    }
  }

  List<MatchedContact> get _filteredRegisteredContacts {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _registeredContacts;
    return _registeredContacts.where((c) {
      return c.contactName.toLowerCase().contains(q) ||
          (c.appUsername ?? '').toLowerCase().contains(q) ||
          c.rawPhoneNumber.contains(q);
    }).toList();
  }

  List<MatchedContact> get _filteredUnregisteredContacts {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _unregisteredContacts;
    return _unregisteredContacts.where((c) {
      return c.contactName.toLowerCase().contains(q) || c.rawPhoneNumber.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        title: const Text('Nuevo Chat / Contactos 🌸', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: Color(0xFFFF1744)),
            tooltip: 'Sincronizar contactos',
            onPressed: _syncPhoneContacts,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Input
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, @username o teléfono...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFF1744)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Main Content Area
            Expanded(
              child: _isLoadingContacts
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)))
                  : _buildContactsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    final registered = _filteredRegisteredContacts;
    final unregistered = _filteredUnregisteredContacts;
    final currentUid = _authService.currentUser?.uid;

    return ListView(
      children: [
        // Permission Banner if not granted
        if (!_hasPermission)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.contacts_rounded, color: Colors.deepPurpleAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Sincronizar Contactos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 2),
                      Text('Permite acceso a tu agenda para ver a tus amigos registrados.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _syncPhoneContacts,
                  child: const Text('ACTIVAR', style: TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

        // Section 1: Phone Contacts on CrystalApp
        if (registered.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.phone_android_rounded, color: Color(0xFFFF1744), size: 18),
                const SizedBox(width: 6),
                Text(
                  'Contactos de tu Teléfono en CrystalApp (${registered.length}):',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
          ...registered.map((c) => _buildContactCard(c)).toList(),
          const SizedBox(height: 16),
        ],

        // Section 2: Global Database Users
        if (!_hasSearched) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
            child: Row(
              children: const [
                Icon(Icons.public_rounded, color: Colors.blueAccent, size: 18),
                SizedBox(width: 6),
                Text(
                  'Todos los Usuarios Registrados en CrystalApp:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: SupabaseConfig.client.from('users').stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting && registered.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFFF1744))));
              }

              final docs = snapshot.data ?? [];
              final filteredDocs = docs.where((u) => u['id'] != currentUid).toList();

              if (filteredDocs.isEmpty && registered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      'No hay otros usuarios registrados todavía.',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ),
                );
              }

              return Column(
                children: filteredDocs.map((uData) {
                  // Check if already shown in phone contacts to avoid duplicates
                  final uid = uData['id'];
                  final isAlreadyInPhoneContacts = registered.any((c) => c.appUserId == uid);
                  if (isAlreadyInPhoneContacts) return const SizedBox.shrink();

                  return _buildUserCard(uData);
                }).toList(),
              );
            },
          ),
        ] else if (_isSearchingGlobal) ...[
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFFF1744))))
        ] else if (_globalSearchResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
            child: Row(
              children: const [
                Icon(Icons.search_rounded, color: Colors.amberAccent, size: 18),
                SizedBox(width: 6),
                Text(
                  'Resultados Globales de Búsqueda:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
          ..._globalSearchResults.map((uData) {
            final isMe = uData['id'] == currentUid || uData['uid'] == currentUid;
            if (isMe) return const SizedBox.shrink();
            return _buildUserCard(uData);
          }).toList(),
        ],

        // Section 3: Invite Phone Contacts
        if (unregistered.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.share_rounded, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Invitar Contactos de tu Teléfono (${unregistered.length}):',
                  style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          ...unregistered.take(20).map((c) => _buildUnregisteredContactCard(c)).toList(),
        ],
      ],
    );
  }

  Widget _buildContactCard(MatchedContact contact) {
    final hasAvatar = contact.avatarUrl != null && contact.avatarUrl!.startsWith('http');

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: const Color(0xFFFF1744).withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF1E1E1E),
              backgroundImage: hasAvatar ? NetworkImage(contact.avatarUrl!) : null,
              child: !hasAvatar
                  ? Text(
                      contact.contactName.isNotEmpty ? contact.contactName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    )
                  : null,
            ),
            if (contact.isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1E1E1E), width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                contact.contactName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF1744).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Agenda 📱', style: TextStyle(color: Color(0xFFFF1744), fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Text(
          contact.appUsername != null && contact.appUsername!.isNotEmpty
              ? '@${contact.appUsername} • ${contact.rawPhoneNumber}'
              : contact.rawPhoneNumber,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF1744),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
          label: const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  recipientId: contact.appUserId!,
                  recipientName: contact.contactName,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> uData) {
    final name = uData['display_name'] ?? uData['displayName'] ?? uData['username'] ?? uData['name'] ?? 'Usuario';
    final username = uData['username'] ?? '';
    final phone = uData['phone'] ?? '';
    final uid = uData['id'] ?? uData['uid'];
    final avatarUrl = uData['avatar_url']?.toString() ?? uData['avatarUrl']?.toString();
    final hasAvatar = avatarUrl != null && avatarUrl.startsWith('http');

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF1E1E1E),
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
          child: !hasAvatar
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                )
              : null,
        ),
        title: Text(
          name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          username.isNotEmpty ? '@$username • $phone' : phone,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
          label: const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  recipientId: uid,
                  recipientName: name,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUnregisteredContactCard(MatchedContact contact) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.white10,
        child: Text(
          contact.contactName.isNotEmpty ? contact.contactName[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
      title: Text(contact.contactName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      subtitle: Text(contact.rawPhoneNumber, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.greenAccent),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Invitar', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E1E1E),
              content: Text('Invitación lista para ${contact.contactName} (${contact.rawPhoneNumber})', style: const TextStyle(color: Colors.white)),
            ),
          );
        },
      ),
    );
  }
}
