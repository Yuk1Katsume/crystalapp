import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import '../services/local_database_service.dart';
import '../services/supabase_config.dart';
import '../services/block_service.dart';
import 'search_users_screen.dart';
import 'image_viewer_screen.dart';
import 'user_profile_screen.dart';
import 'group_info_screen.dart';
import '../widgets/adaptive_image_bubble.dart';

class Sticker {
  final String id;
  final String imageUrl;

  const Sticker({required this.id, required this.imageUrl});
}

class StickerPack {
  final String id;
  final String name;
  final String trayIconUrl;
  final List<Sticker> stickers;

  const StickerPack({
    required this.id,
    required this.name,
    required this.trayIconUrl,
    required this.stickers,
  });
}

final List<StickerPack> mockStickerPacks = [
  StickerPack(
    id: 'pack_0',
    name: 'Crysta Special',
    trayIconUrl: 'https://api.dicebear.com/7.x/bottts/png?seed=crysta1',
    stickers: List.generate(
      12,
      (i) => Sticker(
        id: 's_0_$i',
        imageUrl: 'https://api.dicebear.com/7.x/bottts/png?seed=crysta_$i',
      ),
    ),
  ),
  StickerPack(
    id: 'pack_1',
    name: 'Kawaii Cats',
    trayIconUrl: 'https://api.dicebear.com/7.x/catspirit/png?seed=cat1',
    stickers: List.generate(
      12,
      (i) => Sticker(
        id: 's_1_$i',
        imageUrl: 'https://api.dicebear.com/7.x/catspirit/png?seed=cat_$i',
      ),
    ),
  ),
];

