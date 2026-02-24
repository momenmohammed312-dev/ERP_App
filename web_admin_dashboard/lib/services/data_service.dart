import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/client_model.dart';
import '../models/license_model.dart';

/// Data Service - يدير البيانات عبر Firebase Firestore
class DataService {
  FirebaseFirestore? _firestore;
  static const String _clientsCollection = 'clients';
  static const String _licensesCollection = 'licenses';

  // Singleton
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // Local cache
  List<ClientModel> _clients = [];
  List<LicenseRecord> _licenses = [];
  bool _isInit = false;
  bool _useLocal = false;

  bool _hasPlaceholderFirebaseConfig() {
    try {
      final projectId = FirebaseFirestore.instance.app.options.projectId;
      return projectId.isEmpty || projectId.startsWith('PASTE_');
    } catch (_) {
      return true;
    }
  }

  /// Initialize and load data from Firestore
  Future<void> init() async {
    if (_isInit) return;

    if (_hasPlaceholderFirebaseConfig()) {
      _useLocal = true;
      _isInit = true;
      return;
    }

    try {
      _firestore = FirebaseFirestore.instance;
    } catch (_) {
      _useLocal = true;
      _isInit = true;
      return;
    }

    // Listen to changes (Real-time updates)
    try {
      _firestore!.collection(_clientsCollection).snapshots().listen((snapshot) {
        _clients = snapshot.docs
            .map((doc) => ClientModel.fromJson({...doc.data(), 'id': doc.id}))
            .toList();
      }, onError: (_) {
        _useLocal = true;
      });

      _firestore!.collection(_licensesCollection).snapshots().listen(
          (snapshot) {
        _licenses = snapshot.docs
            .map((doc) => LicenseRecord.fromJson({...doc.data(), 'id': doc.id}))
            .toList();
      }, onError: (_) {
        _useLocal = true;
      });
    } catch (_) {
      _useLocal = true;
    }

    _isInit = true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CLIENT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all clients
  List<ClientModel> getClients() => _clients;

  /// Get client by ID
  ClientModel? getClientById(String id) {
    try {
      return _clients.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Add new client
  Future<ClientModel> addClient(ClientModel client) async {
    if (_useLocal) {
      final newClient = client.copyWith(
        id: client.id.isNotEmpty
            ? client.id
            : DateTime.now().microsecondsSinceEpoch.toString(),
      );
      _clients = [..._clients, newClient];
      return newClient;
    }

    final docRef =
        await _firestore!.collection(_clientsCollection).add(client.toJson());
    final newClient = client.copyWith(id: docRef.id);
    return newClient;
  }

  /// Update client
  Future<void> updateClient(ClientModel client) async {
    if (_useLocal) {
      _clients = _clients.map((c) => c.id == client.id ? client : c).toList();
      return;
    }

    await _firestore!
        .collection(_clientsCollection)
        .doc(client.id)
        .set(client.toJson(), SetOptions(merge: true));
  }

  /// Delete client
  Future<void> deleteClient(String id) async {
    if (_useLocal) {
      _clients = _clients.where((c) => c.id != id).toList();
      return;
    }

    await _firestore!.collection(_clientsCollection).doc(id).delete();
  }

  /// Search clients (uses local cache for performance)
  List<ClientModel> searchClients(String query) {
    if (query.isEmpty) return _clients;
    final lowerQuery = query.toLowerCase();
    return _clients
        .where((c) =>
            c.name.toLowerCase().contains(lowerQuery) ||
            c.phone.contains(query))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LICENSE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all licenses
  List<LicenseRecord> getLicenses() => _licenses;

  /// Get license by ID
  LicenseRecord? getLicenseById(String id) {
    try {
      return _licenses.firstWhere((l) => l.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get license by key
  LicenseRecord? getLicenseByKey(String key) {
    try {
      return _licenses.firstWhere((l) => l.licenseKey == key);
    } catch (e) {
      return null;
    }
  }

  /// Get licenses for a client
  List<LicenseRecord> getLicensesForClient(String clientId) {
    return _licenses.where((l) => l.clientId == clientId).toList();
  }

  /// Generate new license for client
  Future<LicenseRecord> generateLicense({
    required String clientId,
    required String clientName,
    required String packageType,
    required SubscriptionDuration duration,
    String? notes,
  }) async {
    final expiresAt = LicenseKeyGenerator.getExpiryDate(duration);
    final licenseKey = LicenseKeyGenerator.generateKey(
      packageType: packageType,
      expiresAt: expiresAt,
    );
    final price = LicenseKeyGenerator.getPrice(packageType, duration);

    final Map<String, dynamic> licenseData = {
      'licenseKey': licenseKey,
      'clientId': clientId,
      'clientName': clientName,
      'packageType': packageType,
      'duration': duration.index,
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'status': (duration == SubscriptionDuration.trial
              ? LicenseStatus.trial
              : LicenseStatus.active)
          .index,
      'price': price,
      'notes': notes,
    };

    if (_useLocal) {
      final localId = DateTime.now().microsecondsSinceEpoch.toString();
      final license = LicenseRecord.fromJson({...licenseData, 'id': localId});
      _licenses = [..._licenses, license];

      final client = getClientById(clientId);
      if (client != null) {
        await updateClient(client.copyWith(
          currentLicenseId: license.id,
          totalPaid: client.totalPaid + price,
        ));
      }

      return license;
    }

    final docRef =
        await _firestore!.collection(_licensesCollection).add(licenseData);

    final license = LicenseRecord.fromJson({...licenseData, 'id': docRef.id});

    // Update client's current license and total paid
    final client = getClientById(clientId);
    if (client != null) {
      await updateClient(client.copyWith(
        currentLicenseId: license.id,
        totalPaid: client.totalPaid + price,
      ));
    }

    return license;
  }

  /// Generate new license for client with a pre-generated key
  Future<LicenseRecord> generateLicenseWithKey({
    required String clientId,
    required String clientName,
    required String packageType,
    required String licenseKey,
    required DateTime expiresAt,
    required double price,
    String? hardwareId,
    String? notes,
  }) async {
    final Map<String, dynamic> licenseData = {
      'licenseKey': licenseKey,
      'clientId': clientId,
      'clientName': clientName,
      'packageType': packageType,
      'duration': SubscriptionDuration.monthly.index, // Default for manual
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'activatedAt':
          hardwareId != null ? Timestamp.fromDate(DateTime.now()) : null,
      'hardwareId': hardwareId,
      'status': LicenseStatus.active.index,
      'price': price,
      'notes': notes,
    };

    if (_useLocal) {
      final localId = DateTime.now().microsecondsSinceEpoch.toString();
      final license = LicenseRecord.fromJson({...licenseData, 'id': localId});
      _licenses = [..._licenses, license];

      final client = getClientById(clientId);
      if (client != null) {
        await updateClient(client.copyWith(
          currentLicenseId: license.id,
          totalPaid: client.totalPaid + price,
        ));
      }

      return license;
    }

    final docRef =
        await _firestore!.collection(_licensesCollection).add(licenseData);
    final license = LicenseRecord.fromJson({...licenseData, 'id': docRef.id});

    final client = getClientById(clientId);
    if (client != null) {
      await updateClient(client.copyWith(
        currentLicenseId: license.id,
        totalPaid: client.totalPaid + price,
      ));
    }

    return license;
  }

  /// Activate license (from Web Dashboard perspective - usually done by POS)
  Future<void> updateLicenseStatus(String id, LicenseStatus status) async {
    if (_useLocal) {
      _licenses = _licenses
          .map((l) => l.id == id ? l.copyWith(status: status) : l)
          .toList();
      return;
    }

    await _firestore!.collection(_licensesCollection).doc(id).update({
      'status': status.index,
    });
  }

  /// Revoke license
  Future<void> revokeLicense(String id) async {
    await updateLicenseStatus(id, LicenseStatus.revoked);
  }

  /// Renew license
  Future<LicenseRecord?> renewLicense(
      String id, SubscriptionDuration duration) async {
    final license = getLicenseById(id);
    if (license == null) return null;

    final newExpiresAt = LicenseKeyGenerator.getExpiryDate(duration);
    final price = LicenseKeyGenerator.getPrice(license.packageType, duration);

    if (_useLocal) {
      _licenses = _licenses.map((l) {
        if (l.id != id) return l;
        return l.copyWith(
          expiresAt: newExpiresAt,
          status: LicenseStatus.active,
        );
      }).toList();
    } else {
      await _firestore!.collection(_licensesCollection).doc(id).update({
        'expiresAt': Timestamp.fromDate(newExpiresAt),
        'status': LicenseStatus.active.index,
      });
    }

    // Update client's total paid
    final client = getClientById(license.clientId);
    if (client != null) {
      await updateClient(client.copyWith(
        totalPaid: client.totalPaid + price,
      ));
    }

    return getLicenseById(id);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════

  Map<String, int> getClientsCountByPackage() {
    return {
      'basic': _clients.where((c) => c.packageType == 'basic').length,
      'standard': _clients.where((c) => c.packageType == 'standard').length,
      'professional':
          _clients.where((c) => c.packageType == 'professional').length,
    };
  }

  double get totalRevenue => _licenses.fold(0.0, (acc, l) => acc + l.price);

  Map<String, double> getMonthlyRevenue() {
    final now = DateTime.now();
    final Map<String, double> monthlyRevenue = {};

    for (int i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey =
          '${month.year}-${month.month.toString().padLeft(2, '0')}';
      monthlyRevenue[monthKey] = 0.0;
    }

    for (final license in _licenses) {
      final monthKey =
          '${license.createdAt.year}-${license.createdAt.month.toString().padLeft(2, '0')}';
      if (monthlyRevenue.containsKey(monthKey)) {
        monthlyRevenue[monthKey] =
            (monthlyRevenue[monthKey] ?? 0) + license.price;
      }
    }
    return monthlyRevenue;
  }

  List<LicenseRecord> getExpiringSoonLicenses() => _licenses
      .where((l) => l.status == LicenseStatus.active && l.isExpiringSoon)
      .toList();

  int get activeLicensesCount => _licenses
      .where((l) => l.status == LicenseStatus.active && !l.isExpired)
      .length;

  /// Get expired licenses
  List<LicenseRecord> getExpiredLicenses() => _licenses
      .where((l) => l.status == LicenseStatus.expired || l.isExpired)
      .toList();

  /// Get trial licenses count
  int get trialLicensesCount =>
      _licenses.where((l) => l.status == LicenseStatus.trial).length;
}
