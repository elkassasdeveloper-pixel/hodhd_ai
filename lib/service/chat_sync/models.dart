class SyncLoginResponse {
  const SyncLoginResponse({
    required this.token,
    required this.token2,
    required this.isSuccess,
  });

  factory SyncLoginResponse.fromJson(Map<String, dynamic> json) {
    final isSuccess = json['isSuccess'] as bool? ?? false;
    final data = json['data'] as Map<String, dynamic>?;

    if (!isSuccess || data == null) {
      return const SyncLoginResponse(token: '', token2: '', isSuccess: false);
    }

    return SyncLoginResponse(
      token: data['token'] as String? ?? '',
      token2: data['token2'] as String? ?? '',
      isSuccess: true,
    );
  }

  final String token;
  final String token2;
  final bool isSuccess;
}

class SyncUserChild {
  const SyncUserChild({required this.secondUserId, required this.privateAdmin});

  final String secondUserId;
  final String privateAdmin;

  factory SyncUserChild.fromJson(Map<String, dynamic> json) {
    return SyncUserChild(
      secondUserId: json['second_user_id'] as String? ?? '',
      privateAdmin: json['private_admin'] as String? ?? '',
    );
  }
}