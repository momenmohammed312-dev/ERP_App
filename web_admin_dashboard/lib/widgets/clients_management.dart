import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/client_model.dart';
import '../models/license_model.dart';
import '../services/data_service.dart';
import '../utils/constants.dart';
import 'package:uuid/uuid.dart';

/// Clients Management Widget - إدارة العملاء
class ClientsManagement extends StatefulWidget {
  const ClientsManagement({super.key});

  @override
  State<ClientsManagement> createState() => _ClientsManagementState();
}

class _ClientsManagementState extends State<ClientsManagement> {
  final DataService _dataService = DataService();
  final TextEditingController _searchController = TextEditingController();
  List<ClientModel> _filteredClients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _dataService.init();
    _filterClients('');
    setState(() => _isLoading = false);
  }

  void _filterClients(String query) {
    setState(() {
      _filteredClients = _dataService.searchClients(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: AppColors.backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 24),
              // Stats Cards
              _buildStatsCards(),
              const SizedBox(height: 24),
              // Search and Add Button
              _buildSearchAndActions(),
              const SizedBox(height: 16),
              // Clients Table
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildClientsTable(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.clients,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'إدارة عملاء البرنامج والتراخيص',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _showAddClientDialog(),
          icon: const Icon(Icons.add),
          label: const Text(AppStrings.addClient),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.successColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final stats = _dataService.getClientsCountByPackage();

    final cards = <Widget>[
      _buildStatCard(
        'إجمالي العملاء',
        _dataService.getClients().length.toString(),
        Icons.people,
        AppColors.accentColor,
      ),
      _buildStatCard(
        'أساسي',
        (stats['basic'] ?? 0).toString(),
        Icons.star_border,
        AppColors.basicColor,
      ),
      _buildStatCard(
        'قياسي',
        (stats['standard'] ?? 0).toString(),
        Icons.star_half,
        AppColors.standardColor,
      ),
      _buildStatCard(
        'احترافي',
        (stats['professional'] ?? 0).toString(),
        Icons.star,
        AppColors.professionalColor,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        final width = constraints.maxWidth;
        final crossAxisCount = width >= 600 ? 2 : 1;
        const spacing = 16.0;
        final cardWidth = crossAxisCount == 1
            ? width
            : (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndActions() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: _filterClients,
            decoration: InputDecoration(
              hintText: AppStrings.searchClients,
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ),
      ],
    );
  }

  Widget _buildClientsTable() {
    if (_filteredClients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              AppStrings.noClients,
              style: TextStyle(fontSize: 18, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showAddClientDialog(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة عميل جديد'),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                  AppColors.primaryColor.withValues(alpha: 0.05)),
              columns: const [
                DataColumn(
                    label: Text('الاسم',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الهاتف',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الباقة',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الحالة',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('تاريخ التسجيل',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('إجراءات',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _filteredClients
                  .map((client) => _buildClientRow(client))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildClientRow(ClientModel client) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _getPackageColor(client.packageType),
                child: Text(
                  client.name.isNotEmpty ? client.name[0] : '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(client.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (client.email.isNotEmpty)
                    Text(client.email,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ],
          ),
        ),
        DataCell(Text(client.phone)),
        DataCell(_buildPackageBadge(client.packageType)),
        DataCell(_buildStatusBadge(client.isActive)),
        DataCell(Text(_formatDate(client.createdAt))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.key, size: 20),
                color: AppColors.successColor,
                tooltip: 'توليد ترخيص',
                onPressed: () => _showGenerateLicenseDialog(client),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                color: AppColors.accentColor,
                tooltip: 'تعديل',
                onPressed: () => _showEditClientDialog(client),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                color: AppColors.errorColor,
                tooltip: 'حذف',
                onPressed: () => _confirmDelete(client),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPackageBadge(String packageType) {
    String label;
    Color color;
    switch (packageType) {
      case 'basic':
        label = 'أساسي';
        color = AppColors.basicColor;
        break;
      case 'standard':
        label = 'قياسي';
        color = AppColors.standardColor;
        break;
      case 'professional':
        label = 'احترافي';
        color = AppColors.professionalColor;
        break;
      default:
        label = packageType;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.successColor : AppColors.errorColor)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? AppColors.successColor : AppColors.errorColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isActive ? 'نشط' : 'غير نشط',
            style: TextStyle(
              color: isActive ? AppColors.successColor : AppColors.errorColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Color _getPackageColor(String packageType) {
    switch (packageType) {
      case 'basic':
        return AppColors.basicColor;
      case 'standard':
        return AppColors.standardColor;
      case 'professional':
        return AppColors.professionalColor;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showAddClientDialog() {
    _showClientDialog(null);
  }

  void _showEditClientDialog(ClientModel client) {
    _showClientDialog(client);
  }

  void _showClientDialog(ClientModel? client) {
    final isEditing = client != null;
    final nameController = TextEditingController(text: client?.name ?? '');
    final phoneController = TextEditingController(text: client?.phone ?? '');
    final emailController = TextEditingController(text: client?.email ?? '');
    final addressController =
        TextEditingController(text: client?.address ?? '');
    final notesController = TextEditingController(text: client?.notes ?? '');
    String selectedPackage = client?.packageType ?? 'basic';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  isEditing ? Icons.edit : Icons.person_add,
                  color: AppColors.accentColor,
                ),
                const SizedBox(width: 12),
                Text(isEditing ? AppStrings.editClient : AppStrings.addClient),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField(
                        nameController, AppStrings.clientName, Icons.person),
                    const SizedBox(height: 16),
                    _buildTextField(
                        phoneController, AppStrings.clientPhone, Icons.phone),
                    const SizedBox(height: 16),
                    _buildTextField(
                        emailController, AppStrings.clientEmail, Icons.email),
                    const SizedBox(height: 16),
                    _buildTextField(addressController, AppStrings.clientAddress,
                        Icons.location_on),
                    const SizedBox(height: 16),
                    // Package Selection
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              AppStrings.clientPackage,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          ...['basic', 'standard', 'professional'].map((pkg) {
                            // ignore: deprecated_member_use
                            return RadioListTile<String>(
                              value: pkg,
                              // ignore: deprecated_member_use
                              groupValue: selectedPackage,
                              // ignore: deprecated_member_use
                              onChanged: (value) {
                                setDialogState(() => selectedPackage = value!);
                              },
                              title: Text(_getPackageName(pkg)),
                              subtitle: Text(_getPackageDescription(pkg)),
                              secondary: Text(
                                '${PackagePricing.basePrices[pkg]?.toInt() ?? 0} ج',
                                style: TextStyle(
                                  color: _getPackageColor(pkg),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              activeColor: _getPackageColor(pkg),
                              dense: true,
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                        notesController, AppStrings.clientNotes, Icons.note,
                        maxLines: 3),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(AppStrings.cancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty ||
                      phoneController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الاسم والهاتف مطلوبان')),
                    );
                    return;
                  }

                  final newClient = ClientModel(
                    id: client?.id ?? const Uuid().v4(),
                    name: nameController.text,
                    phone: phoneController.text,
                    email: emailController.text,
                    address: addressController.text,
                    packageType: selectedPackage,
                    createdAt: client?.createdAt ?? DateTime.now(),
                    notes: notesController.text.isEmpty
                        ? null
                        : notesController.text,
                    currentLicenseId: client?.currentLicenseId,
                    totalPaid: client?.totalPaid ?? 0,
                    isActive: client?.isActive ?? true,
                  );

                  if (isEditing) {
                    await _dataService.updateClient(newClient);
                  } else {
                    await _dataService.addClient(newClient);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEditing
                            ? AppStrings.clientUpdated
                            : AppStrings.clientAdded),
                        backgroundColor: AppColors.successColor,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text(AppStrings.save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.accentColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  String _getPackageName(String packageType) {
    switch (packageType) {
      case 'basic':
        return AppStrings.basicPackage;
      case 'standard':
        return AppStrings.standardPackage;
      case 'professional':
        return AppStrings.professionalPackage;
      default:
        return packageType;
    }
  }

  String _getPackageDescription(String packageType) {
    switch (packageType) {
      case 'basic':
        return AppStrings.basicDescription;
      case 'standard':
        return AppStrings.standardDescription;
      case 'professional':
        return AppStrings.professionalDescription;
      default:
        return '';
    }
  }

  void _confirmDelete(ClientModel client) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: AppColors.errorColor),
              const SizedBox(width: 12),
              const Text('تأكيد الحذف'),
            ],
          ),
          content: Text('هل أنت متأكد من حذف العميل "${client.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                await _dataService.deleteClient(client.id);
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppStrings.clientDeleted),
                      backgroundColor: AppColors.errorColor,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorColor,
                foregroundColor: Colors.white,
              ),
              child: const Text(AppStrings.delete),
            ),
          ],
        ),
      ),
    );
  }

  void _showGenerateLicenseDialog(ClientModel client) {
    SubscriptionDuration selectedDuration = SubscriptionDuration.monthly;
    String selectedPackage =
        client.packageType.isNotEmpty ? client.packageType : 'basic';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.key, color: AppColors.successColor),
                const SizedBox(width: 12),
                const Text(AppStrings.generateLicense),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Client Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  _getPackageColor(selectedPackage),
                              child: Text(
                                client.name[0],
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(client.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  _getPackageName(selectedPackage),
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('نوع العميل / الباقة:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children:
                              ['basic', 'standard', 'professional'].map((pkg) {
                            final price = LicenseKeyGenerator.getPrice(
                              pkg,
                              selectedDuration,
                            );
                            // ignore: deprecated_member_use
                            return RadioListTile<String>(
                              value: pkg,
                              // ignore: deprecated_member_use
                              groupValue: selectedPackage,
                              // ignore: deprecated_member_use
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedPackage = value;
                                });
                              },
                              title: Text(_getPackageName(pkg)),
                              subtitle: Text(
                                _getPackageDescription(pkg),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              secondary: SizedBox(
                                width: 70,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    price == 0 ? 'مجاني' : '${price.toInt()} ج',
                                    style: TextStyle(
                                      color: _getPackageColor(pkg),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              activeColor: _getPackageColor(pkg),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Text('مدة الاشتراك:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      // Duration Selection
                      ...SubscriptionDuration.values.map((duration) {
                        final price = LicenseKeyGenerator.getPrice(
                            selectedPackage, duration);
                        // ignore: deprecated_member_use
                        return RadioListTile<SubscriptionDuration>(
                          value: duration,
                          // ignore: deprecated_member_use
                          groupValue: selectedDuration,
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            setDialogState(() {
                              selectedDuration = value!;
                            });
                          },
                          title: Text(_getDurationName(duration)),
                          subtitle: Text(
                            _getDurationDescription(duration),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: SizedBox(
                            width: 70,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                price == 0 ? 'مجاني' : '${price.toInt()} ج',
                                style: TextStyle(
                                  color: price == 0
                                      ? AppColors.successColor
                                      : AppColors.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          activeColor: AppColors.successColor,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(AppStrings.cancel),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (selectedPackage.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى اختيار نوع الباقة')),
                    );
                    return;
                  }

                  final license = await _dataService.generateLicense(
                    clientId: client.id,
                    clientName: client.name,
                    packageType: selectedPackage,
                    duration: selectedDuration,
                  );

                  if (client.packageType != selectedPackage) {
                    await _dataService.updateClient(
                      client.copyWith(packageType: selectedPackage),
                    );
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    _showLicenseKeyDialog(license);
                    _loadData();
                  }
                },
                icon: const Icon(Icons.key),
                label: const Text('توليد المفتاح'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLicenseKeyDialog(LicenseRecord license) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.successColor),
              const SizedBox(width: 12),
              const Text('تم توليد المفتاح!'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('مفتاح الترخيص:'),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: SelectableText(
                      license.licenseKey,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildInfoChip('الباقة', license.packageDisplayName),
                      _buildInfoChip('المدة', license.durationDisplayName),
                      _buildInfoChip('الحالة', license.statusDisplayName),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ينتهي في: ${_formatDate(license.expiresAt)}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: license.licenseKey));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(AppStrings.copied),
                    backgroundColor: AppColors.successColor,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text(AppStrings.copyLicenseKey),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }

  String _getDurationName(SubscriptionDuration duration) {
    switch (duration) {
      case SubscriptionDuration.trial:
        return 'تجريبي';
      case SubscriptionDuration.monthly:
        return 'شهري';
      case SubscriptionDuration.yearly:
        return 'سنوي';
      case SubscriptionDuration.lifetime:
        return 'مدى الحياة';
    }
  }

  String _getDurationDescription(SubscriptionDuration duration) {
    switch (duration) {
      case SubscriptionDuration.trial:
        return '7 أيام مجاناً';
      case SubscriptionDuration.monthly:
        return 'شهر واحد';
      case SubscriptionDuration.yearly:
        return 'سنة كاملة (شهرين مجاناً)';
      case SubscriptionDuration.lifetime:
        return 'ترخيص دائم';
    }
  }

  Widget _buildInfoChip(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(
        '$title: $value',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
