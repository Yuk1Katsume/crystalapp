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
  late TabController _tabController;
  late AnimationController _fabAnimationController;
  late Animation<double> _expandAnimation;
  final GroupChatService _groupService = GroupChatService();
  final AuthService _authService = AuthService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();
  final currentUser = FirebaseAuth.instance.currentUser;

  bool _isFabMenuOpen = false;
  Map<String, String> _phoneContactNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.fastOutSlowIn,
    );
    _ensureProfileSaved();
    _loadPhoneContacts();
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
    _tabController.dispose();
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text(
          'CrystalApp 🌸',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF1744),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFF1744),
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'CHATS DIRECTOS'),
            Tab(text: 'GRUPOS'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildDirectChatsList(),
              _buildGroupsList(),
            ],
          ),
          if (_isFabMenuOpen)
            GestureDetector(
              onTap: _toggleFabMenu,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _buildAnimatedExpandableFab(),
    );
  }

  Widget _buildDirectChatsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseConfig.client
          .from('users')
          .stream(primaryKey: ['id'])
          .map((data) => data.where((item) => item['id'] != currentUser?.uid).toList()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)));
        }

        final users = snapshot.data ?? [];

        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_chat_unread_outlined, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
                  'No tienes conversaciones activas.',
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
                  icon: const Icon(Icons.search, color: Colors.white),
                  label: const Text('Buscar Usuarios / Amigos 🔍', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
                    );
                  },
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userData = users[index];
            final userId = userData['id'];
            final rawDisplayName = userData['display_name'] ?? userData['username'] ?? 'Usuario';
            final contactName = _phoneContactNames[userId];
            final displayName = contactName ?? rawDisplayName;
            final isFromContacts = contactName != null;
            final username = userData['username'] ?? '';
            final isOnline = userData['is_online'] ?? false;
            final avatarUrl = userData['avatar_url'];

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
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
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
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
          },
        );
      },
    );
  }

  Widget _buildGroupsList() {
    return StreamBuilder<List<GroupModel>>(
      stream: _groupService.myGroups,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)));
        }

        final groups = snapshot.data ?? [];
        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.groups_outlined, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
                  'No estás en ningún grupo todavía.',
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toca el botón + y selecciona "Crear Grupo"',
                  style: TextStyle(color: Colors.white30, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFFFF1744),
                child: Icon(Icons.group_rounded, color: Colors.white, size: 24),
              ),
              title: Text(group.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text('${group.memberIds.length} miembros • 🔒 Grupo E2EE', style: const TextStyle(color: Colors.white38, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(groupId: group.id, groupName: group.name),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAnimatedExpandableFab() {
    return Container(
      alignment: Alignment.bottomRight,
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: ScaleTransition(
              scale: _expandAnimation,
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
            onPressed: _toggleFabMenu,
            child: AnimatedRotation(
              turns: _isFabMenuOpen ? 1.125 : 0.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutBack,
              child: const Icon(Icons.add, size: 28, color: Colors.white),
            ),
          ),
        ],
      ),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: label,
          backgroundColor: color,
          onPressed: onTap,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  void _showCreateGroupDialog() async {
    final groupNameController = TextEditingController();
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    final availableUsers = usersSnapshot.docs.where((doc) => doc.id != currentUser?.uid).toList();
    final selectedUserIds = <String>[];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Crear Nuevo Grupo 👥', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: groupNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nombre del Grupo',
                        labelStyle: TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF1744))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Selecciona Miembros:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: availableUsers.length,
                        itemBuilder: (context, index) {
                          final u = availableUsers[index];
                          final uData = u.data();
                          final name = uData['displayName'] ?? uData['username'] ?? uData['phone'] ?? 'Usuario';
                          final username = uData['username'] ?? '';
                          final isSelected = selectedUserIds.contains(u.id);

                          return CheckboxListTile(
                            activeColor: const Color(0xFFFF1744),
                            title: Text(name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('@$username', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            value: isSelected,
                            onChanged: (val) {
                              setStateDialog(() {
                                if (val == true) {
                                  selectedUserIds.add(u.id);
                                } else {
                                  selectedUserIds.remove(u.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
                  child: const Text('Crear Grupo', style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    final name = groupNameController.text.trim();
                    if (name.isNotEmpty && selectedUserIds.isNotEmpty) {
                      await _groupService.createGroup(name: name, memberIds: selectedUserIds);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
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
        } else if (text.startsWith('IMGENC:') || text.startsWith('E2EE:')) {
          preview = '🔒 Mensaje cifrado';
        } else {
          preview = text.length > 45 ? '${text.substring(0, 45)}...' : text;
        }

        if (isRead) {
          // Leído → Gris normal
          return Text(
            preview,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        } else {
          // No leído → Blanco y negrita
          return Text(
            preview,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
      },
    );
  }
}
