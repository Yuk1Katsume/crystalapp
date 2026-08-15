import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import '../models/status_model.dart';
import '../models/call_model.dart';
import '../services/group_chat_service.dart';
import '../services/auth_service.dart';
import '../services/local_database_service.dart';
import '../services/supabase_config.dart';
import '../services/chat_service.dart';
import '../services/status_service.dart';
import '../services/call_service.dart';
import 'chat_screen.dart';
import 'search_users_screen.dart';
import 'create_group_screen.dart';
import 'create_status_screen.dart';
import 'status_view_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';
import 'package:uuid/uuid.dart';
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

  late AnimationController _fabAnimationController;
  late Animation<double> _expandAnimation;
  bool _isFabMenuOpen = false;

  final GroupChatService _groupService = GroupChatService();
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final StatusService _statusService = StatusService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();
  final currentUser = FirebaseAuth.instance.currentUser;

  Map<String, String> _phoneContactNames = {};
  StreamSubscription? _incomingMsgSub;
  int _unreadChatCount = 0;
  bool _hasNewStatuses = false;
  String? _myProfileAvatarUrl;
  String? _myProfileDisplayName;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.fastOutSlowIn,
    );

    _ensureProfileSaved();
    _loadPhoneContacts();
    _refreshUnreadCount();
    _chatService.startGlobalIncomingListener();
    _incomingMsgSub = _chatService.onNewIncomingMessage.listen((_) {
      _refreshUnreadCount();
      if (mounted) setState(() {});
    });

    CallService().startIncomingCallListener();
    _incomingCallSub = CallService().onIncomingCall.listen((data) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callId: (data['call_id'] ?? data['id'] ?? data['doc_id'] ?? '').toString(),
              callerId: (data['caller_id'] ?? '').toString(),
              callerName: (data['caller_name'] ?? 'Contacto').toString(),
              callerAvatar: data['caller_avatar'] as String?,
              isVideo: data['is_video'] == true,
            ),
          ),
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  StreamSubscription? _incomingCallSub;

  void _refreshUnreadCount() async {
    final uid = currentUser?.uid;
    if (uid != null) {
      final count = await _localDb.getTotalUnreadCount(uid);
      if (mounted) {
        setState(() {
          _unreadChatCount = count;
        });
      }
    }
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
          .select('id, display_name, username, avatar_url')
          .eq('id', user.uid)
          .maybeSingle();

      if (existing == null) {
        await _authService.registerOrUpdateUserInSupabase(
          user,
          username: 'user_${user.uid.substring(0, 5)}',
          displayName: user.phoneNumber ?? 'Usuario',
        );
      } else {
        if (mounted) {
          setState(() {
            _myProfileAvatarUrl = existing['avatar_url'];
            _myProfileDisplayName = existing['display_name'] ?? existing['username'];
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    _incomingMsgSub?.cancel();
    _searchController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _toggleFabMenu() {
    setState(() {
      _isFabMenuOpen = !_isFabMenuOpen;
      if (_isFabMenuOpen) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            IndexedStack(
              index: _selectedBottomNavIndex,
              children: [
                _buildChatsTab(),
                _buildStatusTab(),
                _buildCallsTab(),
                _buildAiChatTab(),
              ],
            ),
            if (_isFabMenuOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleFabMenu,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _buildAnimatedExpandableFab(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildBottomNavigationBar(),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            icon: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
            tooltip: 'Cámara',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            color: const Color(0xFF1E1E1E),
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
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF262626), width: 1),
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
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF262626)),
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
                color: isSelected ? const Color(0x33FF1744) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFF1744).withOpacity(0.6) : const Color(0xFF262626),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFF1744) : Colors.white60,
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

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _localDb.getActiveConversationUserIds(myUid),
        _localDb.getUnreadConversationIds(myUid),
        _localDb.getFavoriteConversationIds(),
      ]),
      builder: (context, snapshot) {
        final activeUserIds = (snapshot.data?[0] as List<String>?) ?? [];
        final unreadIds = (snapshot.data?[1] as Set<String>?) ?? {};
        final favoriteIds = (snapshot.data?[2] as Set<String>?) ?? {};

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
                var filteredUsers = directUsers.where((u) {
                  if (_searchQuery.isEmpty) return true;
                  final name = (_phoneContactNames[u['id']] ?? u['display_name'] ?? u['username'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery);
                }).toList();

                // Filter groups by search
                var filteredGroups = groups.where((g) {
                  if (_searchQuery.isEmpty) return true;
                  return g.name.toLowerCase().contains(_searchQuery);
                }).toList();

                // Apply selected tab filter
                if (_selectedFilter == 'No leídos') {
                  filteredUsers = filteredUsers.where((u) => unreadIds.contains(u['id'])).toList();
                  filteredGroups = filteredGroups.where((g) => unreadIds.contains(g.id)).toList();

                  if (filteredUsers.isEmpty && filteredGroups.isEmpty) {
                    return _buildEmptyState(
                      'No tienes mensajes no leídos.',
                      '¡Todas tus conversaciones están al día! 🌸',
                    );
                  }
                } else if (_selectedFilter == 'Favoritos') {
                  filteredUsers = filteredUsers.where((u) => favoriteIds.contains(u['id'])).toList();
                  filteredGroups = filteredGroups.where((g) => favoriteIds.contains(g.id)).toList();

                  if (filteredUsers.isEmpty && filteredGroups.isEmpty) {
                    return _buildEmptyState(
                      'No tienes chats favoritos.',
                      'Mantén presionado un chat para añadirlo a tus favoritos ⭐',
                    );
                  }
                }

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
            backgroundColor: const Color(0xFF1E1E1E),
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
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0A0A0A), width: 2),
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
        _refreshUnreadCount();
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildGroupTile(GroupModel group) {
    final hasIcon = group.iconUrl != null &&
        group.iconUrl!.isNotEmpty &&
        group.iconUrl!.startsWith('http');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: const Color(0xFF1E1E1E),
        backgroundImage: hasIcon ? NetworkImage(group.iconUrl!) : null,
        child: !hasIcon
            ? Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.groups_rounded, color: Colors.white70, size: 26),
                ),
              )
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
              backgroundColor: const Color(0xFFFF1744),
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
              _refreshUnreadCount();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: ESTADOS (Real Data & E2EE Stories Only)
  // ==========================================
  Widget _buildStatusTab() {
    final currentUid = currentUser?.uid ?? '';

    return StreamBuilder<List<StatusItem>>(
      stream: _statusService.getMyStatusesStream(),
      builder: (context, myStatusesSnap) {
        final myStatuses = myStatusesSnap.data ?? [];

        return StreamBuilder<List<UserStatusGroup>>(
          stream: _statusService.getRecentStatusesStream(),
          builder: (context, contactGroupsSnap) {
            final contactGroups = contactGroupsSnap.data ?? [];

            // Update badge state
            final hasUnreadStatuses = contactGroups.any((g) => g.hasUnread(currentUid));
            if (hasUnreadStatuses != _hasNewStatuses && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hasNewStatuses = hasUnreadStatuses);
              });
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                // Top Novedades Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Novedades',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.search_rounded, color: Colors.white70),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Section: Estados Header
                const Text(
                  'Estados',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),

                // Horizontal scrollable story cards
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 1 + contactGroups.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildMyStatusCard(myStatuses);
                      }
                      final group = contactGroups[index - 1];
                      return _buildContactStoryCard(group);
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Section: Contactos con estados
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Actualizaciones recientes',
                      style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    if (contactGroups.isNotEmpty)
                      Text(
                        '${contactGroups.length}',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // If no contact statuses yet, show clean state
                if (contactGroups.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.donut_large_rounded, size: 52, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 14),
                        const Text(
                          'No hay actualizaciones recientes',
                          style: TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Los estados que compartan tus contactos mutuos aparecerán aquí con cifrado de extremo a extremo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white30, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  )
                else
                  // Real Contact Status List with Segmented Story Rings
                  ...contactGroups.map((group) => _buildContactStatusTile(group)),

                const SizedBox(height: 20),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded, size: 14, color: Colors.white30),
                      const SizedBox(width: 6),
                      Text(
                        'Tus estados están protegidos con cifrado E2EE',
                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMyStatusCard(List<StatusItem> myStatuses) {
    final hasActiveStatuses = myStatuses.isNotEmpty;
    final effectiveAvatarUrl = _myProfileAvatarUrl ?? currentUser?.photoURL;
    final displayName = _myProfileDisplayName ?? currentUser?.displayName ?? 'Mi estado';

    ImageProvider? bgImage;
    Color? bgColor;
    String? textSnippet;

    if (hasActiveStatuses) {
      final latestStatus = myStatuses.last;
      if (latestStatus.type == 'image') {
        try {
          if (latestStatus.content.startsWith('http')) {
            bgImage = NetworkImage(latestStatus.content);
          } else {
            bgImage = MemoryImage(base64Decode(latestStatus.content));
          }
        } catch (_) {}
      } else if (latestStatus.type == 'text') {
        if (latestStatus.backgroundColor.startsWith('#')) {
          try {
            final hex = latestStatus.backgroundColor.replaceAll('#', '');
            bgColor = Color(int.parse('FF$hex', radix: 16));
          } catch (_) {
            bgColor = const Color(0xFFFF1744);
          }
        } else {
          bgColor = const Color(0xFFFF1744);
        }
        textSnippet = latestStatus.content;
      }
    }

    return GestureDetector(
      onTap: () {
        if (hasActiveStatuses) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StatusViewScreen(
                statusGroup: UserStatusGroup(
                  userId: currentUser?.uid ?? '',
                  userName: displayName,
                  userAvatarUrl: effectiveAvatarUrl,
                  statuses: myStatuses,
                  lastUpdatedAt: myStatuses.last.createdAt,
                ),
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
          );
        }
      },
      child: Container(
        width: 105,
        decoration: BoxDecoration(
          color: bgColor ?? const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasActiveStatuses ? const Color(0xFFFF1744) : const Color(0xFF262626),
            width: hasActiveStatuses ? 1.5 : 1.0,
          ),
          image: bgImage != null
              ? DecorationImage(
                  image: bgImage,
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.35), BlendMode.darken),
                )
              : null,
        ),
        child: Stack(
          children: [
            // If text status, show preview snippet in center
            if (hasActiveStatuses && textSnippet != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    textSnippet,
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                ),
              ),

            // Top-left or center avatar
            if (hasActiveStatuses) ...[
              // Active: Small Avatar in top-left with story ring
              Positioned(
                top: 10,
                left: 10,
                child: CustomPaint(
                  painter: SegmentedStoryRingPainter(
                    count: myStatuses.length,
                    color: const Color(0xFFFF1744),
                    strokeWidth: 2.2,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3.0),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFF262626),
                      backgroundImage: (effectiveAvatarUrl != null && effectiveAvatarUrl.isNotEmpty)
                          ? NetworkImage(effectiveAvatarUrl)
                          : null,
                      child: (effectiveAvatarUrl == null || effectiveAvatarUrl.isEmpty)
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              // Top-right '+' button to add more statuses
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF1744),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ),
              // Bottom Text: Mi estado (X)
              Positioned(
                bottom: 10,
                left: 8,
                right: 8,
                child: Text(
                  'Mi estado\n(${myStatuses.length})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ] else ...[
              // Inactive: Prominent user avatar in center with '+' badge
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFF262626),
                          backgroundImage: (effectiveAvatarUrl != null && effectiveAvatarUrl.isNotEmpty)
                              ? NetworkImage(effectiveAvatarUrl)
                              : null,
                          child: (effectiveAvatarUrl == null || effectiveAvatarUrl.isEmpty)
                              ? Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF1744),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      'Añadir\nestado',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactStoryCard(UserStatusGroup group) {
    final contactName = _phoneContactNames[group.userId] ?? group.userName;
    final firstStatus = group.statuses.first;

    ImageProvider? bgImage;
    if (firstStatus.type == 'image') {
      try {
        if (firstStatus.content.startsWith('http')) {
          bgImage = NetworkImage(firstStatus.content);
        } else {
          bgImage = MemoryImage(base64Decode(firstStatus.content));
        }
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StatusViewScreen(statusGroup: group)),
        );
      },
      child: Container(
        width: 105,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2A2A)),
          image: bgImage != null
              ? DecorationImage(
                  image: bgImage,
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
                )
              : null,
        ),
        child: Stack(
          children: [
            // Segmented story ring avatar at top
            Positioned(
              top: 10,
              left: 10,
              child: CustomPaint(
                painter: SegmentedStoryRingPainter(
                  count: group.statuses.length,
                  color: const Color(0xFFFF1744),
                  strokeWidth: 2.2,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF262626),
                    backgroundImage: (group.userAvatarUrl != null && group.userAvatarUrl!.isNotEmpty)
                        ? NetworkImage(group.userAvatarUrl!)
                        : null,
                    child: (group.userAvatarUrl == null || group.userAvatarUrl!.isEmpty)
                        ? Text(
                            contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            // Contact Name at bottom
            Positioned(
              bottom: 10,
              left: 8,
              right: 8,
              child: Text(
                contactName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactStatusTile(UserStatusGroup group) {
    final contactName = _phoneContactNames[group.userId] ?? group.userName;
    final lastStatus = group.statuses.last;
    final count = group.statuses.length;

    String subtitle = '📷 Foto';
    if (lastStatus.type == 'text') {
      subtitle = lastStatus.content.length > 30 ? '${lastStatus.content.substring(0, 30)}...' : lastStatus.content;
    } else if (lastStatus.caption != null && lastStatus.caption!.isNotEmpty) {
      subtitle = lastStatus.caption!;
    }

    final diff = DateTime.now().difference(lastStatus.createdAt);
    String timeStr = 'Hace ${diff.inMinutes} min';
    if (diff.inMinutes >= 60 && diff.inHours < 24) {
      timeStr = 'Hace ${diff.inHours} h';
    } else if (diff.inHours >= 24) {
      timeStr = 'Ayer';
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CustomPaint(
        painter: SegmentedStoryRingPainter(
          count: count,
          color: const Color(0xFFFF1744),
          strokeWidth: 2.5,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF1E1E1E),
            backgroundImage: (group.userAvatarUrl != null && group.userAvatarUrl!.isNotEmpty)
                ? NetworkImage(group.userAvatarUrl!)
                : null,
            child: (group.userAvatarUrl == null || group.userAvatarUrl!.isEmpty)
                ? Text(
                    contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  )
                : null,
          ),
        ),
      ),
      title: Text(
        contactName,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white60, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: const TextStyle(color: Color(0xFFFF1744), fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: const BoxDecoration(
              color: Color(0xFFFF1744),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StatusViewScreen(statusGroup: group)),
        );
      },
    );
  }

  // ==========================================
  // TAB 2: REGISTRO DE LLAMADAS
  // ==========================================
  Widget _buildCallsTab() {
    return FutureBuilder<List<CallLog>>(
      future: _localDb.getCallLogs(),
      builder: (context, snapshot) {
        final callLogs = snapshot.data ?? [];

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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) async {
                    if (val == 'clear') {
                      await _localDb.clearAllCallLogs();
                      if (mounted) setState(() {});
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Borrar registro de llamadas', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFFFF1744),
                child: Icon(Icons.link_rounded, color: Colors.white, size: 24),
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
                    content: Text('Enlace de llamada cifrada copiado al portapapeles 📋'),
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
            const SizedBox(height: 12),

            if (callLogs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.phone_missed_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
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
              )
            else
              ...callLogs.map((log) {
                final isMissed = log.status == CallStatus.missed || log.status == CallStatus.rejected;
                final isIncoming = log.direction == CallDirection.incoming;

                IconData directionIcon;
                Color directionColor;

                if (isMissed) {
                  directionIcon = Icons.call_missed_rounded;
                  directionColor = const Color(0xFFFF1744);
                } else if (isIncoming) {
                  directionIcon = Icons.call_received_rounded;
                  directionColor = Colors.greenAccent;
                } else {
                  directionIcon = Icons.call_made_rounded;
                  directionColor = Colors.white70;
                }

                final resolvedName = _phoneContactNames[log.otherUserId] ??
                    (log.otherUserName.isNotEmpty && log.otherUserName != 'Contacto' && log.otherUserName != 'Usuario'
                        ? log.otherUserName
                        : 'Contacto');
                final initial = resolvedName.isNotEmpty && resolvedName != 'Contacto'
                    ? resolvedName[0].toUpperCase()
                    : 'C';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF1E1E1E),
                    backgroundImage: (log.otherUserAvatar != null && log.otherUserAvatar!.isNotEmpty && log.otherUserAvatar!.startsWith('http'))
                        ? NetworkImage(log.otherUserAvatar!)
                        : null,
                    child: (log.otherUserAvatar == null || !log.otherUserAvatar!.startsWith('http'))
                        ? Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF2E2E2E), Color(0xFF1A1A1A)],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: const TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    resolvedName,
                    style: TextStyle(
                      color: isMissed ? const Color(0xFFFF1744) : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Icon(directionIcon, size: 16, color: directionColor),
                      const SizedBox(width: 6),
                      Text(
                        '${_formatCallTime(log.timestamp)} · ${log.formattedDuration}',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      log.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: const Color(0xFFFF1744),
                    ),
                    onPressed: () {
                      final callId = const Uuid().v4();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CallScreen(
                            callId: callId,
                            otherUserId: log.otherUserId,
                            otherUserName: log.otherUserName,
                            otherUserAvatar: log.otherUserAvatar,
                            isOutgoing: true,
                            isVideo: log.isVideo,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  String _formatCallTime(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (isToday) {
      return 'Hoy $timeStr';
    } else {
      return '${date.day}/${date.month} $timeStr';
    }
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
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF1744).withOpacity(0.12),
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
                    color: const Color(0xFF121212),
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
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: const Color(0xFF262626)),
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
  // FLOATING ACTION BUTTONS
  // ==========================================
  Widget? _buildAnimatedExpandableFab() {
    if (_selectedBottomNavIndex == 0) {
      // Chats Tab: Expandable Circular FAB
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ScaleTransition(
            alignment: Alignment.bottomRight,
            scale: _expandAnimation,
            child: FadeTransition(
              opacity: _expandAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildFabMenuItem(
                    label: 'Buscar Usuarios',
                    icon: Icons.person_search_rounded,
                    color: const Color(0xFFFF1744),
                    onTap: () {
                      _toggleFabMenu();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildFabMenuItem(
                    label: 'Crear Grupo',
                    icon: Icons.group_add_rounded,
                    color: Colors.deepPurpleAccent,
                    onTap: () {
                      _toggleFabMenu();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          FloatingActionButton(
            backgroundColor: const Color(0xFFFF1744),
            elevation: 6,
            shape: const CircleBorder(),
            onPressed: _toggleFabMenu,
            child: AnimatedRotation(
              turns: _isFabMenuOpen ? 1.125 : 0.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutBack,
              child: const Icon(Icons.add, size: 28, color: Colors.white),
            ),
          ),
        ],
      );
    } else if (_selectedBottomNavIndex == 1) {
      // Estados Tab: Pencil + Camera FABs
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            backgroundColor: const Color(0xFF262626),
            elevation: 4,
            shape: const CircleBorder(),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
              );
            },
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            backgroundColor: const Color(0xFFFF1744),
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
              );
            },
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 26),
          ),
        ],
      );
    } else if (_selectedBottomNavIndex == 2) {
      // Calls Tab: Call FAB
      return FloatingActionButton(
        backgroundColor: const Color(0xFFFF1744),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () {},
        child: const Icon(Icons.add_ic_call_rounded, color: Colors.white, size: 26),
      );
    }
    return null;
  }

  Widget _buildFabMenuItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: FloatingActionButton.small(
            heroTag: label,
            backgroundColor: color,
            elevation: 4,
            shape: const CircleBorder(),
            onPressed: onTap,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // BOTTOM NAVIGATION BAR (Safe Area & Reactive Badges)
  // ==========================================
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(top: BorderSide(color: Color(0xFF1E1E1E), width: 1.0)),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.chat_rounded, 'Chats', hasNotification: _unreadChatCount > 0),
          _buildNavItem(1, Icons.donut_large_rounded, 'Novedades', hasNotification: _hasNewStatuses),
          _buildNavItem(2, Icons.call_rounded, 'Llamadas'),
          _buildNavItem(3, Icons.auto_awesome_rounded, 'Chat IA'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, {bool hasNotification = false}) {
    final isSelected = _selectedBottomNavIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedBottomNavIndex = index;
          if (_isFabMenuOpen) _toggleFabMenu();
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
                      ? const Color(0x33FF1744)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? const Color(0xFFFF1744)
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
                      color: Color(0xFFFF1744),
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
                  ? const Color(0xFFFF1744)
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

/// Custom painter to draw segmented Instagram / WhatsApp story rings
class SegmentedStoryRingPainter extends CustomPainter {
  final int count;
  final Color color;
  final double strokeWidth;
  final double gapAngle;

  SegmentedStoryRingPainter({
    required this.count,
    required this.color,
    this.strokeWidth = 2.5,
    this.gapAngle = 0.12, // radians
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    if (count <= 1) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    const totalSweep = 2 * math.pi;
    final totalGap = gapAngle * count;
    final arcSweep = (totalSweep - totalGap) / count;

    for (int i = 0; i < count; i++) {
      final startAngle = -math.pi / 2 + i * (arcSweep + gapAngle) + gapAngle / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SegmentedStoryRingPainter oldDelegate) {
    return oldDelegate.count != count || oldDelegate.color != color;
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
                color: isRead ? const Color(0xFFFF1744) : Colors.white38,
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
