export const ERP_MODULES = [
  // الوحدات الأساسية
  {
    id: 'pos',
    name: 'شاشة الكاشير ونقطة البيع (POS)',
    description: 'واجهة البيع السريع وتوليد الفواتير والباركود',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },
  {
    id: 'cash_sales',
    name: 'المبيعات النقدية',
    description: 'تسجيل المقبوضات النقدية والدرج المالي',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },
  {
    id: 'credit_sales',
    name: 'المبيعات الآجلة (حسابات العملاء)',
    description: 'تسجيل الديون والآجل ومتابعة أرصدة الزبائن',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },
  {
    id: 'inventory',
    name: 'المخزون وإدارة الأصناف',
    description: 'بطاقات الأصناف والأسعار وتنبيهات النواقص',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },
  {
    id: 'customers',
    name: 'دليل العملاء',
    description: 'سجل العملاء، أرقام الهواتف وكشوفات الحساب',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },
  {
    id: 'suppliers',
    name: 'الموردين وفواتير الشراء',
    description: 'إدارة الموردين، فواتير الشراء وحسابات الدائنين',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },
  {
    id: 'reports',
    name: 'التقارير المالية وحركة الخزينة',
    description: 'تقارير الأرباح والمبيعات والمصروفات اليومية',
    category: 'core',
    defaultEnabled: true,
    badge: 'أساسي'
  },

  // الوحدات الإضافية / المتقدمة
  {
    id: 'manufacturing',
    name: 'التصنيع والإنتاج (Manufacturing)',
    description: 'خلط المواد الخام، أوامر الشغل، وتكلفة المنتج التام',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  },
  {
    id: 'staff_management',
    name: 'الموظفين والمرتبات والورديات',
    description: 'سجل الموظفين، الرواتب، السلفيات، والغياب والحضور',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  },
  {
    id: 'custody',
    name: 'العهد المالية والمصروفات النثرية',
    description: 'إسناد العهد للعاملين وتصفيتها بالفواتير',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  },
  {
    id: 'damaged_goods',
    name: 'الهوالك والتوالف وإهلاك المخزون',
    description: 'تسجيل البضاعة التالفة وحساب الخسائر في التكلفة',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  },
  {
    id: 'multi_branch',
    name: 'الفروع المتعددة والمزامنة',
    description: 'إدارة أكثر من فرع والتحويل بين المستودعات',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  },
  {
    id: 'barcode_print',
    name: 'طباعة وتصميم الباركود',
    description: 'طباعة ملصقات الباركود على طابعات Thermal/Xprinter',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  },
  {
    id: 'installments',
    name: 'الأقساط الشهرية وجداول السداد',
    description: 'تقسيط المبيعات، تواريخ الاستحقاق وإشعارات السداد',
    category: 'addon',
    defaultEnabled: false,
    badge: 'إضافي'
  }
];

export const LICENSE_PLANS = [
  { id: 'trial', name: 'تجريبي (مجاني)', days: 14, defaultModules: 'core' },
  { id: 'monthly', name: 'اشتراك شهري', days: 30, defaultModules: 'core' },
  { id: 'yearly', name: 'اشتراك سنوي', days: 365, defaultModules: 'all' },
  { id: 'lifetime', name: 'مدى الحياة (Lifetime)', days: 3650, defaultModules: 'all' },
];
