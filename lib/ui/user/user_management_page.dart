import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/user_dao.dart';
import '../../core/models/user_model.dart';
import '../../core/services/auth_service.dart';
import '../../core/provider/auth_provider.dart';
import '../../widgets/admin_password_gate.dart';

const Color _bgDark = Color(0xFF0D1117);
const Color _bgCard = Color(0xFF161B22);
const Color _gold = Color(0xFFC9A84C);
const Color _goldLight = Color(0xFFE8C97A);
const Color _border = Color(0xFF30363D);
const Color _textMuted = Color(0xFF7D8590);
const Color _accentGreen = Color(0xFF3FB950);
const Color _accentBlue = Color(0xFF1ABCFE);

class UserManagementPage extends ConsumerStatefulWidget {
  final AppDatabase database;
  final AuthService authService;

  const UserManagementPage({
    super.key,
    required this.database,
    required this.authService,
  });

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  late UserDao _userDao;
  List<AppUser> _users = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _userDao = widget.database.userDao;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final users = _searchQuery.isEmpty
          ? await _userDao.getActiveUsers()
          : await _userDao.searchUsers(_searchQuery);
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (mounted) _showError('فشل تحميل المستخدمين: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgDark,
        appBar: AppBar(
          title: const Text('إدارة المستخدمين'),
          backgroundColor: _bgCard,
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: const TextStyle(
            color: _gold,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: _gold),
              onPressed: _loadUsers,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            _buildStatsCards(),
            Expanded(child: _buildUsersList()),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _addUser(),
          backgroundColor: _gold,
          foregroundColor: _bgDark,
          tooltip: 'إضافة مستخدم',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: (value) {
          _searchQuery = value;
          _loadUsers();
        },
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'البحث عن مستخدم...',
          hintStyle: const TextStyle(color: _textMuted),
          prefixIcon: const Icon(Icons.search, color: _textMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: _textMuted),
                  onPressed: () {
                    _searchQuery = '';
                    _loadUsers();
                  },
                )
              : null,
          filled: true,
          fillColor: _bgCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('إجمالي المستخدمين', '${_users.length}', _accentBlue, Icons.people)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard('المستخدمون النشطون', '${_users.where((u) => u.isActive).length}', _accentGreen, Icons.person)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard('المديرون', '${_users.where((u) => u.role == 'admin').length}', _gold, Icons.admin_panel_settings)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: _textMuted),
            const SizedBox(height: 16),
            const Text('لا يوجد مستخدمون', style: TextStyle(fontSize: 18, color: _textMuted)),
            const SizedBox(height: 8),
            const Text('اضغط على زر الإضافة لإنشاء مستخدم جديد', style: TextStyle(fontSize: 14, color: _textMuted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) => _buildUserCard(_users[index]),
    );
  }

  Widget _buildUserCard(AppUser user) {
    final userRole = UserRole.values.firstWhere(
      (r) => r.name == user.role,
      orElse: () => UserRole.viewer,
    );
    final currentUser = ref.watch(authProvider);
    final isCurrentUserAdmin = currentUser?.role == UserRole.admin;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getRoleColor(userRole).withValues(alpha: 0.2),
                  child: Icon(_getRoleIcon(userRole), color: _getRoleColor(userRole), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('@${user.username}', style: const TextStyle(fontSize: 13, color: _textMuted)),
                    ],
                  ),
                ),
                _buildRoleBadge(userRole),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip(user.email ?? 'لا يوجد بريد', Icons.email, _accentBlue),
                const SizedBox(width: 8),
                _buildInfoChip(user.phone ?? 'لا يوجد هاتف', Icons.phone, _accentGreen),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatusChip(user.isActive),
                const Spacer(),
                if (user.lastLogin != null)
                  Text('آخر دخول: ${_formatDate(user.lastLogin!)}', style: const TextStyle(fontSize: 12, color: _textMuted)),
              ],
            ),
            const SizedBox(height: 12),
            // Permissions
            _buildPermissionsPreview(user, userRole),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isCurrentUserAdmin) ...[
                  TextButton.icon(
                    onPressed: () => _toggleUserStatus(user),
                    icon: Icon(user.isActive ? Icons.block : Icons.check_circle, size: 16),
                    label: Text(user.isActive ? 'تعطيل' : 'تفعيل'),
                    style: TextButton.styleFrom(foregroundColor: user.isActive ? Colors.red : _accentGreen),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _editUser(user),
                    icon: const Icon(Icons.edit, color: _gold),
                    tooltip: 'تعديل',
                  ),
                  if (user.role != 'admin' && user.id != currentUser?.id)
                    IconButton(
                      onPressed: () => _deleteUser(user),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'حذف',
                    ),
                ],
                IconButton(
                  onPressed: () => _showPermissionsDialog(user, userRole),
                  icon: const Icon(Icons.tune, color: _accentBlue),
                  tooltip: 'الصلاحيات',
                ),
                if (isCurrentUserAdmin && user.role != 'admin')
                  IconButton(
                    onPressed: () => _showResetPasswordDialog(user),
                    icon: const Icon(Icons.lock_reset, color: _goldLight),
                    tooltip: 'إعادة تعيين كلمة المرور',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(UserRole role) {
    final color = _getRoleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        PermissionMatrix.getRoleDisplayName(role),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 12, color: color), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool isActive) {
    final color = isActive ? _accentGreen : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isActive ? Icons.check_circle : Icons.block, size: 14, color: color),
          const SizedBox(width: 4),
          Text(isActive ? 'نشط' : 'معطل', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPermissionsPreview(AppUser user, UserRole role) {
    final customPerms = _parseCustomPermissions(user.customPermissions);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الصلاحيات المخصصة:', style: TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: customPerms.entries.take(4).map((e) {
              final color = e.value ? _accentGreen : Colors.red;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_getCustomPermLabel(e.key), style: TextStyle(fontSize: 10, color: color)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _getCustomPermLabel(String key) {
    switch (key) {
      case 'can_delete_invoice': return 'حذف فاتورة';
      case 'can_apply_discount': return 'خصم';
      case 'can_edit_price': return 'تعديل السعر';
      case 'can_view_reports': return 'تقارير';
      case 'can_process_returns': return 'مرتجعات';
      case 'can_add_spoilage': return 'هالك';
      default: return key;
    }
  }

  Map<String, bool> _parseCustomPermissions(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as bool));
    } catch (_) {
      return {};
    }
  }

  String _encodeCustomPermissions(Map<String, bool> perms) {
    return jsonEncode(perms);
  }

  Future<void> _showPermissionsDialog(AppUser user, UserRole role) async {
    final db = widget.database;
    final isAuthed = await showAdminPasswordGate(context, db);
    if (!isAuthed || !mounted) return;

    if (!mounted) return;
    final customPerms = _parseCustomPermissions(user.customPermissions);
    final editable = Map<String, bool>.from(customPerms);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: _bgCard,
            title: Row(
              children: [
                const Icon(Icons.tune, color: _gold),
                const SizedBox(width: 8),
                Text('الصلاحيات المخصصة - ${user.fullName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('صلاحيات إضافية خارج الدور الافتراضي:', style: TextStyle(color: _textMuted, fontSize: 13)),
                    const SizedBox(height: 12),
                    ...editable.keys.map((key) => CheckboxListTile(
                      title: Text(_getCustomPermLabel(key), style: const TextStyle(color: Colors.white, fontSize: 14)),
                      value: editable[key],
                      activeColor: _gold,
                      checkColor: _bgDark,
                      dense: true,
                      onChanged: (v) => setDialogState(() => editable[key] = v ?? false),
                    )),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء', style: TextStyle(color: _textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _bgDark),
                onPressed: () async {
                  try {
                    final encoded = _encodeCustomPermissions(editable);
                    final existing = await _userDao.getUserById(user.id);
                    if (existing != null) {
                      await _userDao.updateUser(existing.copyWith(
                        customPermissions: Value(encoded),
                      ));
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      _loadUsers();
      _showSuccess('تم تحديث الصلاحيات');
    }
  }

  Future<void> _showResetPasswordDialog(AppUser user) async {
    final newPasswordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          title: const Row(children: [
            Icon(Icons.lock_reset, color: _gold),
            SizedBox(width: 8),
            Text('إعادة تعيين كلمة المرور', style: TextStyle(color: Colors.white)),
          ]),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('المستخدم: ${user.fullName}', style: const TextStyle(color: _textMuted)),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                    labelStyle: TextStyle(color: _textMuted),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock, color: _textMuted),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                    labelStyle: TextStyle(color: _textMuted),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline, color: _textMuted),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: _textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _bgDark),
              onPressed: () async {
                if (newPasswordCtrl.text.length < 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('كلمة المرور يجب أن تكون 6 أحرف على الأقل'), backgroundColor: Colors.red));
                  return;
                }
                if (newPasswordCtrl.text != confirmCtrl.text) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('كلمات المرور غير متطابقة'), backgroundColor: Colors.red));
                  return;
                }
                try {
                  await _userDao.changePassword(user.id, newPasswordCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _showSuccess('تم إعادة تعيين كلمة المرور');
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin: return _gold;
      case UserRole.manager: return _accentBlue;
      case UserRole.cashier: return _accentGreen;
      case UserRole.accountant: return Colors.orange;
      case UserRole.viewer: return _textMuted;
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.admin: return Icons.admin_panel_settings;
      case UserRole.manager: return Icons.supervisor_account;
      case UserRole.cashier: return Icons.point_of_sale;
      case UserRole.accountant: return Icons.account_balance;
      case UserRole.viewer: return Icons.visibility;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _addUser() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AddUserDialog(userDao: _userDao),
    );
    if (result == true) _loadUsers();
  }

  void _editUser(AppUser appUser) async {
    final user = _mapAppUserToUser(appUser);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EditUserDialog(userDao: _userDao, user: user),
    );
    if (result == true) _loadUsers();
  }

  void _toggleUserStatus(AppUser user) async {
    try {
      await _userDao.toggleUserStatus(user.id, !user.isActive);
      _loadUsers();
      _showSuccess('تم ${user.isActive ? 'تعطيل' : 'تفعيل'} المستخدم بنجاح');
    } catch (e) {
      _showError('فشل تغيير حالة المستخدم: $e');
    }
  }

  void _deleteUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
          content: Text('هل أنت متأكد من حذف المستخدم "${user.fullName}"؟', style: const TextStyle(color: _textMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء', style: TextStyle(color: _textMuted))),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await _userDao.deleteUser(user.id);
        _loadUsers();
        _showSuccess('تم حذف المستخدم بنجاح');
      } catch (e) {
        _showError('فشل حذف المستخدم: $e');
      }
    }
  }

  User _mapAppUserToUser(AppUser appUser) {
    UserRole role;
    switch (appUser.role.toLowerCase()) {
      case 'admin': role = UserRole.admin; break;
      case 'manager': role = UserRole.manager; break;
      case 'cashier': role = UserRole.cashier; break;
      case 'accountant': role = UserRole.accountant; break;
      default: role = UserRole.viewer;
    }
    return User(
      id: appUser.id,
      username: appUser.username,
      passwordHash: appUser.password,
      fullName: appUser.fullName,
      role: role,
      isActive: appUser.isActive,
      lastLogin: appUser.lastLogin,
      createdAt: appUser.createdAt,
      customPermissions: [],
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: _accentGreen));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }
}

