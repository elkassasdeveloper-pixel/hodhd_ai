part of dash_chat;

/// MessageContainer is just a wrapper around [Text], [Image]
/// component to present the message
class MessageContainer extends StatelessWidget {
  /// Message Object that will be rendered
  /// Takes a [ChatMessage] object
  final ChatMessage message;

  /// [DateFormat] object to render the date in desired
  /// format, if no format is provided it use
  /// the default `HH:mm:ss`
  final DateFormat? timeFormat;

  /// [messageTextBuilder] function takes a function with this
  /// structure [Widget Function(String)] to render the text inside
  /// the container.
  final Widget Function(String?, [ChatMessage])? messageTextBuilder;

  /// [messageImageBuilder] function takes a function with this
  /// structure [Widget Function(String)] to render the image inside
  /// the container.
  final Widget Function(String?, [ChatMessage])? messageImageBuilder;

  /// [messageTimeBuilder] function takes a function with this
  /// structure [Widget Function(String)] to render the time text inside
  /// the container.
  final Widget Function(String, [ChatMessage])? messageTimeBuilder;

  /// Provides a custom style to the message container
  /// takes [BoxDecoration]
  final BoxDecoration? messageContainerDecoration;

  /// Used to parse text to make it linkified text uses
  /// [flutter_parsed_text](https://pub.dev/packages/flutter_parsed_text)
  /// takes a list of [MatchText] in order to parse Email, phone, links
  /// and can also add custom pattersn using regex
  final List<MatchText> parsePatterns;

  /// A flag which is used for assiging styles
  final bool isUser;

  /// Provides a list of buttons to allow the usage of adding buttons to
  /// the bottom of the message
  final List<Widget>? buttons;

  /// [messageButtonsBuilder] function takes a function with this
  /// structure [List<Widget> Function()] to render the buttons inside
  /// a row.
  final List<Widget> Function(ChatMessage)? messageButtonsBuilder;

  /// Constraint to use to build the message layout
  final BoxConstraints? constraints;

  /// Padding of the message
  /// Default to EdgeInsets.all(8.0)
  final EdgeInsets messagePadding;

  /// Should show the text before the image in the chat bubble
  /// or the opposite
  /// Default to `true`
  final bool textBeforeImage;

  /// overrides the boxdecoration of the message
  /// can be used to override color, or customise the message container
  /// params [ChatMessage] and [isUser]: boolean
  /// return BoxDecoration
  final BoxDecoration Function(ChatMessage, bool?)? messageDecorationBuilder;

  const MessageContainer({super.key,
    required this.message,
    required this.timeFormat,
    this.constraints,
    this.messageImageBuilder,
    this.messageTextBuilder,
    this.messageTimeBuilder,
    this.messageContainerDecoration,
    this.parsePatterns = const <MatchText>[],
    this.textBeforeImage = true,
    required this.isUser,
    this.messageButtonsBuilder,
    this.buttons,
    this.messagePadding = const EdgeInsets.all(8.0),
    this.messageDecorationBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final constraints = this.constraints ??
        BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height,
            maxWidth: MediaQuery.of(context).size.width);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: constraints.maxWidth * 0.8,
      ),
      child: Container(
        decoration: messageDecorationBuilder?.call(message, isUser) ??
            messageContainerDecoration?.copyWith(
              color: message.user.containerColor ?? messageContainerDecoration!.color,
            ) ??
            BoxDecoration(
              color: message.user.containerColor ??
                  (isUser
                      ? Theme.of(context).primaryColor
                      : Color.fromRGBO(225, 225, 225, 1)),
              borderRadius: BorderRadius.circular(5.0),
            ),
        margin: EdgeInsets.only(
          bottom: 5.0,
        ),
        padding: messagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            if(!isUser)
             if(message.userName != null) Text(message.userName!,style: AppFont.w400.getStyle(context, fontSize: 14,color: context.colorS.primary),),
            SizedBox(height: 8,),
            if (textBeforeImage)
              _buildMessageText(context)
            else
              _buildMessageImage(),
            if (textBeforeImage)
              _buildMessageImage()
            else
              _buildMessageText(context),
            if (buttons != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment:
                    isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: buttons!,
              )
            else if (messageButtonsBuilder != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment:
                    isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: messageButtonsBuilder!(message),
              ),
            messageTimeBuilder?.call(
                  timeFormat?.format(message.createdAt) ??
                      DateFormat('HH:mm:ss').format(message.createdAt),
                  message,
                ) ??
                Padding(
                  padding: EdgeInsets.only(top: 5.0),
                  child: Text(
                    timeFormat != null
                        ? timeFormat!.format(message.createdAt)
                        : DateFormat('HH:mm:ss').format(message.createdAt)
    ,style: AppFont.w400.getStyle(context, fontSize: 10,color: message.user.color ??
                      (isUser ? context.colorS.onPrimary : Colors.black87),)
                  ),
                )
          ],
        ),
      ),
    );
  }

  Widget _buildMessageText(BuildContext context) {
    return messageTextBuilder?.call(message.text, message) ??
        ParsedText(
          parse: parsePatterns,
          text: message.text!
            ,style: AppFont.w400.getStyle(context, fontSize: 14, color: message.user.color ??
            (isUser ? context.colorS.onPrimary : Colors.black87),)
        );
  }

  Widget _buildMessageImage() {
    final Uint8List kTransparentImage = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    if (message.image != null) {
      return messageImageBuilder?.call(message.image, message) ??
          Padding(
            padding: EdgeInsets.only(top: 10.0, bottom: 10.0),
            child: FadeInImage.memoryNetwork(
              height: constraints!.maxHeight * 0.3,
              width: constraints!.maxWidth * 0.7,
              fit: BoxFit.contain,
              placeholder: kTransparentImage,
              image: message.image!,
            ),
          );
    }
    return SizedBox(width: 0, height: 0);
  }
}
