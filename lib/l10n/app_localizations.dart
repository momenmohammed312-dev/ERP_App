import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @brand_name.
  ///
  /// In en, this message translates to:
  /// **'POS System'**
  String get brand_name;

  /// No description provided for @brand_name_subtitle.
  ///
  /// In en, this message translates to:
  /// **'(NextComm)'**
  String get brand_name_subtitle;

  /// No description provided for @search_product.
  ///
  /// In en, this message translates to:
  /// **'Search Product'**
  String get search_product;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @invoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoice;

  /// No description provided for @sign_up.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get sign_up;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @enter_valid_phone_number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get enter_valid_phone_number;

  /// No description provided for @product_list.
  ///
  /// In en, this message translates to:
  /// **'Product List'**
  String get product_list;

  /// No description provided for @add_product.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get add_product;

  /// No description provided for @save_product.
  ///
  /// In en, this message translates to:
  /// **'Save Product'**
  String get save_product;

  /// No description provided for @product_name.
  ///
  /// In en, this message translates to:
  /// **'Product Name'**
  String get product_name;

  /// No description provided for @enter_product_name.
  ///
  /// In en, this message translates to:
  /// **'Enter product name'**
  String get enter_product_name;

  /// No description provided for @enter_valid_product_name.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid product name'**
  String get enter_valid_product_name;

  /// No description provided for @delete_confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete Confirmation'**
  String get delete_confirmation;

  /// No description provided for @are_you_sure_you_want_to_delete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete?'**
  String get are_you_sure_you_want_to_delete;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @remove_product.
  ///
  /// In en, this message translates to:
  /// **'Remove Product'**
  String get remove_product;

  /// No description provided for @please_fill_the_form.
  ///
  /// In en, this message translates to:
  /// **'Please fill the form'**
  String get please_fill_the_form;

  /// No description provided for @export_to_pdf.
  ///
  /// In en, this message translates to:
  /// **'Export as PDF'**
  String get export_to_pdf;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @select_products.
  ///
  /// In en, this message translates to:
  /// **'Select Products'**
  String get select_products;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @total_customer.
  ///
  /// In en, this message translates to:
  /// **'Total Customers'**
  String get total_customer;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @enter_valid_quantity.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid quantity'**
  String get enter_valid_quantity;

  /// No description provided for @enter_valid_price.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid price'**
  String get enter_valid_price;

  /// No description provided for @customer_name.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get customer_name;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @add_customer.
  ///
  /// In en, this message translates to:
  /// **'Add Customer'**
  String get add_customer;

  /// No description provided for @save_customer.
  ///
  /// In en, this message translates to:
  /// **'Save Customer'**
  String get save_customer;

  /// No description provided for @enter_valid_customer_name.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid customer name'**
  String get enter_valid_customer_name;

  /// No description provided for @enter_valid_name.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid name'**
  String get enter_valid_name;

  /// No description provided for @new_invoice.
  ///
  /// In en, this message translates to:
  /// **'New Invoice'**
  String get new_invoice;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get credit;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @tax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tax;

  /// No description provided for @net_total.
  ///
  /// In en, this message translates to:
  /// **'Net Total'**
  String get net_total;

  /// No description provided for @select_customer.
  ///
  /// In en, this message translates to:
  /// **'Select Customer'**
  String get select_customer;

  /// No description provided for @add_to_invoice.
  ///
  /// In en, this message translates to:
  /// **'Add to Invoice'**
  String get add_to_invoice;

  /// No description provided for @remove_from_invoice.
  ///
  /// In en, this message translates to:
  /// **'Remove from Invoice'**
  String get remove_from_invoice;

  /// No description provided for @proceed_to_payment.
  ///
  /// In en, this message translates to:
  /// **'Proceed to Payment'**
  String get proceed_to_payment;

  /// No description provided for @payment_method.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get payment_method;

  /// No description provided for @payment_successful.
  ///
  /// In en, this message translates to:
  /// **'Payment Successful'**
  String get payment_successful;

  /// No description provided for @invoice_created.
  ///
  /// In en, this message translates to:
  /// **'Invoice Created'**
  String get invoice_created;

  /// No description provided for @no_products_available.
  ///
  /// In en, this message translates to:
  /// **'No products available'**
  String get no_products_available;

  /// No description provided for @no_customers_available.
  ///
  /// In en, this message translates to:
  /// **'No customers available'**
  String get no_customers_available;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @sales_report.
  ///
  /// In en, this message translates to:
  /// **'Sales Report'**
  String get sales_report;

  /// No description provided for @expenses_report.
  ///
  /// In en, this message translates to:
  /// **'Expenses Report'**
  String get expenses_report;

  /// No description provided for @inventory_report.
  ///
  /// In en, this message translates to:
  /// **'Inventory Report'**
  String get inventory_report;

  /// No description provided for @date_range.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get date_range;

  /// No description provided for @from_date.
  ///
  /// In en, this message translates to:
  /// **'From Date'**
  String get from_date;

  /// No description provided for @to_date.
  ///
  /// In en, this message translates to:
  /// **'To Date'**
  String get to_date;

  /// No description provided for @generate_report.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get generate_report;

  /// No description provided for @export_report.
  ///
  /// In en, this message translates to:
  /// **'Export Report'**
  String get export_report;

  /// No description provided for @cash_box.
  ///
  /// In en, this message translates to:
  /// **'Cash Box'**
  String get cash_box;

  /// No description provided for @recent_transactions.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get recent_transactions;

  /// No description provided for @credit_management.
  ///
  /// In en, this message translates to:
  /// **'Credit Management'**
  String get credit_management;

  /// No description provided for @suppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliers;

  /// No description provided for @customer_transactions.
  ///
  /// In en, this message translates to:
  /// **'Customer Transactions'**
  String get customer_transactions;

  /// No description provided for @total_product.
  ///
  /// In en, this message translates to:
  /// **'Total Products'**
  String get total_product;

  /// No description provided for @exceeds_available_stock.
  ///
  /// In en, this message translates to:
  /// **'Quantity exceeds available stock'**
  String get exceeds_available_stock;

  /// No description provided for @test_env.
  ///
  /// In en, this message translates to:
  /// **'test'**
  String get test_env;

  /// No description provided for @enter_quantity.
  ///
  /// In en, this message translates to:
  /// **'Enter Quantity'**
  String get enter_quantity;

  /// No description provided for @invalid_quantity_or_product.
  ///
  /// In en, this message translates to:
  /// **'Invalid quantity or product'**
  String get invalid_quantity_or_product;

  /// No description provided for @select_product.
  ///
  /// In en, this message translates to:
  /// **'Select Product'**
  String get select_product;

  /// No description provided for @select_customer_and_product.
  ///
  /// In en, this message translates to:
  /// **'Select customer and product'**
  String get select_customer_and_product;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @other_settings.
  ///
  /// In en, this message translates to:
  /// **'Other Settings'**
  String get other_settings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @dark_mode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get dark_mode;

  /// No description provided for @customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customer;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @phone_number.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phone_number;

  /// No description provided for @gstin.
  ///
  /// In en, this message translates to:
  /// **'GSTIN'**
  String get gstin;

  /// No description provided for @enter_valid_gstin.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid GSTIN'**
  String get enter_valid_gstin;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get print;

  /// No description provided for @invoice_number.
  ///
  /// In en, this message translates to:
  /// **'Invoice Number'**
  String get invoice_number;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @customer_list.
  ///
  /// In en, this message translates to:
  /// **'Customer List'**
  String get customer_list;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @enter_invoice_number.
  ///
  /// In en, this message translates to:
  /// **'Enter invoice number'**
  String get enter_invoice_number;

  /// No description provided for @enter_valid_invoice_number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid invoice number'**
  String get enter_valid_invoice_number;

  /// No description provided for @enter_customer_name.
  ///
  /// In en, this message translates to:
  /// **'Enter customer name'**
  String get enter_customer_name;

  /// No description provided for @enter_total_amount.
  ///
  /// In en, this message translates to:
  /// **'Enter total amount'**
  String get enter_total_amount;

  /// No description provided for @total_amount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get total_amount;

  /// No description provided for @enter_valid_total_amount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid total amount'**
  String get enter_valid_total_amount;

  /// No description provided for @save_invoice.
  ///
  /// In en, this message translates to:
  /// **'Save Invoice'**
  String get save_invoice;

  /// No description provided for @add_invoice.
  ///
  /// In en, this message translates to:
  /// **'Add Invoice'**
  String get add_invoice;

  /// No description provided for @ctn.
  ///
  /// In en, this message translates to:
  /// **'CTN'**
  String get ctn;

  /// No description provided for @enter_ctn.
  ///
  /// In en, this message translates to:
  /// **'Enter CTN'**
  String get enter_ctn;

  /// No description provided for @edit_customer.
  ///
  /// In en, this message translates to:
  /// **'Edit Customer'**
  String get edit_customer;

  /// No description provided for @edit_invoice.
  ///
  /// In en, this message translates to:
  /// **'Edit Invoice'**
  String get edit_invoice;

  /// No description provided for @product_details.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get product_details;

  /// No description provided for @invoice_details.
  ///
  /// In en, this message translates to:
  /// **'Invoice Details'**
  String get invoice_details;

  /// No description provided for @invoice_list.
  ///
  /// In en, this message translates to:
  /// **'Invoice List'**
  String get invoice_list;

  /// No description provided for @expense_management.
  ///
  /// In en, this message translates to:
  /// **'Expense Management'**
  String get expense_management;

  /// No description provided for @add_new_expense.
  ///
  /// In en, this message translates to:
  /// **'Add New Expense'**
  String get add_new_expense;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @bank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get bank;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @supplier_colon.
  ///
  /// In en, this message translates to:
  /// **'Supplier:'**
  String get supplier_colon;

  /// No description provided for @select_supplier.
  ///
  /// In en, this message translates to:
  /// **'Select Supplier'**
  String get select_supplier;

  /// No description provided for @notes_optional.
  ///
  /// In en, this message translates to:
  /// **'Notes (Optional)'**
  String get notes_optional;

  /// No description provided for @add_expense.
  ///
  /// In en, this message translates to:
  /// **'Add Expense'**
  String get add_expense;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @total_colon.
  ///
  /// In en, this message translates to:
  /// **'Total:'**
  String get total_colon;

  /// No description provided for @no_expenses.
  ///
  /// In en, this message translates to:
  /// **'No Expenses'**
  String get no_expenses;

  /// No description provided for @error_loading_suppliers.
  ///
  /// In en, this message translates to:
  /// **'Error loading suppliers'**
  String get error_loading_suppliers;

  /// No description provided for @error_loading_expenses.
  ///
  /// In en, this message translates to:
  /// **'Error loading expenses'**
  String get error_loading_expenses;

  /// No description provided for @expense_added_successfully.
  ///
  /// In en, this message translates to:
  /// **'Expense added successfully'**
  String get expense_added_successfully;

  /// No description provided for @error_adding_expense.
  ///
  /// In en, this message translates to:
  /// **'Error adding expense'**
  String get error_adding_expense;

  /// No description provided for @confirm_delete_expense.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this expense?'**
  String get confirm_delete_expense;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get rent;

  /// No description provided for @electricity.
  ///
  /// In en, this message translates to:
  /// **'Electricity'**
  String get electricity;

  /// No description provided for @water.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get water;

  /// No description provided for @internet.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get internet;

  /// No description provided for @salaries.
  ///
  /// In en, this message translates to:
  /// **'Salaries'**
  String get salaries;

  /// No description provided for @maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

  /// No description provided for @marketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get marketing;

  /// No description provided for @other_expenses.
  ///
  /// In en, this message translates to:
  /// **'Other Expenses'**
  String get other_expenses;

  /// No description provided for @supplier_purchases.
  ///
  /// In en, this message translates to:
  /// **'Supplier Purchases'**
  String get supplier_purchases;

  /// No description provided for @sales_and_invoices.
  ///
  /// In en, this message translates to:
  /// **'Sales & Invoices'**
  String get sales_and_invoices;

  /// No description provided for @total_sales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get total_sales;

  /// No description provided for @total_paid.
  ///
  /// In en, this message translates to:
  /// **'Total Paid'**
  String get total_paid;

  /// No description provided for @total_remaining.
  ///
  /// In en, this message translates to:
  /// **'Total Remaining'**
  String get total_remaining;

  /// No description provided for @select_period.
  ///
  /// In en, this message translates to:
  /// **'Select Period'**
  String get select_period;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get remaining;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @reprint.
  ///
  /// In en, this message translates to:
  /// **'Reprint'**
  String get reprint;

  /// No description provided for @make_payment.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get make_payment;

  /// No description provided for @pay_invoice.
  ///
  /// In en, this message translates to:
  /// **'Pay Invoice'**
  String get pay_invoice;

  /// No description provided for @error_loading_data.
  ///
  /// In en, this message translates to:
  /// **'Error loading data'**
  String get error_loading_data;

  /// No description provided for @print_error.
  ///
  /// In en, this message translates to:
  /// **'Print Error'**
  String get print_error;

  /// No description provided for @payment_greater_than_remaining.
  ///
  /// In en, this message translates to:
  /// **'Payment amount greater than remaining'**
  String get payment_greater_than_remaining;

  /// No description provided for @confirm_payment.
  ///
  /// In en, this message translates to:
  /// **'Confirm Payment'**
  String get confirm_payment;

  /// No description provided for @payment_recorded.
  ///
  /// In en, this message translates to:
  /// **'Payment Recorded'**
  String get payment_recorded;

  /// No description provided for @error_recording_payment.
  ///
  /// In en, this message translates to:
  /// **'Error recording payment'**
  String get error_recording_payment;

  /// No description provided for @no_transactions.
  ///
  /// In en, this message translates to:
  /// **'No Transactions'**
  String get no_transactions;

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get sales;

  /// No description provided for @today_sales.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Sales'**
  String get today_sales;

  /// No description provided for @today_expenses.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Expenses'**
  String get today_expenses;

  /// No description provided for @current_balance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get current_balance;

  /// No description provided for @quick_actions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quick_actions;

  /// No description provided for @pay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get pay;

  /// No description provided for @last_transactions.
  ///
  /// In en, this message translates to:
  /// **'Last Transactions'**
  String get last_transactions;

  /// No description provided for @sale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get sale;

  /// No description provided for @purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchase;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get currency;

  /// No description provided for @currency_symbol.
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get currency_symbol;

  /// No description provided for @cashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get cashier;

  /// No description provided for @day_is_open.
  ///
  /// In en, this message translates to:
  /// **'Day is Open'**
  String get day_is_open;

  /// No description provided for @day_is_closed.
  ///
  /// In en, this message translates to:
  /// **'Day is Closed'**
  String get day_is_closed;

  /// No description provided for @close_day.
  ///
  /// In en, this message translates to:
  /// **'Close Day'**
  String get close_day;

  /// No description provided for @open_new_day.
  ///
  /// In en, this message translates to:
  /// **'Open New Day'**
  String get open_new_day;

  /// No description provided for @opening_date.
  ///
  /// In en, this message translates to:
  /// **'Opening Date'**
  String get opening_date;

  /// No description provided for @opening_balance_drawer.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get opening_balance_drawer;

  /// No description provided for @total_revenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get total_revenue;

  /// No description provided for @current_balance_drawer.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get current_balance_drawer;

  /// No description provided for @print_statement.
  ///
  /// In en, this message translates to:
  /// **'Print Statement'**
  String get print_statement;

  /// No description provided for @recent_transactions_cashier.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get recent_transactions_cashier;

  /// No description provided for @opening_balance_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Open New Day'**
  String get opening_balance_dialog_title;

  /// No description provided for @opening_balance_prompt.
  ///
  /// In en, this message translates to:
  /// **'Please enter opening drawer balance:'**
  String get opening_balance_prompt;

  /// No description provided for @opening_balance_label.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance (EGP)'**
  String get opening_balance_label;

  /// No description provided for @invalid_amount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get invalid_amount;

  /// No description provided for @day_opened_successfully.
  ///
  /// In en, this message translates to:
  /// **'Day opened successfully'**
  String get day_opened_successfully;

  /// No description provided for @error_opening_day.
  ///
  /// In en, this message translates to:
  /// **'Error opening day: {error}'**
  String error_opening_day(Object error);

  /// No description provided for @closing_day_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Close Day'**
  String get closing_day_dialog_title;

  /// No description provided for @closing_cash_label.
  ///
  /// In en, this message translates to:
  /// **'Cash Amount (EGP)'**
  String get closing_cash_label;

  /// No description provided for @closing_visa_label.
  ///
  /// In en, this message translates to:
  /// **'Visa Amount (EGP)'**
  String get closing_visa_label;

  /// No description provided for @day_closed_successfully.
  ///
  /// In en, this message translates to:
  /// **'Day closed successfully'**
  String get day_closed_successfully;

  /// No description provided for @error_closing_day.
  ///
  /// In en, this message translates to:
  /// **'Error closing day: {error}'**
  String error_closing_day(Object error);

  /// No description provided for @print_cash_report_success.
  ///
  /// In en, this message translates to:
  /// **'Cash report printed'**
  String get print_cash_report_success;

  /// No description provided for @print_error_param.
  ///
  /// In en, this message translates to:
  /// **'Print error: {error}'**
  String print_error_param(Object error);

  /// No description provided for @visa.
  ///
  /// In en, this message translates to:
  /// **'Visa'**
  String get visa;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @no_products_available_drawer.
  ///
  /// In en, this message translates to:
  /// **'No products available.'**
  String get no_products_available_drawer;

  /// No description provided for @search_product_hint.
  ///
  /// In en, this message translates to:
  /// **'Search for product'**
  String get search_product_hint;

  /// No description provided for @index_short.
  ///
  /// In en, this message translates to:
  /// **'#'**
  String get index_short;

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @product_updated_successfully.
  ///
  /// In en, this message translates to:
  /// **'Product updated successfully'**
  String get product_updated_successfully;

  /// No description provided for @edit_product.
  ///
  /// In en, this message translates to:
  /// **'Edit Product'**
  String get edit_product;

  /// No description provided for @update_product.
  ///
  /// In en, this message translates to:
  /// **'Update Product'**
  String get update_product;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @suppliers_summary.
  ///
  /// In en, this message translates to:
  /// **'Suppliers Summary'**
  String get suppliers_summary;

  /// No description provided for @total_suppliers.
  ///
  /// In en, this message translates to:
  /// **'Total Suppliers'**
  String get total_suppliers;

  /// No description provided for @outstanding_debt.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Debt'**
  String get outstanding_debt;

  /// No description provided for @paid_this_month.
  ///
  /// In en, this message translates to:
  /// **'Paid This Month'**
  String get paid_this_month;

  /// No description provided for @active_suppliers.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active_suppliers;

  /// No description provided for @has_debt.
  ///
  /// In en, this message translates to:
  /// **'Has Debt'**
  String get has_debt;

  /// No description provided for @search_supplier_hint.
  ///
  /// In en, this message translates to:
  /// **'Search for supplier'**
  String get search_supplier_hint;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @add_supplier.
  ///
  /// In en, this message translates to:
  /// **'Add Supplier'**
  String get add_supplier;

  /// No description provided for @no_suppliers_currently.
  ///
  /// In en, this message translates to:
  /// **'No suppliers currently'**
  String get no_suppliers_currently;

  /// No description provided for @add_new_suppliers_to_start.
  ///
  /// In en, this message translates to:
  /// **'Add new suppliers to start'**
  String get add_new_suppliers_to_start;

  /// No description provided for @last_purchase.
  ///
  /// In en, this message translates to:
  /// **'Last Purchase'**
  String get last_purchase;

  /// No description provided for @last_purchase_colon.
  ///
  /// In en, this message translates to:
  /// **'Last Purchase:'**
  String get last_purchase_colon;

  /// No description provided for @debtor.
  ///
  /// In en, this message translates to:
  /// **'Debtor'**
  String get debtor;

  /// No description provided for @entitled.
  ///
  /// In en, this message translates to:
  /// **'Entitled'**
  String get entitled;

  /// No description provided for @contact_information.
  ///
  /// In en, this message translates to:
  /// **'Contact Information'**
  String get contact_information;

  /// No description provided for @total_purchases.
  ///
  /// In en, this message translates to:
  /// **'Total Purchases'**
  String get total_purchases;

  /// No description provided for @add_purchase.
  ///
  /// In en, this message translates to:
  /// **'Add Purchase'**
  String get add_purchase;

  /// No description provided for @purchase_materials.
  ///
  /// In en, this message translates to:
  /// **'Purchase Materials #'**
  String get purchase_materials;

  /// No description provided for @paid_status.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid_status;

  /// No description provided for @settle_payment.
  ///
  /// In en, this message translates to:
  /// **'Settle Payment'**
  String get settle_payment;

  /// No description provided for @add_new_supplier.
  ///
  /// In en, this message translates to:
  /// **'Add New Supplier'**
  String get add_new_supplier;

  /// No description provided for @supplier_name.
  ///
  /// In en, this message translates to:
  /// **'Supplier Name'**
  String get supplier_name;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @opening_balance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get opening_balance;

  /// No description provided for @supplier_added_successfully.
  ///
  /// In en, this message translates to:
  /// **'Supplier added successfully'**
  String get supplier_added_successfully;

  /// No description provided for @advanced_reports.
  ///
  /// In en, this message translates to:
  /// **'Advanced Reports'**
  String get advanced_reports;

  /// No description provided for @reports_and_stats.
  ///
  /// In en, this message translates to:
  /// **'Reports & Statistics'**
  String get reports_and_stats;

  /// No description provided for @dashboard_tab.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard_tab;

  /// No description provided for @sales_report_tab.
  ///
  /// In en, this message translates to:
  /// **'Sales Report'**
  String get sales_report_tab;

  /// No description provided for @expenses_report_tab.
  ///
  /// In en, this message translates to:
  /// **'Expenses Report'**
  String get expenses_report_tab;

  /// No description provided for @customer_balances_tab.
  ///
  /// In en, this message translates to:
  /// **'Customer Balances'**
  String get customer_balances_tab;

  /// No description provided for @date_filter.
  ///
  /// In en, this message translates to:
  /// **'Date Filter'**
  String get date_filter;

  /// No description provided for @select_start_date.
  ///
  /// In en, this message translates to:
  /// **'Select Start Date'**
  String get select_start_date;

  /// No description provided for @select_end_date.
  ///
  /// In en, this message translates to:
  /// **'Select End Date'**
  String get select_end_date;

  /// No description provided for @clear_filter.
  ///
  /// In en, this message translates to:
  /// **'Clear Filter'**
  String get clear_filter;

  /// No description provided for @apply_filter.
  ///
  /// In en, this message translates to:
  /// **'Apply Filter'**
  String get apply_filter;

  /// No description provided for @detailed_sales_report.
  ///
  /// In en, this message translates to:
  /// **'Detailed Sales Report'**
  String get detailed_sales_report;

  /// No description provided for @supplier_expense_report.
  ///
  /// In en, this message translates to:
  /// **'Supplier Expense Report'**
  String get supplier_expense_report;

  /// No description provided for @comprehensive_report.
  ///
  /// In en, this message translates to:
  /// **'Comprehensive Report'**
  String get comprehensive_report;

  /// No description provided for @customer_report.
  ///
  /// In en, this message translates to:
  /// **'Customer Report'**
  String get customer_report;

  /// No description provided for @invoice_count.
  ///
  /// In en, this message translates to:
  /// **'Invoice Count'**
  String get invoice_count;

  /// No description provided for @no_data.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get no_data;

  /// No description provided for @total_sales_colon.
  ///
  /// In en, this message translates to:
  /// **'Total Sales:'**
  String get total_sales_colon;

  /// No description provided for @paid_colon.
  ///
  /// In en, this message translates to:
  /// **'Paid:'**
  String get paid_colon;

  /// No description provided for @current_balance_colon.
  ///
  /// In en, this message translates to:
  /// **'Current Balance:'**
  String get current_balance_colon;

  /// No description provided for @pdf_exported_successfully.
  ///
  /// In en, this message translates to:
  /// **'PDF report exported'**
  String get pdf_exported_successfully;

  /// No description provided for @export_pdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get export_pdf;

  /// No description provided for @excel_exported_successfully.
  ///
  /// In en, this message translates to:
  /// **'Excel report exported'**
  String get excel_exported_successfully;

  /// No description provided for @export_excel.
  ///
  /// In en, this message translates to:
  /// **'Export Excel'**
  String get export_excel;

  /// No description provided for @total_expenses.
  ///
  /// In en, this message translates to:
  /// **'Total Expenses'**
  String get total_expenses;

  /// No description provided for @expenses_count.
  ///
  /// In en, this message translates to:
  /// **'Expenses Count'**
  String get expenses_count;

  /// No description provided for @net_profit.
  ///
  /// In en, this message translates to:
  /// **'Net Profit'**
  String get net_profit;

  /// No description provided for @accounts_receivable.
  ///
  /// In en, this message translates to:
  /// **'Accounts Receivable'**
  String get accounts_receivable;

  /// No description provided for @under_development.
  ///
  /// In en, this message translates to:
  /// **'Under Development'**
  String get under_development;

  /// No description provided for @dashboard_under_development.
  ///
  /// In en, this message translates to:
  /// **'Dashboard under development'**
  String get dashboard_under_development;

  /// No description provided for @outstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get outstanding;

  /// No description provided for @error_loading_data_with_error.
  ///
  /// In en, this message translates to:
  /// **'Error loading data: {error}'**
  String error_loading_data_with_error(Object error);

  /// No description provided for @error_exporting_with_error.
  ///
  /// In en, this message translates to:
  /// **'Error exporting: {error}'**
  String error_exporting_with_error(Object error);

  /// No description provided for @invoice_id_short.
  ///
  /// In en, this message translates to:
  /// **'Inv #'**
  String get invoice_id_short;

  /// No description provided for @payment_method_short.
  ///
  /// In en, this message translates to:
  /// **'Pay Method'**
  String get payment_method_short;

  /// No description provided for @credit_remaining.
  ///
  /// In en, this message translates to:
  /// **'Credit / Remaining'**
  String get credit_remaining;

  /// No description provided for @no_sales_period.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period'**
  String get no_sales_period;

  /// No description provided for @no_expenses_period.
  ///
  /// In en, this message translates to:
  /// **'No expenses in this period'**
  String get no_expenses_period;

  /// No description provided for @no_customers.
  ///
  /// In en, this message translates to:
  /// **'No customers'**
  String get no_customers;

  /// No description provided for @item_description.
  ///
  /// In en, this message translates to:
  /// **'Item / Description'**
  String get item_description;

  /// No description provided for @total_receivables_us.
  ///
  /// In en, this message translates to:
  /// **'Total Receivables (Us)'**
  String get total_receivables_us;

  /// No description provided for @total_payables_us.
  ///
  /// In en, this message translates to:
  /// **'Total Payables (Us)'**
  String get total_payables_us;

  /// No description provided for @receivable_balance.
  ///
  /// In en, this message translates to:
  /// **'Receivable Balance'**
  String get receivable_balance;

  /// No description provided for @invoice_type.
  ///
  /// In en, this message translates to:
  /// **'Invoice Type'**
  String get invoice_type;

  /// No description provided for @cash_invoice.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash_invoice;

  /// No description provided for @credit_invoice.
  ///
  /// In en, this message translates to:
  /// **'Credit (Debt)'**
  String get credit_invoice;

  /// No description provided for @next_add_products.
  ///
  /// In en, this message translates to:
  /// **'Next: Add Products'**
  String get next_add_products;

  /// No description provided for @change_invoice_type.
  ///
  /// In en, this message translates to:
  /// **'Change Invoice Type'**
  String get change_invoice_type;

  /// No description provided for @select_customer_required.
  ///
  /// In en, this message translates to:
  /// **'Select Customer (Required)'**
  String get select_customer_required;

  /// No description provided for @search_customer_hint.
  ///
  /// In en, this message translates to:
  /// **'Search for customer'**
  String get search_customer_hint;

  /// No description provided for @add_new_customers_to_start.
  ///
  /// In en, this message translates to:
  /// **'Add new customers to start'**
  String get add_new_customers_to_start;

  /// No description provided for @walk_in_customer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in Customer'**
  String get walk_in_customer;

  /// No description provided for @required_field.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required_field;

  /// No description provided for @save_and_print.
  ///
  /// In en, this message translates to:
  /// **'Save and Print'**
  String get save_and_print;

  /// No description provided for @please_select_customer_first.
  ///
  /// In en, this message translates to:
  /// **'Please select customer first'**
  String get please_select_customer_first;

  /// No description provided for @invoice_saved_successfully.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved successfully'**
  String get invoice_saved_successfully;

  /// No description provided for @product_saved_successfully.
  ///
  /// In en, this message translates to:
  /// **'Product saved successfully'**
  String get product_saved_successfully;

  /// No description provided for @unit_label.
  ///
  /// In en, this message translates to:
  /// **'Unit (pc, kg, etc.)'**
  String get unit_label;

  /// No description provided for @will_be_registered_as.
  ///
  /// In en, this message translates to:
  /// **'Will be registered as: {name}'**
  String will_be_registered_as(Object name);

  /// No description provided for @pdf_label.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get pdf_label;

  /// No description provided for @excel_label.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get excel_label;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @paid_amount.
  ///
  /// In en, this message translates to:
  /// **'Paid Amount'**
  String get paid_amount;

  /// No description provided for @remaining_amount.
  ///
  /// In en, this message translates to:
  /// **'Remaining Amount'**
  String get remaining_amount;

  /// No description provided for @enter_amount.
  ///
  /// In en, this message translates to:
  /// **'Enter Amount'**
  String get enter_amount;

  /// No description provided for @note_optional.
  ///
  /// In en, this message translates to:
  /// **'Note (Optional)'**
  String get note_optional;

  /// No description provided for @enter_note.
  ///
  /// In en, this message translates to:
  /// **'Enter Note'**
  String get enter_note;

  /// No description provided for @add_payment.
  ///
  /// In en, this message translates to:
  /// **'Add Payment'**
  String get add_payment;

  /// No description provided for @search_customers.
  ///
  /// In en, this message translates to:
  /// **'Search Customers'**
  String get search_customers;

  /// No description provided for @no_customers_found.
  ///
  /// In en, this message translates to:
  /// **'No Customers Found'**
  String get no_customers_found;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @no_email.
  ///
  /// In en, this message translates to:
  /// **'No Email'**
  String get no_email;

  /// No description provided for @no_phone.
  ///
  /// In en, this message translates to:
  /// **'No Phone'**
  String get no_phone;

  /// No description provided for @overdue_balance.
  ///
  /// In en, this message translates to:
  /// **'Overdue Balance'**
  String get overdue_balance;

  /// No description provided for @available_balance.
  ///
  /// In en, this message translates to:
  /// **'Available Balance'**
  String get available_balance;

  /// No description provided for @last_30_days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 Days'**
  String get last_30_days;

  /// No description provided for @last_month.
  ///
  /// In en, this message translates to:
  /// **'Last Month'**
  String get last_month;

  /// No description provided for @last_year.
  ///
  /// In en, this message translates to:
  /// **'Last Year'**
  String get last_year;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @select_date_range.
  ///
  /// In en, this message translates to:
  /// **'Select Date Range'**
  String get select_date_range;

  /// No description provided for @receivable_label.
  ///
  /// In en, this message translates to:
  /// **'Receivable / لنا'**
  String get receivable_label;

  /// No description provided for @payable_label.
  ///
  /// In en, this message translates to:
  /// **'Payable / علينا'**
  String get payable_label;

  /// No description provided for @export_success.
  ///
  /// In en, this message translates to:
  /// **'Export completed successfully'**
  String get export_success;

  /// No description provided for @export_error.
  ///
  /// In en, this message translates to:
  /// **'Export error'**
  String get export_error;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
