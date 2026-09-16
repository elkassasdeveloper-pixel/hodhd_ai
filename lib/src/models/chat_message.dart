part of '../../dash_chat.dart';

/// A message data structure used by dash chat to handle messages
/// and also to handle quick replies
class ChatMessage {
  /// Id of the message if no id is supplied a new id is assigned
  /// using a [UUID v4] this behaviour could be overriden by provind
  /// and [optional] paramter called [messageIdGenerator].
  /// [messageIdGenerator] take a function with this
  /// signature [String Function()]
  String? id;
  String? userName;

  /// Actual text message.
  String? text;

  /// It's a [non-optional] pararmter which specifies the time the
  /// message was delivered takes a [DateTime] object.
  late DateTime createdAt;

  /// Takes a [ChatUser] object which is used to distinguish between
  /// users and also provide avaatar URLs and name.
  late ChatUser user;

  /// A [non-optional] parameter which is used to display images
  /// takes a [Sring] as a url
  String? image;

  /// A [non-optional] parameter which is used to display vedio
  /// takes a [Sring] as a url
  String? video;

  /// A [non-optional] parameter which is used to show quick replies
  /// to the user
  QuickReplies? quickReplies;

  /// Allows to set custom-properties that could help with implementing custom
  /// functionality to dashchat.
  Map<String, dynamic>? customProperties;

  /// Allows to set buttons that could help with implementing custom
  /// actions in message container.
  List<Widget>? buttons;

  ChatMessage(
      {String? id,
      required this.text,
      required this.user,
      required this.userName,
      this.image,
      this.video,
      this.quickReplies,
      String Function()? messageIdGenerator,
      DateTime? createdAt,
      this.customProperties,
      this.buttons}) {
    this.createdAt = createdAt ?? DateTime.now();
    this.id = id ?? messageIdGenerator?.call() ?? Uuid().v4().toString();
  }

  ChatMessage.fromJson(Map<dynamic, dynamic> json) {
    id = json['id'];
    userName = json['userName'];
    text = json['text'];
    image = json['image'];
    video = json['video'] ?? json['vedio'];
    createdAt = DateTime.fromMillisecondsSinceEpoch(json['createdAt']);
    user = ChatUser.fromJson(json['user']);
    quickReplies = json['quickReplies'] != null
        ? QuickReplies.fromJson(json['quickReplies'])
        : null;
    customProperties = json['customProperties'] as Map<String, dynamic>?;
    buttons = json['buttons'] as List<Widget>?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};

    try {
      data['id'] = id;
      data['userName'] = userName;
      data['text'] = text;
      data['image'] = image;
      data['video'] = video;
      data['createdAt'] = createdAt.millisecondsSinceEpoch;
      data['user'] = user.toJson();
      data['quickReplies'] = quickReplies?.toJson();
      data['customProperties'] = customProperties;
    } catch (e, stack) {
      myPrintX('ERROR caught when trying to convert ChatMessage to JSON:');
      myPrintX(e.toString());
      myPrintX(stack.toString());
    }
    return data;
  }
}
/// A message data structure used by dash chat to handle messages
/// and also to handle quick replies
class ApiChatMessage {
  final int? id;
  final String userId;
  final String userName;
  final String text;
  final String? image;
  final String? video;
  final DateTime createdAt;

  ApiChatMessage({
    this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.createdAt,
    this.image,
    this.video,
  });

  factory ApiChatMessage.fromJson(Map<String, dynamic> json) {
    return ApiChatMessage(
      id: json['trans_id'] as int,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      text: json['message'] as String,
      createdAt: DateTime.parse(json['add_date'] as String),
      image: null,
      video: null,
    );
  }
}
ChatMessage mapToDashMessage(
    ApiChatMessage apiMessage,
    ChatUser currentUser,
    ) {
  return ChatMessage(
    userName: apiMessage.userName,
    text: apiMessage.text,
    user: ChatUser(
      uid: apiMessage.userId,
      name: apiMessage.userName,
    ),
    createdAt: apiMessage.createdAt,
  );
}