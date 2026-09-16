part of dash_chat;

class ChatInputToolbar extends StatelessWidget {
  final TextEditingController? controller;
  final TextStyle? inputTextStyle;
  final TextCapitalization? textCapitalization;
  final List<Widget> leading;
  final List<Widget> trailing;
  final int inputMaxLines;
  final int? maxInputLength;
  final bool alwaysShowSend;
  final ChatUser user;
  final Function(ChatMessage)? onSend;
  final String? text;
  final Function(String)? onTextChange;
  final bool inputDisabled;
  final String Function()? messageIdGenerator;
  final Widget Function(Function)? sendButtonBuilder;
  final Widget Function()? inputFooterBuilder;
  final bool showInputCursor;
  final double inputCursorWidth;
  final Color? inputCursorColor;
  final ScrollController? scrollController;
  final bool showTrailingBeforeSend;
  final FocusNode? focusNode;
  final EdgeInsets inputToolbarPadding;
  final EdgeInsets inputToolbarMargin;
  final TextDirection textDirection;
  final bool sendOnEnter;
  final bool reverse;
  final TextInputAction? textInputAction;

  // UI Enhancements
  final String? hintText;
  final Widget? sendIcon;
  final Color? sendButtonColor;
  final Color? inputBackgroundColor;
  final double inputBorderRadius;
  final bool showCharacterCount;

  const ChatInputToolbar({
    super.key,
    this.textDirection = TextDirection.ltr,
    this.focusNode,
    this.scrollController,
    this.text,
    this.textInputAction,
    this.sendOnEnter = false,
    this.onTextChange,
    this.inputDisabled = false,
    this.controller,
    this.leading = const [],
    this.trailing = const [],
    this.textCapitalization,
    this.inputTextStyle,
    this.inputMaxLines = 5,
    this.showInputCursor = true,
    this.maxInputLength,
    this.inputCursorWidth = 2.0,
    this.inputCursorColor,
    this.onSend,
    this.reverse = false,
    required this.user,
    this.alwaysShowSend = false,
    this.messageIdGenerator,
    this.inputFooterBuilder,
    this.sendButtonBuilder,
    this.showTrailingBeforeSend = true,
    this.inputToolbarPadding =
    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.inputToolbarMargin = EdgeInsets.zero,
    this.hintText = "Type a message...",
    this.sendIcon,
    this.sendButtonColor,
    this.inputBackgroundColor,
    this.inputBorderRadius = 28,
    this.showCharacterCount = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasText = text?.trim().isNotEmpty == true;

    ChatMessage message = ChatMessage(
      text: text,
      user: user,
      messageIdGenerator: messageIdGenerator,
      createdAt: DateTime.now(),
      userName: user.name,
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        padding: inputToolbarPadding,
        margin: inputToolbarMargin,
        decoration: BoxDecoration(
          borderRadius: BorderRadiusGeometry.circular(32),
          border: Border.all(color: Colors.black12,width: 1.5),
          color: inputBackgroundColor ??
              (isDark ? Colors.black : Colors.white),
          boxShadow: [
            BoxShadow(
              color: context.colorS.outlineVariant,
              offset: const Offset(4, 4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (leading.isNotEmpty) ...leading,

                /// Input Field
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFF5F5F5),
                      borderRadius:
                      BorderRadius.circular(inputBorderRadius),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade300,
                        width: 0.8,
                      ),
                    ),
                    child: TextField(
                      focusNode: focusNode,
                      controller: controller,
                      enabled: !inputDisabled,
                      textCapitalization:
                      textCapitalization ??
                          TextCapitalization.sentences,
                      textInputAction:
                      textInputAction ?? TextInputAction.send,
                      minLines: 1,
                      maxLines: inputMaxLines,
                      maxLength: maxInputLength,
                      showCursor: showInputCursor,
                      cursorWidth: inputCursorWidth,
                      cursorColor:
                      inputCursorColor ?? theme.primaryColor,
                      style: inputTextStyle ??
                          AppFont.w500.getStyle(context, fontSize: 15,color: isDark
                              ? Colors.white
                              : Colors.black87),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: AppFont.w500.getStyle(context, fontSize: 14,color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade600,),
                        border: InputBorder.none,
                        counterText:
                        showCharacterCount ? null : "",
                      ),
                      onChanged: onTextChange,
                      onSubmitted: (value) {
                        if (sendOnEnter && value.trim().isNotEmpty) {
                          _sendMessage(context, message);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                /// Send Button
                if (showTrailingBeforeSend) ...trailing,

                if (sendButtonBuilder != null)
                  sendButtonBuilder!(() async {
                    if (hasText) {
                      await _sendMessage(context, message);
                    }
                  })
                else
                  AnimatedScale(
                    scale: hasText || alwaysShowSend ? 1 : 0.85,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: hasText || alwaysShowSend ? 1 : 0.6,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasText || alwaysShowSend
                              ? (sendButtonColor ??
                              theme.primaryColor)
                              : (isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade300),
                        ),
                        child: IconButton(
                          splashRadius: 22,
                          icon: sendIcon ??
                              const Icon(Icons.send_rounded),
                          color: context.colorS.onPrimary,
                          onPressed: (hasText ||
                              alwaysShowSend) &&
                              !inputDisabled
                              ? () =>
                              _sendMessage(context, message)
                              : null,
                        ),
                      ),
                    ),
                  ),

                if (!showTrailingBeforeSend) ...trailing,
              ],
            ),

            if (inputFooterBuilder != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: inputFooterBuilder!(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage(BuildContext context, ChatMessage message) async {
    if (text?.isEmpty != false) return;

    try {
      await onSend?.call(message);

      controller?.clear();
      onTextChange?.call("");

      // Keep focus on input field
      FocusScope.of(context).requestFocus(focusNode);

      // Scroll to bottom with smooth animation
      if (scrollController?.hasClients == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController?.hasClients == true) {
            scrollController?.animateTo(
              reverse ? 0.0 : scrollController!.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        });      }
    } catch (e) {
      // Show error feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message',style: AppFont.w400.getStyle(context, fontSize: 14),),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

}