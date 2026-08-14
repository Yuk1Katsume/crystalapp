import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import '../services/group_chat_service.dart';
import '../services/auth_service.dart';
import '../services/local_database_service.dart';
import '../services/supabase_config.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'search_users_screen.dart';
import 'create_group_screen.dart';
import 'settings_screen.dart';
import '../services/update_service.dart';
import '../services/contacts_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedBottomNavIndex = 0;
  String _selectedFilter = 'Todos'; // 'Todos', 'No leídos', 'Favoritos', 'Grupos'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final GroupChatService _groupService = GroupChatService();
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();
  final currentUser = FirebaseAuth.instance.currentUser;

  Map<String, String> _phoneContactNames = {};
  StreamSubscription? _incomingMsgSub;

  @override
  void initState() {
    super.initState();
    _ensureProfileSaved();
    _loadPhoneContacts();
    _chatService.startGlobalIncomingListener();
    _incomingMsgSub = _chatService.onNewIncomingMessage.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  void _loadPhoneContacts() async {
    final res = await _contactsService.syncContacts();
    final registered = res['registered'] ?? [];
    if (mounted) {
      setState(() {
        _phoneContactNames = {
          for (final c in registered)
            if (c.appUserId != null) c.appUserId!: c.contactName
        };
      });
    }
  }

  void _checkUpdate() async {
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      showUpdateDialog(context, update);
    }
  }

  void _ensureProfileSaved() async {
    final user = currentUser;
    if (user != null) {
      final existing = await SupabaseConfig.client
          .from('users')
          .select('id')
          .eq('id', user.uid)
          .maybeSingle();

      if (existing == null) {
        await _authService.registerOrUpdateUserInSupabase(
          user,
          username: 'user_${user.uid.substring(0, 5)}',
          displayName: user.phoneNumber ?? 'Usuario',
        );
      }
    }
  }

  @override
  void dispose() {
    _incomingMsgSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141B),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedBottomNavIndex,
          children: [
            _buildChatsTab(),
            _buildStatusTab(),
            _buildCallsTab(),
            _buildAiChatTab(),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ==========================================
  // TAB 0: CHATS TAB (Unified Direct + Groups)
  // ==========================================
  Widget _buildChatsTab() {
    return Column(
      children: [
        _buildTopHeader(),
        _buildSearchBar(),
        _buildFilterPills(),
        Expanded(child: _buildUnifiedConversationsList()),
      ],
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text(
            'CrystalApp 🌸',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            tooltip: 'Cámara',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Abre la cámara desde cualquier conversación para enviar fotos o notas.'),
                  backgroundColor: Color(0xFF1E1E1E),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: const Color(0xFF1E262C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'new_group') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                );
              } else if (val == 'search') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
                );
              } else if (val == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_group',
                child: Text('Nuevo grupo', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'search',
                child: Text('Buscar amigos', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Ajustes', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Preguntar a Crystal AI o buscar',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim().toLowerCase();
                  });
                },
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF1744), size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPills() {
    final filters = ['Todos', 'No leídos', 'Favoritos', 'Grupos'];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == filters.length) {
            // '+' pill
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2C34),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.add, color: Colors.white54, size: 18),
            );
          }

          final filter = filters[index];
          final isSelected = _selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedFilter = filter;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0F392B) : const Color(0xFF1F2C34),
                borderRadius: BorderRadius.circular(20),
                border: isSelected
                    ? Border.all(color: const Color(0xFF00A884).withOpacity(0.5), width: 1)
                    : null,
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF25D366) : Colors.white60,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnifiedConversationsList() {
    final myUid = currentUser?.uid ?? '';
    if (myUid.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)));
    }

    return FutureBuilder<List<String>>(
      future: _localDb.getActiveConversationUserIds(myUid),
      builder: (context, activeIdsSnap) {
        final activeUserIds = activeIdsSnap.data ?? [];

        return StreamBuilder<List<GroupModel>>(
          stream: _groupService.myGroups,
          builder: (context, groupsSnap) {
            final groups = groupsSnap.data ?? [];

            // If user only wants to see groups filter
            if (_selectedFilter == 'Grupos') {
              final filteredGroups = groups.where((g) {
                if (_searchQuery.isEmpty) return true;
                return g.name.toLowerCase().contains(_searchQuery);
              }).toList();

              if (filteredGroups.isEmpty) {
                return _buildEmptyState('No estás en ningún grupo todavía.', 'Crea un grupo con tus amigos.');
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filteredGroups.length,
                itemBuilder: (context, index) {
                  return _buildGroupTile(filteredGroups[index]);
                },
              );
            }

            // For 'Todos', 'No leídos', 'Favoritos'
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseConfig.client
                  .from('users')
                  .stream(primaryKey: ['id'])
                  .map((data) => data.where((item) => activeUserIds.contains(item['id'])).toList()),
              builder: (context, usersSnap) {
                final directUsers = usersSnap.data ?? [];

                // Filter direct users by search
                final filteredUsers = directUsers.where((u) {
                  if (_searchQuery.isEmpty) return true;
                  final name = (_phoneContactNames[u['id']] ?? u['display_name'] ?? u['username'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery);
                }).toList();

                // Filter groups by search
                final filteredGroups = groups.where((g) {
                  if (_searchQuery.isEmpty) return true;
                  return g.name.toLowerCase().contains(_searchQuery);
                }).toList();

                final totalCount = filteredUsers.length + filteredGroups.length;

                if (totalCount == 0) {
                  return _buildEmptyState(
                    'No tienes conversaciones activas.',
                    'Busca un usuario o crea un grupo para empezar a chatear.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: totalCount,
                  itemBuilder: (context, index) {
                    if (index < filteredUsers.length) {
                      return _buildDirectUserTile(filteredUsers[index]);
                    } else {
                      final groupIndex = index - filteredUsers.length;
                      return _buildGroupTile(filteredGroups[groupIndex]);
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDirectUserTile(Map<String, dynamic> userData) {
    final userId = userData['id'];
    final rawDisplayName = userData['display_name'] ?? userData['username'] ?? 'Usuario';
    final contactName = _phoneContactNames[userId];
    final displayName = contactName ?? rawDisplayName;
    final isFromContacts = contactName != null;
    final isOnline = userData['is_online'] ?? false;
    final avatarUrl = userData['avatar_url'];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF1E262C),
            backgroundImage: (avatarUrl != null && avatarUrl.toString().startsWith('http'))
                ? NetworkImage(avatarUrl)
                : null,
            child: (avatarUrl == null || !avatarUrl.toString().startsWith('http'))
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  )
                : null,
          ),
          if (isOnline)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0B141B), width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isFromContacts) ...[
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
        ],
      ),
      subtitle: _LastMessagePreview(
        userId: userId,
        currentUserId: currentUser?.uid ?? '',
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(recipientId: userId, recipientName: displayName),
          ),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildGroupTile(GroupModel group) {
    final hasIcon = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: const Color(0xFF1E262C),
        backgroundImage: hasIcon ? NetworkImage(group.iconUrl!) : null,
        child: !hasIcon
            ? const Icon(Icons.groups_rounded, color: Colors.white70, size: 26)
            : null,
      ),
      title: Text(
        group.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${group.memberIds.length} miembros • 🔒 Grupo E2EE',
        style: const TextStyle(color: Colors.white38, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(groupId: group.id, groupName: group.name),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white30, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A884),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Buscar contactos 🔍'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: ESTADOS (Status / Stories)
  // ==========================================
  Widget _buildStatusTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Estados',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF1E262C),
                child: Text(
                  currentUser?.displayName?.isNotEmpty == true
                      ? currentUser!.displayName![0].toUpperCase()
                      : '🌸',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00A884),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
          title: const Text(
            'Mi estado',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: const Text(
            'Añade una actualización',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Los estados multimedia estarán disponibles muy pronto 🌸'),
                backgroundColor: Color(0xFF1E1E1E),
              ),
            );
          },
        ),
        const Divider(color: Colors.white12, height: 32),
        const Text(
          'ACTUALIZACIONES RECIENTES',
          style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              Icon(Icons.donut_large_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 12),
              const Text(
                'No hay actualizaciones de estado recientes',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Colors.white30),
                  const SizedBox(width: 6),
                  Text(
                    'Tus estados están protegidos con cifrado E2EE',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: REGISTRO DE LLAMADAS
  // ==========================================
  Widget _buildCallsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Llamadas',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFF00A884),
            child: Icon(Icons.link_rounded, color: Colors.black, size: 24),
          ),
          title: const Text(
            'Crear enlace de llamada',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: const Text(
            'Comparte un enlace para tu llamada cifrada',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Llamadas cifradas de voz y video en camino 📞'),
                backgroundColor: Color(0xFF1E1E1E),
              ),
            );
          },
        ),
        const Divider(color: Colors.white12, height: 32),
        const Text(
          'RECIENTES',
          style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 32),
        Center(
          child: Column(
            children: [
              Icon(Icons.call_end_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 12),
              const Text(
                'No hay llamadas recientes',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Colors.white30),
                  const SizedBox(width: 6),
                  Text(
                    'Tus llamadas personales están cifradas de extremo a extremo',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: CHAT DE IA (Crystal AI - Próximamente)
  // ==========================================
  Widget _buildAiChatTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Crystal AI 🌸',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF1744), Color(0xFF7C4DFF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'BETA',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2C34),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF1744).withOpacity(0.1),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF1744), Color(0xFF9C27B0), Color(0xFF29B6F6)],
                    ),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Chat de IA Inteligente',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tu asistente personal con cifrado total, generación de resúmenes, traducción en tiempo real y respuestas instantáneas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101D25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.hourglass_top_rounded, color: Color(0xFFFF1744), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'En desarrollo para la próxima versión',
                        style: TextStyle(color: Color(0xFFFF8DA1), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2C34),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF1744), size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pregúntale algo a Crystal AI...',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white30, size: 20),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El motor de IA estará activo en la siguiente actualización 🤖🌸'),
                        backgroundColor: Color(0xFF1E1E1E),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ==========================================
  // FLOATING ACTION BUTTON
  // ==========================================
  Widget? _buildFloatingActionButton() {
    if (_selectedBottomNavIndex == 0) {
      // Chats tab FAB
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Meta AI-style floating badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E262C),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF1744), size: 20),
              tooltip: 'Crystal AI',
              onPressed: () {
                setState(() {
                  _selectedBottomNavIndex = 3;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            backgroundColor: const Color(0xFF00A884),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
              );
            },
            child: const Icon(Icons.chat_bubble_rounded, color: Colors.black, size: 24),
          ),
        ],
      );
    } else if (_selectedBottomNavIndex == 1) {
      // Status tab FAB
      return FloatingActionButton(
        backgroundColor: const Color(0xFF00A884),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () {},
        child: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 24),
      );
    } else if (_selectedBottomNavIndex == 2) {
      // Calls tab FAB
      return FloatingActionButton(
        backgroundColor: const Color(0xFF00A884),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () {},
        child: const Icon(Icons.add_ic_call_rounded, color: Colors.black, size: 24),
      );
    }
    return null;
  }

  // ==========================================
  // BOTTOM NAVIGATION BAR (WhatsApp Style)
  // ==========================================
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B141B),
        border: Border(top: BorderSide(color: Color(0xFF1F2C34), width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.chat_rounded, 'Chats'),
          _buildNavItem(1, Icons.donut_large_rounded, 'Estados', hasNotification: true),
          _buildNavItem(2, Icons.call_rounded, 'Llamadas'),
          _buildNavItem(3, Icons.auto_awesome_rounded, 'Chat IA', isAi: true),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, {bool hasNotification = false, bool isAi = false}) {
    final isSelected = _selectedBottomNavIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedBottomNavIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isAi ? const Color(0x33FF1744) : const Color(0xFF0F392B))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? (isAi ? const Color(0xFFFF1744) : const Color(0xFF25D366))
                      : Colors.white54,
                ),
              ),
              if (hasNotification && !isSelected)
                Positioned(
                  top: 2,
                  right: 14,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF25D366),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Colors.white54,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget that shows last message preview for a direct chat conversation
