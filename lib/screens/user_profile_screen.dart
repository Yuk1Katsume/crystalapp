import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message_model.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/contacts_service.dart';
import '../services/group_chat_service.dart';
import '../services/local_database_service.dart';
import '../services/supabase_config.dart';
import 'chat_screen.dart';
import 'image_viewer_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final String? initialAvatarUrl;

  const UserProfileScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.initialAvatarUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final AuthService _authService = AuthService();
  final BlockService _blockService = BlockService();
  final GroupChatService _groupService = GroupChatService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();

  String? _savedContactName;
  String? _displayName;
  String? _username;
  String? _phoneNumber;
  String? _avatarUrl;
  bool _isOnline = false;
  bool _isBlocked = false;
  bool _isLoading = true;

  List<Message> _mediaMessages = [];
  List<Message> _starredMessages = [];
  List<GroupModel> _groupsInCommon = [];

  @override
  void initState() {
    super.initState();
    _displayName = widget.recipientName;
    _avatarUrl = widget.initialAvatarUrl;
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);

    try {
      final currentUid = _authService.currentUser?.uid ?? '';
      final conversationId = currentUid.compareTo(widget.recipientId) < 0
          ? '${currentUid}_${widget.recipientId}'
          : '${widget.recipientId}_$currentUid';

      // 1. Fetch user data from Supabase
      try {
        final userData = await SupabaseConfig.client
            .from('users')
            .select('id, username, display_name, phone, avatar_url, is_online')
            .eq('id', widget.recipientId)
            .maybeSingle();

        if (userData != null) {
          _displayName = userData['display_name'] ?? _displayName;
          _username = userData['username'];
          _phoneNumber = userData['phone'];
          _avatarUrl = userData['avatar_url'] ?? _avatarUrl;
          _isOnline = userData['is_online'] == true;
        }
      } catch (_) {}

      // 2. Check if contact is saved in local phone agenda
      try {
        final contactName = await _contactsService.getContactNameForUser(
          widget.recipientId,
          _phoneNumber,
        );
        if (contactName != null && contactName.isNotEmpty) {
          _savedContactName = contactName;
        }
      } catch (_) {}

      // 3. Check blocked status
      _isBlocked = await _blockService.isUserBlocked(widget.recipientId);

      // 4. Load media and starred messages from local DB
      _mediaMessages = await _localDb.getMediaMessages(conversationId);
      _starredMessages = await _localDb.getStarredMessages(conversationId);

      // 5. Load groups in common
      _groupsInCommon = await _groupService.getGroupsInCommon(widget.recipientId);
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            const Icon(Icons.copy_rounded, color: Color(0xFFFF1744), size: 18),
            const SizedBox(width: 10),
            Text('$label copiado al portapapeles', style: const TextStyle(color: Colors.white)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openFullScreenAvatar() {
    final image = _avatarUrl;
    if (image == null || !image.startsWith('http')) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(_savedContactName ?? _displayName ?? 'Foto de perfil'),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Hero(
                tag: 'user_avatar_${widget.recipientId}',
                child: Image.network(
                  image,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const CircularProgressIndicator(color: Color(0xFFFF1744));
                  },
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

  Future<void> _toggleBlock() async {
    final name = _savedContactName ?? _displayName ?? 'este contacto';
    final willBlock = !_isBlocked;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          willBlock ? '¿Bloquear a $name?' : '¿Desbloquear a $name?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          willBlock
              ? 'Los contactos bloqueados no podrán enviarte mensajes ni ver tu estado.'
              : 'Este contacto podrá volver a enviarte mensajes.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: willBlock ? const Color(0xFFFF1744) : Colors.greenAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willBlock ? 'Bloquear' : 'Desbloquear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (willBlock) {
        await _blockService.blockUser(widget.recipientId);
      } else {
        await _blockService.unblockUser(widget.recipientId);
      }

      setState(() => _isBlocked = willBlock);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1E1E),
            content: Text(
              willBlock ? 'Contacto bloqueado' : 'Contacto desbloqueado',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
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
                  child: Text('No hay mensajes destacados en este chat', style: TextStyle(color: Colors.white54)),
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
                  child: Text('No se han enviado archivos ni fotos', style: TextStyle(color: Colors.white54)),
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
    final titleName = _savedContactName ?? _displayName ?? 'Usuario';
    final hasValidAvatar = _avatarUrl != null && _avatarUrl!.startsWith('http');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: CustomScrollView(
        slivers: [
          // 1. Collapsible AppBar with Profile Picture
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                titleName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
              background: GestureDetector(
                onTap: _openFullScreenAvatar,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasValidAvatar)
                      Hero(
                        tag: 'user_avatar_${widget.recipientId}',
                        child: Image.network(
                          _avatarUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(color: const Color(0xFF1A1A1A));
                          },
                          errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(titleName),
                        ),
                      )
                    else
                      _buildAvatarFallback(titleName),

                    // Gradient shadow for readable title
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                            Colors.black.withOpacity(0.85),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Body Info Cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contact Details Card
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
                        // Display / Contact Name
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                titleName,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (_savedContactName != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF1744).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Agenda 📱', style: TextStyle(color: Color(0xFFFF1744), fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),

                        // Username (@username)
                        if (_username != null && _username!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '@$_username',
                            style: const TextStyle(color: Color(0xFFFF1744), fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],

                        // Visible Name (if contact is saved with another name)
                        if (_savedContactName != null && _displayName != null && _displayName != _savedContactName) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Nombre en CrystalApp: $_displayName',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],

                        const SizedBox(height: 12),
                        const Divider(color: Colors.white12, height: 1),
                        const SizedBox(height: 12),

                        // Phone Number Row (with Copy Action)
                        InkWell(
                          onTap: () {
                            if (_phoneNumber != null && _phoneNumber!.isNotEmpty) {
                              _copyToClipboard(_phoneNumber!, 'Número de teléfono');
                            }
                          },
                          onLongPress: () {
                            if (_phoneNumber != null && _phoneNumber!.isNotEmpty) {
                              _copyToClipboard(_phoneNumber!, 'Número de teléfono');
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.phone_rounded, color: Colors.white60, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _phoneNumber != null && _phoneNumber!.isNotEmpty
                                            ? _phoneNumber!
                                            : 'Número no disponible',
                                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                                      ),
                                      const Text('Móvil · Mantén pulsado para copiar', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 18),
                                  onPressed: () {
                                    if (_phoneNumber != null && _phoneNumber!.isNotEmpty) {
                                      _copyToClipboard(_phoneNumber!, 'Número de teléfono');
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Online status
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isOnline ? const Color(0xFF00E676) : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOnline ? 'En línea' : 'Desconectado',
                              style: TextStyle(
                                color: _isOnline ? const Color(0xFF00E676) : Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Media, Links and Docs Section
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

                  // Starred Messages Section
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

                  // Groups in Common Section
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
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Text(
                            'Grupos en común (${_groupsInCommon.length})',
                            style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        if (_groupsInCommon.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                            child: Text('No tienes grupos en común con este contacto', style: TextStyle(color: Colors.white38, fontSize: 13)),
                          )
                        else
                          ..._groupsInCommon.map((group) {
                            final hasIcon = group.iconUrl != null && group.iconUrl!.isNotEmpty;
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF222222),
                                backgroundImage: hasIcon ? NetworkImage(group.iconUrl!) : null,
                                child: !hasIcon
                                    ? const Icon(Icons.group_rounded, color: Colors.white70, size: 18)
                                    : null,
                              ),
                              title: Text(group.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Text('${group.memberIds.length} miembros', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      groupId: group.id,
                                      groupName: group.name,
                                    ),
                                  ),
                                );
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
                                'Los mensajes de este chat están protegidos con cifrado E2EE nativo.',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Block / Unblock Contact Action Button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      onTap: _toggleBlock,
                      leading: Icon(
                        _isBlocked ? Icons.check_circle_outline_rounded : Icons.block_rounded,
                        color: _isBlocked ? Colors.greenAccent : const Color(0xFFFF1744),
                        size: 24,
                      ),
                      title: Text(
                        _isBlocked ? 'Desbloquear a $titleName' : 'Bloquear a $titleName',
                        style: TextStyle(
                          color: _isBlocked ? Colors.greenAccent : const Color(0xFFFF1744),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        _isBlocked
                            ? 'Pulsa para permitir que este contacto te envíe mensajes'
                            : 'Evita que este contacto pueda enviarte mensajes',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
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

  Widget _buildAvatarFallback(String name) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white70, fontSize: 72, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