final Map<String, List<String>> mockEmojis = {
  'Caras y Personas': [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '🫠', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '🥲', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🫡', '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '😮‍💨', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '🥸', '😎', '🤓', '🧐', '😕', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '🥹', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖',
    '👋', '🤚', '🖐️', '✋', '🖖', '🫲', '🫱', '🫴', '🫳', '🫵', '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '✍️', '💅', '🤳',
    '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👩', '🧓', '👴', '👵', '🙍', '🙎', '🙅', '🙆', '💁', '🙋', '🧏', '🙇', '🤦', '🤷', '👮', '🕵️', '💂', '🥷', '👷', '🤴', '👸', '👳', '👲', '🧕', '🤵', '👰', '🤰', '🤱', '👼', '🎅', '🤶', '🦸', '🦹', '🧙', '🧚', '🧛', '🧜', '🧝', '🧞', '🧟', '💃', '🕺', '🏃', '🚶'
  ],
  'Animales y Naturaleza': [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐵', '🐒', '🦍', '🦧', '🐕', '🐩', '🐺', '🦝', '🐈', '🦁', '🐯', '🐆', '🐴', '🐎', '🦄', '🦓', '🦌', '🦬', '🐮', '🐂', '🐃', '🐄', '🐷', '🐖', '🐗', '🐑', '🐏', '🐐', '🐪', '🐫', '🦙', '🦒', '🐘', '🦣', '🦏', '🦛', '🐭', '🐁', '🐀', '🐹', '🐰', '🐇', '🐿️', '🦫', '🦔', '🦇', '🦥', '🦦', '🦨', '🦘', '🦡',
    '🦅', '🦆', '🦢', '🦉', '🦩', '🦚', '🦜', '🐧', '🐥', '🐣', '🐤', '🐦', '🐓', '🦃', '🕊️', '🐍', '🦎', '🐊', '🐢', '🦕', '🦖',
    '🐳', '🐋', '🐬', '🦭', '🐟', '🐠', '🐡', '🦈', '🐙', '🐚', '🦀', '🦞', '🦐', '🦑', '🐌', '🦋', '🐛', '🐜', '🐝', '🐞', '<ctrl42>', '🕷️', '🦂', '🦟',
    '💐', '🌸', '💮', '🪷', '🌹', '🥀', '🌺', '🌻', '🌼', '🌷', '🪻', '🌱', '🪴', '🌲', '🌳', '🌴', '🌵', '🌾', '🌿', '☘️', '🍀', '🍁', '🍂', '🍃', '🍄'
  ],
  'Comida y Bebida': [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅', '🥔', '🍠', '🫚',
    '🍞', '🥐', '🥖', '🫓', '🥨', '🥯', '🥞', '🧇', '🧀', '🍖', '🍗', '🥩', '🥓', '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🌯', '🫔', '🥙', '🧆', '🥚', '🍳', '🥘', '🍲', '🫕', '🥣', '🥗', '🍿', '🧈', '🥫', '🍱', '🍘', '🍙', '🍚', '🍛', '🍜', '🍝', '🍢', '🍣', '🍤', '🍥', '🥮', '🍡', '🥟', '🥠', '🥡',
    '🍦', '🍧', '🍨', '🍩', '🍪', '🎂', '🍰', '🧁', '🥧', '🍫', '🍬', '🍭', '🍮', '🍯', '🍼', '🥛', '☕', '🍵', '🧃', '🥤', '🧋', '🍶', '🍾', '🍷', '🍸', '🍹', '🍺', '🍻', '🥂', '🥃', '🧊'
  ],
  'Actividades y Deportes': [
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱', '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '🏌️', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷', '⛸️', '🥌', '🎿',
    '🎯', '🪁', '👾', '🕹️', '🎰', '🎲', '🧩', '🧸', '🪅', '🪆', '♠️', '♥️', '♦️', '♣️', '🃏', '🀄', '🎴', '🎭', '🖼️', '🎨', '🧵', '🪡', '🧶', '🪢'
  ],
  'Viajes y Lugares': [
    '🚗', '🚕', '🚙', '🚌', '🛺', '🏎️', '🚓', '🚑', '🚒', '🚐', '🛻', '🚚', '🚛', '🚜', '🛴', '🚲', '🛵', '🏍️', '🚨', '🚔', '🚍', '🚘', '🚖', '🛩️', '✈️', '🛫', '🛬', '🪂', '💺', '🚁', '🚀', '🛰️', '🛸', '🛥️', '🚤', '⛴️', '🛳️', '🚢',
    '🏔️', '⛰️', '🌋', '🗻', '🏕️', '🏖️', '🏜️', '🏝️', '🏞️', '🏟️', '🏛️', '🏗️', '🧱', '🪨', '🪵', '🛖', '🏠', '🏡', '🏢', '🏣', '🏥', '🏦', '🏨', '🏩', '🏪', '🏫', '🏬', '🏭', '🏰', '🏯', '💒', '🗼', '🗽', '⛪', '🕌', '🛕', '🕍', '⛩️', '🕋'
  ],
  'Objetos': [
    '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🕹️', '🗜️', '💽', '💾', '💿', '📀', '📼', '📷', '📸', '📹', '🎥', '📽️', '🎞️', '📞', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🚡', '📡',
    '💡', '🔦', '🕯️', '🪔', '🧯', '🛢️', '💸', '💵', '💴', '💶', '💷', '🪙', '💰', '💳', '💎', '⚖️', '🧰', '🔧', '🔨', '⚒️', '🛠️', '⛏️', '🪛', '🗡️', '⚔️', '💣', '🔪', '🛡️', '🚬', '⚰️', '🪦', '⚱️', '🏺', '🔮', '📿', '🧿', '💈', '🩺', '🔬', '🔭', '💉', '🩸', '💊', '🩹', '🚪', '🛏️', '🛋️', 'TU', '🪠', '🚿', '🛁', '🪒', '🧴', '🧷', '🧹', '🧺', '🧻', '🧼', '🪥', '🧽',
    '🎷', '🪗', '🎸', '🎹', '🎺', '🎻', '🪕', '🥁', '🪘', '🪈'
  ],
  'Símbolos': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮️', '✝️', '☪️', '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️', '☦️', '🛐', '<ctrl42>', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓',
    '📴', '📳', '🈶', '🈚', '🈸', '🈺', '🈷️', '✴️', '🆚', '💮', '🉐', '㊙️', '㊗️', '🈴', '🈵', '🈹', '🈲', '🅰️', '🅱️', '🆎', '🆑', '🅾️', '🆘', '❌', '⭕', '🛑', '⛔', '📛', '🚫', '💯', '💢', '♨️', '🚷', '🚯', '🚳', '🚱', '🔞', '📵', '🚭', '❗', '❕', '❓', '🔘', '⚠️', '🚸', '🔱', '🔰', '♻️', '❇️', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⬛', '⬜', '🟥', '🟧', '🟨', '🟩', '🟦', '🟪'
  ],
  'Banderas': [
    '🏁', '🚩', '🎌', '🏴', '🏳️', '🏳️‍🌈', '🏴‍☠️',
    '🇪🇸', '🇦🇩', '🇦🇪', '🇦🇫', '🇦🇬', '🇦🇮', '🇦🇱', '🇦🇲', '🇦🇴', '🇦🇷', '🇦🇹', '🇦🇺', '🇦🇼', '🇦🇿', '🇧🇦', '🇧🇧', '🇧🇩', '🇧🇪', '🇧🇫', '🇧🇬', '🇧🇭', '🇧🇮', '🇧🇯', '🇧🇲', '🇧🇴', '🇧🇷', '🇧🇸', '🇧🇹', '🇧🇼', '🇧🇾', '🇧🇿', '🇨🇦', '🇨🇭', '🇨🇱', '🇨🇲', '🇨🇳', '🇨🇴', '🇨🇷', '🇨🇺', '🇨🇻', '🇨🇾', '🇨🇿', '🇩🇪', '🇩🇰', '🇩🇲', '🇩🇴', '🇩🇿', '🇪🇨', '🇪🇪', '🇪🇬', '🇪🇸', '🇫🇮', '🇫🇯', '🇫🇷', '🇬🇦', '🇬🇧', '🇬🇪', '🇬🇭', '🇬🇷', '🇬🇹', '🇭🇳', '🇭🇷', '🇭🇹', '🇭🇺', '🇮🇩', '🇮🇪', '🇮🇱', '🇮🇳', '🇮🇶', '🇮🇷', '🇮🇸', '🇮🇹', '🇯🇲', '🇯🇴', '🇯🇵', '🇰🇪', '🇰🇷', '🇰🇼', '🇰🇿', '🇱🇧', '🇱🇨', '🇱🇮', '🇱🇰', '🇱🇺', '🇱🇻', '🇲🇦', '🇲🇨', '🇲🇩', '🇲🇪', '🇲🇽', '🇲🇾', '🇳🇮', '🇳🇱', '🇳🇴', '🇳🇵', '🇳🇿', '🇵🇦', '🇵🇪', '🇵🇭', '🇵🇰', '🇵🇱', '🇵🇷', '🇵🇹', '🇵🇾', '🇶🇦', '🇷🇴', '🇷🇸', '🇷🇺', '🇸🇦', '🇸🇪', '🇸🇬', '🇸🇮', '🇸🇰', '🇸🇳', '🇸🇻', '🇸🇾', '🇹🇭', '🇹🇳', '🇹🇷', '🇹🇹', '🇹🇼', '🇺🇦', '🇺🇾', '🇺🇸', '🇻🇪', '🇻🇳', '🇿🇦'
  ],
};