class _AddUserDialog extends StatefulWidget {
  final UserDao userDao;
  const _AddUserDialog({required this.userDao});

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  UserRole _selectedRole = UserRole.viewer;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: _bgCard,
        title: const Text('إضافة مستخدم جديد', style: TextStyle(color: _gold)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(_usernameController, 'اسم المستخدم', Icons.person),
                  const SizedBox(height: 12),
                  _buildTextField(_fullNameController, 'الاسم الكامل', Icons.badge),
                  const SizedBox(height: 12),
                  _buildTextField(_emailController, 'البريد الإلكتروني', Icons.email),
                  const SizedBox(height: 12),
                  _buildTextField(_phoneController, 'رقم الهاتف', Icons.phone),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _selectedRole,
                    dropdownColor: _bgCard,
                    decoration: _inputDecoration('الدور', Icons.admin_panel_settings),
                    items: UserRole.values.map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(PermissionMatrix.getRoleDisplayName(role), style: const TextStyle(color: Colors.white)),
                    )).toList(),
                    onChanged: (value) => setState(() => _selectedRole = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('كلمة المرور', Icons.lock),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'يرجى إدخال كلمة المرور';
                      if (v.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('تأكيد كلمة المرور', Icons.lock_outline),
                    validator: (v) => v != _passwordController.text ? 'كلمتا المرور غير متطابقتين' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _bgDark),
            onPressed: _isLoading ? null : _saveUser,
            child: _isLoading
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _bgDark))
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _textMuted),
      prefixIcon: Icon(icon, color: _textMuted),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: _border)),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _gold)),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label, icon),
    );
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await widget.userDao.createUser(
        _usernameController.text.trim(),
        _passwordController.text,
        _selectedRole.name,
        _fullNameController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ المستخدم: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _EditUserDialog extends StatefulWidget {
  final UserDao userDao;
  final User user;
  const _EditUserDialog({required this.userDao, required this.user});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late UserRole _selectedRole;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.user.fullName);
    _emailController = TextEditingController(text: widget.user.email ?? '');
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _selectedRole = widget.user.role;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: _bgCard,
        title: Text('تعديل المستخدم: ${widget.user.fullName}', style: const TextStyle(color: _gold)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _fullNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      labelStyle: TextStyle(color: _textMuted),
                      prefixIcon: Icon(Icons.badge, color: _textMuted),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _border)),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'يرجى إدخال الاسم الكامل' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      labelStyle: TextStyle(color: _textMuted),
                      prefixIcon: Icon(Icons.email, color: _textMuted),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _border)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      labelStyle: TextStyle(color: _textMuted),
                      prefixIcon: Icon(Icons.phone, color: _textMuted),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _border)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _selectedRole,
                    dropdownColor: _bgCard,
                    decoration: const InputDecoration(
                      labelText: 'الدور',
                      labelStyle: TextStyle(color: _textMuted),
                      prefixIcon: Icon(Icons.admin_panel_settings, color: _textMuted),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _border)),
                    ),
                    items: UserRole.values.map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(PermissionMatrix.getRoleDisplayName(role), style: const TextStyle(color: Colors.white)),
                    )).toList(),
                    onChanged: (value) => setState(() => _selectedRole = value!),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _bgDark),
            onPressed: _isLoading ? null : _saveUser,
            child: _isLoading
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _bgDark))
                : const Text('تعديل'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final existing = await widget.userDao.getUserById(widget.user.id!);
      if (existing == null) throw StateError('User not found');
      final appUser = existing.copyWith(
        role: _selectedRole.name,
        fullName: _fullNameController.text.trim(),
        email: Value(_emailController.text.trim().isEmpty ? null : _emailController.text.trim()),
        phone: Value(_phoneController.text.trim().isEmpty ? null : _phoneController.text.trim()),
      );
      await widget.userDao.updateUser(appUser);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تعديل المستخدم: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
