import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:hodhd_ai/service/cache_helper.dart';
import 'package:hodhd_ai/service/chat_sync/api_endpoints.dart';
import 'package:hodhd_ai/service/chat_sync/models.dart';

/// Handles: creating a per-install uuid user (once), logging it in each
/// session, resolving the "saeed" child's private_admin token via
/// user_childern, and posting each completed Q&A exchange to FugoMessage.
class ChatSyncService {
  final Dio _authDio = Dio(BaseOptions(baseUrl: ChatSyncEndpoints.authBaseUrl));
  final Dio _fugoDio = Dio(BaseOptions(baseUrl: ChatSyncEndpoints.fugoBaseUrl));

  static const String _adminUserId = 'saeed';
  static const String _adminPassword = 'zakigommah';
  static const int _messageMaxLength = 500;

  String? _privateAdminToken;
  bool _ready = false;

  bool get isReady => _ready;

  Future<SyncLoginResponse> _login(String userName, String password) async {
    final response = await _authDio.post(
      ChatSyncEndpoints.login,
      data: {'user_id': userName, 'password': password},
    );
    return SyncLoginResponse.fromJson(response.data as Map<String, dynamic>);
  }

  static String _generateShortId() {
    final uuid = const Uuid().v4().replaceAll('-', '');
    return uuid.substring(0, 20);
  }

  Future<void> _createSysUser(String uuid, String adminToken) async {
    await _authDio.post(
      ChatSyncEndpoints.addSysUser,
      options: Options(headers: {'Authorization': 'Bearer $adminToken'}),
      queryParameters: {"m_code" : 1},
      data: {
        'user_id': uuid,
        'user_full_name': 'hodhd_ai_$uuid',
        'job_title': '',
        'password': uuid,
        'work_email': '',
        'private_email': '',
        'mobile_no1': '',
        'mobile_no2': '',
        'remarks': '',
        'max_discount': 0,
        'is_admin': 'N',
        'is_active': 'Y',
        'curr_company_num': 0,
        'curr_year_num': 0,
        'curr_branch_num': 0,
        'emp_num': 0,
        'fk_curr_branch_num_descr': '',
        'fk_emp_num_descr': '',
      },
    );
  }

  Future<String?> _findSaeedPrivateAdmin(String token) async {
    final response = await _authDio.get(
      ChatSyncEndpoints.userChildren,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final json = response.data as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];

    for (final entry in data) {
      final child = SyncUserChild.fromJson(entry as Map<String, dynamic>);
      if (child.secondUserId == _adminUserId) {
        return child.privateAdmin;
      }
    }
    return null;
  }

  /// Call once, near app/cubit startup. Never throws — sync silently stays
  /// unavailable on any failure, and chat continues to work normally.
  Future<void> init() async {
    try {
      var uuid = CacheHelper.getData('chatSyncUuid') as String?;
      final alreadyCreated = CacheHelper.getData('chatSyncUserCreated') as bool? ?? false;

      if (uuid == null) {
        uuid = _generateShortId();
        await CacheHelper.saveData(key: 'chatSyncUuid', value: uuid);
      }

      if (!alreadyCreated) {
        final adminLogin = await _login(_adminUserId, _adminPassword);
        if (!adminLogin.isSuccess) return;

        await _createSysUser(uuid, adminLogin.token);
        await CacheHelper.saveData(key: 'chatSyncUserCreated', value: true);
      }

      final userLogin = await _login(uuid, uuid);
      if (!userLogin.isSuccess) return;

      _privateAdminToken = await _findSaeedPrivateAdmin(userLogin.token);
      _ready = _privateAdminToken != null;
    } catch (_) {
      _ready = false;
    }
  }

  /// Posts one completed Q&A exchange. Safe to call even if [init] failed
  /// or hasn't finished — it just silently does nothing in that case.
  Future<void> syncExchange(String? question, String? answer) async {
    if (!_ready || _privateAdminToken == null) return;

    final q = question?.trim() ?? '';
    final a = answer?.trim() ?? '';
    if (q.isEmpty && a.isEmpty) return;

    var message = 'Q:$q\nA:$a';
    if (message.length > _messageMaxLength) {
      message = message.substring(0, _messageMaxLength);
    }

    try {
      await _fugoDio.post(
        ChatSyncEndpoints.addFugoMessage,
        options: Options(headers: {'Authorization': 'Bearer $_privateAdminToken'}),
        data: {'message': message},
      );
    } catch (_) {
      // sync failures should never disrupt the chat itself
    }
  }
}