class ChatScreen extends StatefulWidget {
  final String? recipientId;
  final String? recipientName;
  final String? groupId;
  final String? groupName;

  const ChatScreen({
    super.key,
    this.recipientId,
    this.recipientName,
    this.groupId,
    this.groupName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ChatService _chatService = ChatService();
  final GroupChatService _groupService = GroupChatService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final currentUser = FirebaseAuth.instance.currentUser;

  bool get isGroup => widget.groupId != null;
  bool _isPickerVisible = false;
  double _keyboardHeight = 280.0;
  String? _recipientAvatarUrl;

  // Multiple selection state
  final Set<Message> _selectedMessages = {};
  bool _initialScrollDone = false;
  Message? _replyingToMessage;
  Message? _editingMessage;
  final StreamController<List<Message>> _uiStreamController = StreamController<List<Message>>.broadcast();
  StreamSubscription<List<Message>>? _sub;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _fetchRecipientAvatar();
    _subscribeToPresence();
    _subscribeToMessages();
    _markConversationAsRead();
  }

  void _markConversationAsRead() {
    final chatId = isGroup ? widget.groupId! : _chatService.getChatId(_chatService.currentUserId, widget.recipientId ?? '');
    LocalDatabaseService().markMessagesAsRead(chatId);
  }

  void _subscribeToMessages() {
    _sub?.cancel();
    final sourceStream = isGroup
        ? _groupService.getGroupMessages(widget.groupId!)
        : _chatService.getChatMessagesWithUser(widget.recipientId ?? '');

    _sub = sourceStream.listen((data) {
      if (!_uiStreamController.isClosed) {
        _uiStreamController.add(data);
        _markConversationAsRead();
      }
    });
  }

  void _refreshMessages() async {
    final chatId = isGroup ? widget.groupId! : _chatService.getChatId(_chatService.currentUserId, widget.recipientId ?? '');
    final localMsgs = await LocalDatabaseService().getLocalMessages(chatId);
    if (!_uiStreamController.isClosed) {
      _uiStreamController.add(localMsgs);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _uiStreamController.close();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      if (_isPickerVisible) {
        setState(() {
          _isPickerVisible = false;
        });
      }
    }
  }

  void _togglePicker() async {
    if (_isPickerVisible) {
      _focusNode.requestFocus();
    } else {
      if (_focusNode.hasFocus) {
        _focusNode.unfocus();
        // Wait 250ms for Android keyboard slide-down animation to fully complete
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (mounted) {
        setState(() {
          _isPickerVisible = true;
        });
      }
    }
  }

  bool _recipientIsOnline = false;

  void _subscribeToPresence() {
    if (isGroup || widget.recipientId == null) return;
    SupabaseConfig.client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', widget.recipientId!)
        .listen((data) {
          if (data.isNotEmpty && mounted) {
            setState(() {
              _recipientIsOnline = data.first['is_online'] ?? false;
            });
          }
        });
  }

  void _fetchRecipientAvatar() async {
    if (isGroup || widget.recipientId == null) return;
    try {
      final res = await SupabaseConfig.client
          .from('users')
          .select('avatar_url, is_online')
          .eq('id', widget.recipientId!)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _recipientAvatarUrl = res['avatar_url'];
          _recipientIsOnline = res['is_online'] ?? false;
        });
      }
    } catch (e) {
      // Ignore
    }
  }


  void _toggleMessageSelection(Message msg) {
    setState(() {
      final exists = _selectedMessages.any((m) => m.id == msg.id);
      if (exists) {
        _selectedMessages.removeWhere((m) => m.id == msg.id);
      } else {
        _selectedMessages.add(msg);
      }
    });
  }

  void _copySelectedMessage() {
    if (_selectedMessages.length == 1) {
      final msg = _selectedMessages.first;
      Clipboard.setData(ClipboardData(text: msg.text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje copiado al portapapeles 📋')),
      );
    }
    setState(() => _selectedMessages.clear());
  }

  void _editSelectedMessage() {
    if (_selectedMessages.length == 1) {
      final msg = _selectedMessages.first;
      if (msg.type == ChatMessageType.text) {
        setState(() {
          _editingMessage = msg;
          _messageController.text = msg.text;
          _selectedMessages.clear();
        });
        _focusNode.requestFocus();
      }
    }
  }

  void _deleteSelectedMessages() async {
    final toDelete = List<Message>.from(_selectedMessages);
    setState(() {
      _selectedMessages.clear();
    });

    for (var msg in toDelete) {
      await _chatService.deleteMessage(msg.id);
    }

    if (mounted) {
      _refreshMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje(s) eliminado(s) localmente 🗑️')),
      );
    }
  }

  void _forwardSelectedMessages() async {
    final selectedMsgs = List<Message>.from(_selectedMessages);
    setState(() => _selectedMessages.clear());

    final targetUser = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
    );

    if (targetUser != null && targetUser['id'] != null) {
      for (var msg in selectedMsgs) {
        await _chatService.sendDirectMessage(
          recipientId: targetUser['id'],
          text: msg.text,
          mediaUrl: msg.mediaUrl,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reenviado a ${targetUser['display_name'] ?? targetUser['username']}')),
        );
      }
    }
  }

  Future<void> _starSelectedMessages() async {
    final anyNotStarred = _selectedMessages.any((m) => !m.isStarred);
    final targetStarred = anyNotStarred;

    for (var msg in _selectedMessages) {
      await _localDb.toggleStarredMessage(msg.id, targetStarred);
    }

    setState(() {
      _selectedMessages.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
          content: Text(
            targetStarred ? 'Mensaje añadido a destacados ⭐️' : 'Mensaje eliminado de destacados',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > 200) {
      _keyboardHeight = bottomInset;
    }

    final title = isGroup
        ? (widget.groupName ?? 'Grupo')
        : (widget.recipientName ?? 'Chat Directo');

    final isSelectionMode = _selectedMessages.isNotEmpty;
    final singleSelected = _selectedMessages.length == 1 ? _selectedMessages.first : null;
    final isSingleTextMessage = singleSelected != null && singleSelected.type == ChatMessageType.text;
    final allSelectedAreStarred = _selectedMessages.isNotEmpty && _selectedMessages.every((m) => m.isStarred);

    final pickerHeight = _keyboardHeight < 300 ? 320.0 : _keyboardHeight;

    return PopScope(
      canPop: !_isPickerVisible && _selectedMessages.isEmpty && !_focusNode.hasFocus,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedMessages.isNotEmpty) {
          setState(() => _selectedMessages.clear());
          return;
        }
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          return;
        }
        if (_isPickerVisible) {
          setState(() => _isPickerVisible = false);
          return;
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: isSelectionMode
            ? AppBar(
                backgroundColor: const Color(0xFF1E1E1E),
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _selectedMessages.clear()),
                ),
                title: Text(
                  '${_selectedMessages.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      allSelectedAreStarred ? Icons.star_rounded : Icons.star_border_rounded,
                      color: allSelectedAreStarred ? const Color(0xFFFF1744) : Colors.white,
                    ),
                    tooltip: allSelectedAreStarred ? 'Quitar destacado' : 'Destacar',
                    onPressed: _starSelectedMessages,
                  ),
                  if (_selectedMessages.length == 1 && isSingleTextMessage) ...[
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white),
                      onPressed: _copySelectedMessage,
                    ),
                    if (singleSelected.senderId == currentUser?.uid)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white),
                        onPressed: _editSelectedMessage,
                      ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.forward, color: Colors.white),
                    onPressed: _forwardSelectedMessages,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: _deleteSelectedMessages,
                  ),
                ],
              )
            : AppBar(
                backgroundColor: const Color(0xFF121212),
                foregroundColor: Colors.white,
                titleSpacing: 0,
                title: InkWell(
                  onTap: () {
                    if (isGroup && widget.groupId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupInfoScreen(
                            groupId: widget.groupId!,
                            groupName: title,
                          ),
                        ),
                      );
                    } else if (!isGroup && widget.recipientId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            recipientId: widget.recipientId!,
                            recipientName: title,
                            initialAvatarUrl: _recipientAvatarUrl,
                          ),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF1E1E1E),
                          backgroundImage: (_recipientAvatarUrl != null && _recipientAvatarUrl!.startsWith('http'))
                              ? NetworkImage(_recipientAvatarUrl!)
                              : null,
                          child: (_recipientAvatarUrl == null || !_recipientAvatarUrl!.startsWith('http'))
                              ? Text(
                                  title.isNotEmpty ? title[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isGroup
                                          ? Colors.deepPurpleAccent
                                          : (_recipientIsOnline ? Colors.greenAccent : Colors.grey),
                                    ),
                                  ),
                                  Text(
                                    isGroup
                                        ? 'Grupo · Cifrado E2EE'
                                        : (_recipientIsOnline ? 'Online · Cifrado E2EE' : 'Offline · Cifrado E2EE'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isGroup
                                          ? Colors.white70
                                          : (_recipientIsOnline ? Colors.greenAccent : Colors.grey),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        body: Column(
          children: [
            Expanded(child: _buildMessageList()),
            if (_replyingToMessage != null) _buildReplyPreview(),
            _buildInputBar(),
            if (_isPickerVisible)
              SizedBox(
                height: pickerHeight,
                child: WhatsAppMediaPicker(
                  onEmojiSelected: (emoji) {
                    _messageController.text += emoji;
                    _messageController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _messageController.text.length),
                    );
                  },
                  onStickerSelected: (sticker) async {
                    if (isGroup) {
                      await _groupService.sendGroupMessage(
                        groupId: widget.groupId!,
                        text: '🎨 Sticker',
                        type: ChatMessageType.sticker,
                        mediaUrl: sticker.imageUrl,
                      );
                    } else if (widget.recipientId != null) {
                      await _chatService.sendDirectMessage(
                        recipientId: widget.recipientId!,
                        text: '🎨 Sticker',
                        mediaUrl: sticker.imageUrl,
                        isSticker: true,
                      );
                    }
                    _scrollToBottom();
                  },
                  onBackspace: () {
                    final text = _messageController.text;
                    if (text.isNotEmpty) {
                      _messageController.text = text.characters.skipLast(1).string;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _messageController.text.length),
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          Container(width: 4, height: 36, color: const Color(0xFFFF1744)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respondiendo a ${_replyingToMessage!.senderId == currentUser?.uid ? "ti mismo" : (widget.recipientName ?? "Mensaje")}',
                  style: const TextStyle(color: Color(0xFFFF1744), fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  _replyingToMessage!.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white60, size: 18),
            onPressed: () => setState(() => _replyingToMessage = null),
          ),
        ],
      ),
    );
  }

  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageList() {
    return StreamBuilder<List<Message>>(
      stream: _uiStreamController.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)));
        }

        final messages = snapshot.data ?? [];
        if (messages.isEmpty) {
          return const Center(
            child: Text(
              '🔒 Los mensajes están cifrados de extremo a extremo.\nNadie fuera de este chat puede leerlos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        // Jump to bottom instantly on first load (no animation)
        if (!_initialScrollDone) {
          _initialScrollDone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final isMe = msg.senderId == currentUser?.uid;
            final isSelected = _selectedMessages.any((m) => m.id == msg.id);

            return Container(
              key: ValueKey('container_${msg.id}'),
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E3A8A).withOpacity(0.65) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Dismissible(
                key: Key('reply_${msg.id}'),
                direction: DismissDirection.startToEnd,
                confirmDismiss: (dir) async {
                  setState(() {
                    _replyingToMessage = msg;
                  });
                  return false;
                },
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  color: Colors.transparent,
                  child: const Icon(Icons.reply, color: Color(0xFFFF1744)),
                ),
                child: GestureDetector(
                  onLongPress: () => _toggleMessageSelection(msg),
                  onTap: () {
                    if (_selectedMessages.isNotEmpty) {
                      _toggleMessageSelection(msg);
                    }
                  },
                  child: _buildMessageBubble(msg, isMe, isSelected: isSelected),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(Message msg) {
    switch (msg.status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 13, color: Colors.white60);
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 14, color: Colors.white60);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white70);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Color(0xFFFF1744)); // Neon pink (#FF1744)
    }
  }

  Widget _buildMessageBubble(Message msg, bool isMe, {bool isSelected = false}) {
    final isSticker = msg.type == ChatMessageType.sticker || (msg.type == ChatMessageType.image && msg.text == '🎨 Sticker');

    if (isSticker && msg.mediaUrl != null) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: const Color(0xFFFF1744), width: 2.0),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Image.network(
                msg.mediaUrl!,
                width: 140,
                height: 140,
                fit: BoxFit.contain,
                cacheWidth: 280,
                cacheHeight: 280,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80, color: Colors.white30),
              ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xCC1E1E1E), // Semi-transparent dark mini-pill
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(msg),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Color bubbleColor;
    if (isSelected) {
      bubbleColor = isMe ? const Color(0xFFB71C1C) : const Color(0xFF263238);
    } else {
      bubbleColor = isMe ? const Color(0xFFFF1744) : const Color(0xFF1E1E1E);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          border: isSelected ? Border.all(color: const Color(0xFFFF1744), width: 2.0) : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isGroup && !isMe && msg.senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  msg.senderName!,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (msg.type == ChatMessageType.image && msg.mediaUrl != null)
              AdaptiveImageBubble(
                mediaUrl: msg.mediaUrl!,
                onTap: () {
                  if (_selectedMessages.isNotEmpty) {
                    _toggleMessageSelection(msg);
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImageViewerScreen(
                        imagePathOrUrl: msg.mediaUrl!,
                        message: msg,
                        senderName: isGroup ? msg.senderName : (isMe ? 'Tú' : (widget.recipientName ?? 'Contacto')),
                        onReply: () {
                          setState(() {
                            _replyingToMessage = msg;
                          });
                        },
                        onForward: () {
                          _selectedMessages.clear();
                          _selectedMessages.add(msg);
                          _forwardSelectedMessages();
                        },
                      ),
                    ),
                  );
                },
              )
            else
              Text(
                msg.text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg.isStarred) ...[
                    const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFF1744)),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(msg),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF121212),
      child: SafeArea(
        bottom: !_isPickerVisible,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _isPickerVisible ? Icons.keyboard : Icons.emoji_emotions_outlined,
                color: const Color(0xFFFF1744),
              ),
              onPressed: _togglePicker,
            ),
            IconButton(
              icon: const Icon(Icons.photo_library, color: Colors.white60),
              onPressed: _sendImage,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _editingMessage != null ? 'Editando mensaje...' : 'Escribe un mensaje cifrado...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFFFF1744),
              child: IconButton(
                icon: Icon(_editingMessage != null ? Icons.check : Icons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (!isGroup && widget.recipientId != null) {
      final isBlocked = await BlockService().isUserBlocked(widget.recipientId!);
      if (isBlocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF1E1E1E),
              content: Text('Has bloqueado a este contacto. Desbloquéalo para enviarle mensajes.', style: TextStyle(color: Colors.white)),
            ),
          );
        }
        return;
      }
    }

    var formattedText = text;
    if (_replyingToMessage != null) {
      formattedText = '↩️ "${_replyingToMessage!.text}"\n$text';
    }

    _messageController.clear();

    try {
      if (isGroup) {
        await _groupService.sendGroupMessage(
          groupId: widget.groupId!,
          text: formattedText,
        );
      } else if (widget.recipientId != null) {
        await _chatService.sendDirectMessage(
          recipientId: widget.recipientId!,
          text: formattedText,
        );
      }
      setState(() {
        _replyingToMessage = null;
        _editingMessage = null;
      });
      _refreshMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar mensaje: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _sendImage() async {
    final file = await _groupService.pickImage();
    if (file == null) return;

    if (isGroup) {
      await _groupService.sendGroupMessage(
        groupId: widget.groupId!,
        text: '📷 Imagen cifrada',
        type: ChatMessageType.image,
        mediaUrl: file.path,
      );
    } else if (widget.recipientId != null) {
      await _chatService.sendDirectMessage(
        recipientId: widget.recipientId!,
        text: '📷 Imagen cifrada',
        mediaUrl: file.path,
      );
    }
    if (mounted) {
      _refreshMessages();
    }
    _scrollToBottom();
  }
}

