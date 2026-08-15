import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message_model.dart';
import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import '../services/group_chat_service.dart';
import '../services/local_database_service.dart';
import '../services/supabase_config.dart';
import 'chat_screen.dart';
import 'image_viewer_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final GroupChatService _groupService = GroupChatService();
  final AuthService _authService = AuthService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();

  GroupModel? _group;
  String _groupName = '';
  String? _groupDescription;
  String? _groupIconUrl;
  String _adminId = '';
  List<String> _memberIds = [];
  List<Map<String, dynamic>> _membersData = [];

  List<Message> _mediaMessages = [];
  List<Message> _starredMessages = [];

  bool _isLoading = true;
  bool _isUploadingIcon = false;
  StreamSubscription? _metadataSub;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
    _loadGroupDetails();
    _listenToGroupRealtimeUpdates();
  }

  @override
  void dispose() {
    _metadataSub?.cancel();
    super.dispose();
  }

  void _listenToGroupRealtimeUpdates() {
    try {
      _metadataSub = SupabaseConfig.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('group_id', 'GLOBAL_GROUPS')
          .listen((data) {
            for (var row in data) {
              try {
                if (row['message_type'] == 'group_metadata') {
                  final enc = row['encrypted_content'] as String? ?? '';
                  final map = jsonDecode(enc) as Map<String, dynamic>;
                  if (map['id'] == widget.groupId) {
                    final updated = GroupModel.fromJson(map);
                    if (mounted) {
                      setState(() {
                        _group = updated;
                        _groupName = updated.name;
                        _groupDescription = updated.description;
                        _groupIconUrl = updated.iconUrl;
                        _adminId = updated.adminId;
                        _memberIds = updated.memberIds;
                      });
                      _refreshMembersData(updated.memberIds);
                    }
                  }
                }
              } catch (_) {}
            }
          });
    } catch (_) {}
  }

  Future<void> _refreshMembersData(List<String> memberIds) async {
    if (memberIds.isEmpty) {
      if (mounted) setState(() => _membersData = []);
      return;
    }
    try {
      final List<dynamic> users = await SupabaseConfig.client
          .from('users')
          .select('id, username, display_name, phone, avatar_url, is_online')
          .filter('id', 'in', memberIds);

      final List<Map<String, dynamic>> resolvedMembers = [];
      for (final u in users) {
        final uMap = Map<String, dynamic>.from(u as Map);
        final uid = uMap['id']?.toString() ?? '';
        final phone = uMap['phone']?.toString();

        final contactName = await _contactsService.getContactNameForUser(uid, phone);
        if (contactName != null && contactName.isNotEmpty) {
          uMap['resolved_name'] = contactName;
          uMap['is_in_contacts'] = true;
        } else {
          uMap['resolved_name'] = uMap['display_name'] ?? uMap['username'] ?? 'Usuario';
          uMap['is_in_contacts'] = false;
        }
        resolvedMembers.add(uMap);
      }
      if (mounted) {
        setState(() {
          _membersData = resolvedMembers;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadGroupDetails() async {
    setState(() => _isLoading = true);

    try {
      final group = await _groupService.getGroupDetails(widget.groupId);
      if (group != null) {
        _group = group;
        _groupName = group.name;
        _groupDescription = group.description;
        _groupIconUrl = group.iconUrl;
        _adminId = group.adminId;
        _memberIds = group.memberIds;
      }

      // 1. Load member profile data from Supabase
      if (_memberIds.isNotEmpty) {
        try {
          final List<dynamic> users = await SupabaseConfig.client
              .from('users')
              .select('id, username, display_name, phone, avatar_url, is_online')
              .filter('id', 'in', _memberIds);

          final List<Map<String, dynamic>> resolvedMembers = [];
          for (final u in users) {
            final uMap = Map<String, dynamic>.from(u as Map);
            final uid = uMap['id']?.toString() ?? '';
            final phone = uMap['phone']?.toString();

            // Resolve name with phone contacts agenda
            final contactName = await _contactsService.getContactNameForUser(uid, phone);
            if (contactName != null && contactName.isNotEmpty) {
              uMap['resolved_name'] = contactName;
              uMap['is_in_contacts'] = true;
            } else {
              uMap['resolved_name'] = uMap['display_name'] ?? uMap['username'] ?? 'Usuario';
              uMap['is_in_contacts'] = false;
            }
            resolvedMembers.add(uMap);
          }
          _membersData = resolvedMembers;
        } catch (_) {}
      }

      // 2. Load media (excluding stickers) and starred messages
      _mediaMessages = await _localDb.getMediaMessages(widget.groupId);
      _starredMessages = await _localDb.getStarredMessages(widget.groupId);
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndChangeGroupIcon() async {
    try {
      final picked = await _groupService.pickImage();
      if (picked == null) return;

      setState(() => _isUploadingIcon = true);

      final oldIcon = _groupIconUrl;
      final url = await _groupService.uploadGroupIcon(widget.groupId, File(picked.path), oldIconUrl: oldIcon);
      if (url != null && mounted) {
        setState(() {
          _groupIconUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E1E1E),
            content: Text('Foto del grupo actualizada con éxito ✨', style: TextStyle(color: Colors.white)),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E1E1E),
            content: Text('No se pudo subir la foto del grupo. Comprueba tu conexión.', style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1E1E),
            content: Text('Error al cambiar la foto: $e', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingIcon = false);
      }
    }
  }

  void _openFullScreenIcon() {
    if (_groupIconUrl == null || !_groupIconUrl!.startsWith('http')) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(_groupName),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Hero(
                tag: 'group_icon_${widget.groupId}',
                child: Image.network(
                  _groupIconUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const CircularProgressIndicator(color: Color(0xFFFF1744)),
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editGroupName() async {
    final controller = TextEditingController(text: _groupName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar nombre del grupo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nombre del grupo...',
            hintStyle: TextStyle(color: Colors.white38),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF1744))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _groupName) {
      await _groupService.updateGroupInfo(groupId: widget.groupId, name: newName);
      setState(() => _groupName = newName);
    }
  }

  Future<void> _editGroupDescription() async {
    final controller = TextEditingController(text: _groupDescription ?? '');

    final newDesc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Descripción del grupo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Añade una descripción para este grupo...',
            hintStyle: TextStyle(color: Colors.white38),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF1744))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newDesc != null) {
      await _groupService.updateGroupInfo(groupId: widget.groupId, description: newDesc);
      setState(() => _groupDescription = newDesc);
    }
  }

  void _openAddMembersModal() async {
    final currentUid = _authService.currentUser?.uid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddMembersBottomSheet(
        currentMemberIds: _memberIds,
        onMembersAdded: (newMemberIds) async {
          Navigator.pop(ctx);
          if (newMemberIds.isEmpty) return;

          setState(() => _isLoading = true);
          await _groupService.addMembersToGroup(widget.groupId, newMemberIds);
          await _loadGroupDetails();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF1E1E1E),
                content: Text('${newMemberIds.length} participante(s) añadido(s) con éxito 🎉', style: const TextStyle(color: Colors.white)),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('¿Salir del grupo "$_groupName"?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Ya no recibirás los mensajes enviados en este grupo.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final currentUid = _authService.currentUser?.uid ?? '';
      await _groupService.removeMemberFromGroup(widget.groupId, currentUid);

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }
  }

  void _openStarredMessagesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
            title: const Text('Mensajes destacados ⭐️', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          body: _starredMessages.isEmpty
              ? const Center(
                  child: Text('No hay mensajes destacados en este grupo', style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _starredMessages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _starredMessages[i];
                    final time =
                        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')} · ${msg.timestamp.day}/${msg.timestamp.month}/${msg.timestamp.year}';

                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.star_rounded, color: Color(0xFFFF1744), size: 28),
                        title: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: Text(time, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _openMediaGalleryScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
            title: const Text('Archivos y multimedia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          body: _mediaMessages.isEmpty
              ? const Center(
                  child: Text('No se han enviado fotos ni audios', style: TextStyle(color: Colors.white54)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _mediaMessages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _mediaMessages[i];
                    if (msg.mediaUrl != null && msg.mediaUrl!.startsWith('http')) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ImageViewerScreen(
                                imagePathOrUrl: msg.mediaUrl!,
                                message: msg,
                                senderName: msg.senderName,
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            msg.mediaUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) =>
                                progress == null ? child : Container(color: const Color(0xFF1E1E1E)),
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
                          ),
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Icon(Icons.audiotrack_rounded, color: Color(0xFFFF1744), size: 28)),
                    );
                  },
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _authService.currentUser?.uid ?? '';
    final hasValidIcon = _groupIconUrl != null && _groupIconUrl!.startsWith('http');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)))
          : CustomScrollView(
              slivers: [
                // 1. Collapsible AppBar with Group Icon and Change Photo button
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  backgroundColor: const Color(0xFF121212),
                  foregroundColor: Colors.white,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      _groupName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: _openFullScreenIcon,
                          child: hasValidIcon
                              ? Hero(
                                  tag: 'group_icon_${widget.groupId}',
                                  child: Image.network(
                                    _groupIconUrl!,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) =>
                                        progress == null ? child : Container(color: const Color(0xFF1E1E1E)),
                                    errorBuilder: (_, __, ___) => _buildDefaultGroupBanner(),
                                  ),
                                )
                              : _buildDefaultGroupBanner(),
                        ),

                        // Gradient shadow
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.3),
                                Colors.transparent,
                                Colors.black.withOpacity(0.85),
                              ],
                            ),
                          ),
                        ),

                        // Camera button to change group photo
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton.small(
                            backgroundColor: const Color(0xFFFF1744),
                            foregroundColor: Colors.white,
                            onPressed: _isUploadingIcon ? null : _pickAndChangeGroupIcon,
                            child: _isUploadingIcon
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt_rounded, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Info Cards
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group Name & Description Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _groupName,
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: Color(0xFFFF1744), size: 20),
                                    onPressed: _editGroupName,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _editGroupDescription,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _groupDescription != null && _groupDescription!.isNotEmpty
                                              ? _groupDescription!
                                              : 'Añade una descripción del grupo...',
                                          style: TextStyle(
                                            color: _groupDescription != null && _groupDescription!.isNotEmpty
                                                ? Colors.white70
                                                : Colors.white38,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.edit_note_rounded, color: Colors.white38, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Grupo creado el ${_group?.createdAt.day ?? DateTime.now().day}/${_group?.createdAt.month ?? DateTime.now().month}/${_group?.createdAt.year ?? DateTime.now().year}',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Media, Links & Docs Section (Stickers EXCLUDED)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                onTap: _openMediaGalleryScreen,
                                title: const Text('Archivos, enlaces y docs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${_mediaMessages.length}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                                  ],
                                ),
                              ),
                              if (_mediaMessages.isNotEmpty)
                                Container(
                                  height: 74,
                                  padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _mediaMessages.take(8).length,
                                    itemBuilder: (ctx, i) {
                                      final msg = _mediaMessages[i];
                                      if (msg.mediaUrl != null && msg.mediaUrl!.startsWith('http')) {
                                        return Container(
                                          width: 62,
                                          margin: const EdgeInsets.only(right: 8),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              msg.mediaUrl!,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (_, child, progress) =>
                                                  progress == null ? child : Container(color: const Color(0xFF1E1E1E)),
                                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
                                            ),
                                          ),
                                        );
                                      }
                                      return Container(
                                        width: 62,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                                        child: const Center(child: Icon(Icons.audiotrack_rounded, color: Color(0xFFFF1744), size: 22)),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Starred Messages Section (Neon Pink Star)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: ListTile(
                            onTap: _openStarredMessagesScreen,
                            leading: const Icon(Icons.star_rounded, color: Color(0xFFFF1744), size: 24),
                            title: const Text('Mensajes destacados', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${_starredMessages.length}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Group Members (Participantes)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text(
                                  '${_membersData.length} participantes',
                                  style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),

                              // ADD MEMBERS BUTTON
                              ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF1744),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
                                ),
                                title: const Text(
                                  'Añadir participantes',
                                  style: TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                onTap: _openAddMembersModal,
                              ),

                              const Divider(color: Colors.white12, height: 1),

                              ..._membersData.map((m) {
                                final uid = m['id']?.toString() ?? '';
                                final name = m['resolved_name'] ?? m['display_name'] ?? m['username'] ?? 'Usuario';
                                final username = m['username'] ?? '';
                                final avatarUrl = m['avatar_url']?.toString();
                                final hasAvatar = avatarUrl != null && avatarUrl.startsWith('http');
                                final isAdmin = uid == _adminId;
                                final isMe = uid == currentUid;

                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFF1E1E1E),
                                    backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                                    child: !hasAvatar
                                        ? Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          isMe ? '$name (Tú)' : name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (m['is_in_contacts'] == true) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF1744).withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Agenda 📱', style: TextStyle(color: Color(0xFFFF1744), fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    username.isNotEmpty ? '@$username' : '',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  trailing: isAdmin
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.deepPurpleAccent.withOpacity(0.25),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Admin del grupo',
                                            style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      : null,
                                  onTap: isMe
                                      ? null
                                      : () {
                                          _showMemberActionsDialog(m);
                                        },
                                );
                              }).toList(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // E2EE Security Section
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outline_rounded, color: Color(0xFFFF1744), size: 24),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Cifrado de extremo a extremo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    SizedBox(height: 2),
                                    Text(
                                      'Los mensajes y archivos de este grupo están cifrados con clave E2EE de grupo.',
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Leave Group Action
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                          ),
                          child: ListTile(
                            onTap: _leaveGroup,
                            leading: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFFF1744), size: 24),
                            title: const Text(
                              'Salir del grupo',
                              style: TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showMemberActionsDialog(Map<String, dynamic> member) {
    final name = member['resolved_name'] ?? member['display_name'] ?? member['username'] ?? 'Usuario';
    final uid = member['id']?.toString() ?? '';
    final myUid = _authService.currentUser?.uid ?? '';
    final isMeAdmin = _adminId == myUid;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
              title: Text('Enviar mensaje directo a $name', style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(recipientId: uid, recipientName: name),
                  ),
                );
              },
            ),
            if (isMeAdmin && uid != myUid)
              ListTile(
                leading: const Icon(Icons.person_remove_rounded, color: Color(0xFFFF1744)),
                title: Text('Eliminar a $name del grupo', style: const TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      title: Text('Eliminar a $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      content: Text('¿Deseas eliminar a $name de este grupo?', style: const TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
                          onPressed: () => Navigator.pop(dCtx, true),
                          child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    final ok = await _groupService.removeMemberFromGroup(widget.groupId, uid);
                    if (ok && mounted) {
                      setState(() {
                        _memberIds.remove(uid);
                        _membersData.removeWhere((m) => m['id'] == uid);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$name fue eliminado del grupo'), backgroundColor: const Color(0xFF1E1E1E)),
                      );
                    }
                  }
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultGroupBanner() {
    return Container(
      color: const Color(0xFF1F1A2C),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_rounded, size: 72, color: Colors.deepPurpleAccent),
            const SizedBox(height: 8),
            Text(
              _groupName,
              style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMembersBottomSheet extends StatefulWidget {
  final List<String> currentMemberIds;
  final Function(List<String>) onMembersAdded;

  const _AddMembersBottomSheet({
    required this.currentMemberIds,
    required this.onMembersAdded,
  });

  @override
  State<_AddMembersBottomSheet> createState() => _AddMembersBottomSheetState();
}

class _AddMembersBottomSheetState extends State<_AddMembersBottomSheet> {
  final ContactsServiceManager _contactsService = ContactsServiceManager();
  final AuthService _authService = AuthService();
  final Set<String> _selectedUids = {};
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableUsers() async {
    final currentUid = _authService.currentUser?.uid;
    final excludeSet = {...widget.currentMemberIds, if (currentUid != null) currentUid};

    try {
      // 1. Load phone contacts
      final contactsRes = await _contactsService.syncContacts();
      final List<MatchedContact> registeredContacts = contactsRes['registered'] ?? [];

      // 2. Load all Supabase users
      final List<dynamic> usersRes = await SupabaseConfig.client
          .from('users')
          .select('id, username, display_name, phone, avatar_url, is_online');

      final List<Map<String, dynamic>> list = [];
      for (final u in usersRes) {
        final uMap = Map<String, dynamic>.from(u as Map);
        final uid = uMap['id']?.toString() ?? '';
        if (excludeSet.contains(uid)) continue;

        final phone = uMap['phone']?.toString();
        final contactName = await _contactsService.getContactNameForUser(uid, phone);

        if (contactName != null && contactName.isNotEmpty) {
          uMap['resolved_name'] = contactName;
          uMap['is_in_contacts'] = true;
        } else {
          uMap['resolved_name'] = uMap['display_name'] ?? uMap['username'] ?? 'Usuario';
          uMap['is_in_contacts'] = false;
        }

        list.add(uMap);
      }

      _availableUsers = list;
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase().trim();
    final filtered = _availableUsers.where((u) {
      final name = (u['resolved_name'] ?? '').toString().toLowerCase();
      final username = (u['username'] ?? '').toString().toLowerCase();
      return name.contains(query) || username.contains(query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Añadir participantes',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (_selectedUids.isNotEmpty)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1744),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () => widget.onMembersAdded(_selectedUids.toList()),
                  child: Text(
                    'Añadir (${_selectedUids.length})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar contacto o usuario...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)))
                : filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay contactos disponibles para añadir',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final u = filtered[i];
                          final uid = u['id']?.toString() ?? '';
                          final name = u['resolved_name'] ?? 'Usuario';
                          final username = u['username'] ?? '';
                          final avatarUrl = u['avatar_url']?.toString();
                          final isSelected = _selectedUids.contains(uid);

                          return CheckboxListTile(
                            activeColor: const Color(0xFFFF1744),
                            checkColor: Colors.white,
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedUids.add(uid);
                                } else {
                                  _selectedUids.remove(uid);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF262626),
                              backgroundImage: (avatarUrl != null && avatarUrl.startsWith('http'))
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || !avatarUrl.startsWith('http'))
                                  ? Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (u['is_in_contacts'] == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF1744).withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Agenda 📱', style: TextStyle(color: Color(0xFFFF1744), fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              username.isNotEmpty ? '@$username' : '',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
