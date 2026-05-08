import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/user_dao.dart';
import '../../core/models/user_model.dart';
import '../../core/services/auth_service.dart';
import '../../core/provider/auth_provider.dart';

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
    setState(() {
      _isLoading = true;
    });

    try {
      final users = _searchQuery.isEmpty
          ? await _userDao.getActiveUsers()
          : await _userDao.searchUsers(_searchQuery);

      if (!mounted) return;
      setState(() {
        _users = users;
      });
    } catch (e) {
      if (mounted) _showError('فشل تحميل المستخدمين: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  User _mapAppUserToUser(AppUser appUser) {
    UserRole role;
    switch (appUser.role.toLowerCase()) {
      case 'admin':
        role = UserRole.admin;
        break;
      case 'manager':
        role = UserRole.manager;
        break;
      case 'cashier':
        role = UserRole.cashier;
        break;
      case 'accountant':
        role = UserRole.accountant;
        break;
      case 'viewer':
        role = UserRole.viewer;
        break;
      default:
        role = UserRole.viewer;
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المستخدمين'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
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
          onPressed: _addUser,
          backgroundColor: Colors.green,
          tooltip: 'إضافة مستخدم',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        onChanged: (value) {
          _searchQuery = value;
          _loadUsers();
        },
        decoration: InputDecoration(
          hintText: 'البحث عن مستخدم...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchQuery = '';
                    _loadUsers();
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'إجمالي المستخدمين',
              '${_users.length}',
              Colors.blue,
              Icons.people,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'المستخدمون النشطون',
              '${_users.where((u) => u.isActive).length}',
              Colors.green,
              Icons.person,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'المديرون',
              '${_users.where((u) => u.role == UserRole.admin.name).length}',
              Colors.purple,
              Icons.admin_panel_settings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا يوجد مستخدمون',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على زر الإضافة لإنشاء مستخدم جديد',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(AppUser user) {
    final UserRole role = UserRole.values.firstWhere(
      (r) => r.name == user.role,
      orElse: () => UserRole.viewer,
    );

    final currentUser = ref.watch(authProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getRoleColor(role),
                  child: Icon(
                    _getRoleIcon(role),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '@${user.username}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _buildRoleChip(role),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip('لا يوجد بريد', Icons.email, Colors.blue),
                const SizedBox(width: 8),
                _buildInfoChip('لا يوجد هاتف', Icons.phone, Colors.green),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatusChip(user.isActive, false),
                const Spacer(),
                if (user.lastLogin != null)
                  Text(
                    'آخر دخول: ${_formatDate(user.lastLogin!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _toggleUserStatus(user),
                  icon: Icon(
                    user.isActive ? Icons.block : Icons.check_circle,
                    size: 16,
                  ),
                  label: Text(user.isActive ? 'تعطيل' : 'تفعيل'),
                  style: TextButton.styleFrom(
                    foregroundColor: user.isActive ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _editUser(user),
                  icon: const Icon(Icons.edit),
                  tooltip: 'تعديل',
                ),
                if (user.role != 'admin' && user.id != currentUser?.id)
                  IconButton(
                    onPressed: () => _deleteUser(user),
                    icon: const Icon(Icons.delete),
                    tooltip: 'حذف',
                    color: Colors.red,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(UserRole role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getRoleColor(role),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        PermissionMatrix.getRoleDisplayName(role),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
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
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool isActive, bool isLocked) {
    Color color;
    String text;
    IconData icon;

    if (isLocked) {
      color = Colors.red;
      text = 'مقفل';
      icon = Icons.lock;
    } else if (isActive) {
      color = Colors.green;
      text = 'نشط';
      icon = Icons.check_circle;
    } else {
      color = Colors.grey;
      text = 'معطل';
      icon = Icons.block;
    }

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
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.purple;
      case UserRole.manager:
        return Colors.blue;
      case UserRole.cashier:
        return Colors.green;
      case UserRole.accountant:
        return Colors.orange;
      case UserRole.viewer:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Icons.admin_panel_settings;
      case UserRole.manager:
        return Icons.supervisor_account;
      case UserRole.cashier:
        return Icons.point_of_sale;
      case UserRole.accountant:
        return Icons.account_balance;
      case UserRole.viewer:
        return Icons.visibility;
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

    if (result == true) {
      _loadUsers();
    }
  }

  void _editUser(AppUser appUser) async {
    final user = _mapAppUserToUser(appUser);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EditUserDialog(userDao: _userDao, user: user),
    );

    if (result == true) {
      _loadUsers();
    }
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
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          'هل أنت متأكد من حذف المستخدم "${user.fullName}"؟\nهذا الإجراء لا يمكن التراجع عنه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
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

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
        title: const Text('إضافة مستخدم جديد'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى إدخال اسم المستخدم';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      prefixIcon: Icon(Icons.badge),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى إدخال الاسم الكامل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'الدور',
                      prefixIcon: Icon(Icons.admin_panel_settings),
                    ),
                    items: UserRole.values.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(PermissionMatrix.getRoleDisplayName(role)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى إدخال كلمة المرور';
                      }
                      if (value.length < 6) {
                        return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'كلمتا المرور غير متطابقتين';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveUser,
            child: _isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.userDao.createUser(
        _usernameController.text.trim(),
        _passwordController.text,
        _selectedRole.name,
        _fullNameController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حفظ المستخدم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        title: Text('تعديل المستخدم: ${widget.user.fullName}'),
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
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      prefixIcon: Icon(Icons.badge),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى إدخال الاسم الكامل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'الدور',
                      prefixIcon: Icon(Icons.admin_panel_settings),
                    ),
                    items: UserRole.values.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(PermissionMatrix.getRoleDisplayName(role)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveUser,
            child: _isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('تعديل'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final appUser = AppUser(
        id: widget.user.id!,
        username: widget.user.username,
        password: widget.user.passwordHash,
        role: _selectedRole.name,
        fullName: _fullNameController.text.trim(),
        isActive: widget.user.isActive,
        failedAttempts: widget.user.failedAttempts,
        lastLogin: widget.user.lastLogin,
        createdAt: widget.user.createdAt,
      );

      await widget.userDao.updateUser(appUser);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تعديل المستخدم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