class _LastMessagePreview extends StatefulWidget {
  final String userId;
  final String currentUserId;

  const _LastMessagePreview({required this.userId, required this.currentUserId});

  @override
  State<_LastMessagePreview> createState() => _LastMessagePreviewState();
}

class _LastMessagePreviewState extends State<_LastMessagePreview> {
  final _localDb = LocalDatabaseService();
  final _chatService = ChatService();

  @override
  Widget build(BuildContext context) {
    final chatId = _chatService.getChatId(widget.currentUserId, widget.userId);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _localDb.getLastMessage(chatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const Text(
            '🔒 Chat Cifrado E2EE',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          );
        }

        final msg = snapshot.data!;
        final text = msg['text'] as String? ?? '';
        final messageType = msg['message_type'] as String? ?? 'text';
        final senderId = msg['sender_id'] as String? ?? '';
        final isSentByMe = senderId == widget.currentUserId;
        final isRead = (msg['is_read'] as int? ?? 1) == 1;

        // Preview text
        String preview;
        if (messageType == 'image') {
          preview = isSentByMe ? '📷 Foto enviada' : '📷 Foto recibida';
        } else if (messageType == 'audio') {
          preview = isSentByMe ? '🎤 Mensaje de voz' : '🎤 Mensaje de voz recibido';
        } else if (text.startsWith('IMGENC:') || text.startsWith('E2EE:')) {
          preview = '🔒 Mensaje cifrado';
        } else {
          preview = text.length > 45 ? '${text.substring(0, 45)}...' : text;
        }

        return Row(
          children: [
            if (isSentByMe) ...[
              Icon(
                isRead ? Icons.done_all_rounded : Icons.done_rounded,
                size: 15,
                color: isRead ? const Color(0xFF53BDEB) : Colors.white38,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                preview,
                style: TextStyle(
                  color: isRead ? Colors.white38 : Colors.white,
                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