class WhatsAppMediaPicker extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<Sticker> onStickerSelected;
  final VoidCallback onBackspace;

  const WhatsAppMediaPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onStickerSelected,
    required this.onBackspace,
  });

  @override
  State<WhatsAppMediaPicker> createState() => _WhatsAppMediaPickerState();
}

class _WhatsAppMediaPickerState extends State<WhatsAppMediaPicker>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;
  int _selectedStickerPackIndex = 0;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      child: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _mainTabController,
              children: [
                _buildEmojiView(),
                const Center(child: Text('Buscador de GIFs', style: TextStyle(color: Colors.white54))),
                _buildStickerView(),
              ],
            ),
          ),
          Container(
            height: 48,
            color: const Color(0xFF121212),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _mainTabController,
                    indicatorColor: const Color(0xFFFF1744),
                    labelColor: const Color(0xFFFF1744),
                    unselectedLabelColor: Colors.white54,
                    tabs: const [
                      Tab(icon: Icon(Icons.emoji_emotions_outlined)),
                      Tab(child: Text('GIF', style: TextStyle(fontWeight: FontWeight.bold))),
                      Tab(icon: Icon(Icons.sticky_note_2_outlined)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.backspace_outlined, color: Colors.white60),
                  onPressed: widget.onBackspace,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _selectedEmojiCategoryIndex = 0;

  final List<IconData> _categoryIcons = const [
    Icons.sentiment_satisfied_alt,
    Icons.pets,
    Icons.fastfood,
    Icons.sports_soccer,
    Icons.directions_car,
    Icons.lightbulb_outline,
    Icons.favorite_border,
    Icons.flag_outlined,
  ];

  Widget _buildEmojiView() {
    final categories = mockEmojis.entries.toList();

    return Column(
      children: [
        Container(
          height: 40,
          color: const Color(0xFF1E1E1E),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final isSelected = index == _selectedEmojiCategoryIndex;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedEmojiCategoryIndex = index;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? const Color(0xFFFF1744) : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Icon(
                    _categoryIcons[index % _categoryIcons.length],
                    size: 22,
                    color: isSelected ? const Color(0xFFFF1744) : Colors.white54,
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: CustomScrollView(
            key: ValueKey(_selectedEmojiCategoryIndex),
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    categories[_selectedEmojiCategoryIndex].key,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final emoji = categories[_selectedEmojiCategoryIndex].value[index];
                    return InkWell(
                      onTap: () => widget.onEmojiSelected(emoji),
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    );
                  },
                  childCount: categories[_selectedEmojiCategoryIndex].value.length,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStickerView() {
    return Column(
      children: [
        Container(
          height: 40,
          color: const Color(0xFF1E1E1E),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: mockStickerPacks.length,
            itemBuilder: (context, index) {
              final pack = mockStickerPacks[index];
              final isSelected = index == _selectedStickerPackIndex;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedStickerPackIndex = index);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? const Color(0xFFFF1744) : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Image.network(pack.trayIconUrl, width: 28, height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.category, color: Colors.white)),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: mockStickerPacks[_selectedStickerPackIndex].stickers.length,
            itemBuilder: (context, index) {
              final sticker = mockStickerPacks[_selectedStickerPackIndex].stickers[index];
              return InkWell(
                onTap: () => widget.onStickerSelected(sticker),
                child: Image.network(
                  sticker.imageUrl,
                  fit: BoxFit.contain,
                  cacheWidth: 150,
                  cacheHeight: 150,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
