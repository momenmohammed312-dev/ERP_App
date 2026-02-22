# =============================================================================
COMPLETE TESTING SOP - POS SAAS SYSTEM
Test Everything Before Customer Delivery

## PURPOSE:

Ensure EVERY feature works correctly before releasing to customers.
No bugs, no crashes, no data loss, no security holes.

## WHO SHOULD USE THIS:

- Developers before release
- QA testers
- You before selling to first customer

## HOW TO USE:

1. Start with fresh installation
1. Follow sections in order
1. Check ✓ each test that passes
1. Fix any failures immediately
1. Retest after fixes
1. Don't skip any test

## TESTING ENVIRONMENT:

□ Clean Windows 10/11 installation
□ No existing POS data
□ Internet connection available
□ Printer connected (for receipt tests)
□ Multiple user accounts (for multi-user tests)

# =============================================================================
SECTION 1: INSTALLATION & ACTIVATION

## TEST 1.1: Fresh Installation

STEPS:

1. Run installer: POS_Setup_v2.0.0.exe
1. Follow installation wizard
1. Launch application after install

EXPECTED RESULTS:
□ Installer runs without errors
□ No antivirus warnings
□ Desktop shortcut created
□ Start menu entry created
□ Application launches successfully
□ Shows activation screen (not home screen)

PASS/FAIL: _______

-----

## TEST 1.2: Device Fingerprint Generation

STEPS:

1. On activation screen, observe Device ID field

EXPECTED RESULTS:
□ Device ID appears automatically
□ Device ID is 64-character hex string
□ Device ID is same every time app restarts
□ Copy button works
□ Device ID copied to clipboard correctly

PASS/FAIL: _______

-----

## TEST 1.3: Invalid License Key

STEPS:

1. Enter random text in License Key field
1. Click "Activate License"

EXPECTED RESULTS:
□ Shows error message
□ Error says "Invalid license format" or similar
□ Application does NOT crash
□ Can try again with different key

PASS/FAIL: _______

-----

## TEST 1.4: Valid License Activation

PREREQUISITE: Generate test license using:

```bash
dart run tools/license_generator.dart
```

- Use Device ID from activation screen
- Select: Standard license, Yearly duration

STEPS:

1. Paste generated license key
1. Click "Activate License"
1. Wait for activation

EXPECTED RESULTS:
□ Success message appears
□ Shows "Activation Successful" screen (green)
□ After 2 seconds, automatically navigates to home
□ No errors in console

PASS/FAIL: _______

-----

## TEST 1.5: License Persistence

STEPS:

1. Close application completely
1. Reopen application

EXPECTED RESULTS:
□ Goes directly to home screen (NOT activation)
□ Does not ask for license again
□ All features accessible

PASS/FAIL: _______

-----

## TEST 1.6: License Information Display

STEPS:

1. Navigate to Settings → License Information
   OR wherever license info is displayed

EXPECTED RESULTS:
□ Shows license type (Standard)
□ Shows duration (Yearly)
□ Shows max users (3)
□ Shows expiry date (1 year from now)
□ Shows days remaining (365)
□ Shows enabled features list
□ All information correct

PASS/FAIL: _______

# =============================================================================
SECTION 2: USER MANAGEMENT

## TEST 2.1: Default Admin User

STEPS:

1. Check if default admin user exists
1. Try to login with default credentials

EXPECTED RESULTS:
□ Default admin exists OR
□ Setup wizard creates first user
□ Can login successfully
□ Admin has full permissions

PASS/FAIL: _______

-----

## TEST 2.2: Create New User (Within Limit)

PREREQUISITE: Standard license (3 users max)

STEPS:

1. Navigate to Users → Add User
1. Enter details:
- Name: "Test User 1"
- Username: "testuser1"
- Password: "Test@123"
- Role: Cashier
1. Click Save

EXPECTED RESULTS:
□ User created successfully
□ Appears in user list
□ Success message shown
□ No errors

STEPS (Repeat):
4. Create "Test User 2" with same process

EXPECTED RESULTS:
□ Second user created successfully
□ Total active users: 3 (admin + 2 test users)

PASS/FAIL: _______

-----

## TEST 2.3: User Limit Enforcement

PREREQUISITE: Already have 3 active users

STEPS:

1. Try to create 4th user
1. Enter details for "Test User 3"
1. Click Save

EXPECTED RESULTS:
□ Shows error message
□ Error says "User limit reached" or similar
□ Mentions current license allows 3 users
□ Suggests upgrading license
□ User is NOT created
□ Total users remains 3

PASS/FAIL: _______

-----

## TEST 2.4: User Login

STEPS:

1. Logout from admin account
1. Login as "testuser1" with password "Test@123"

EXPECTED RESULTS:
□ Login successful
□ Shows correct user name in header/profile
□ User has appropriate permissions
□ Can access allowed features only

PASS/FAIL: _______

-----

## TEST 2.5: Concurrent User Limit

PREREQUISITE: Standard license (3 concurrent users)

STEPS:

1. Login on first computer as admin
1. Login on second computer as testuser1
1. Login on third computer as testuser2
1. Try to login on fourth computer as any user

EXPECTED RESULTS:
□ First 3 logins succeed
□ Fourth login blocked
□ Shows error: "Maximum concurrent users reached"
□ Suggests waiting or upgrading license

PASS/FAIL: _______

-----

## TEST 2.6: Edit User

STEPS:

1. Navigate to Users list
1. Select "testuser1"
1. Click Edit
1. Change name to "Test User One"
1. Change role to "Manager"
1. Click Save

EXPECTED RESULTS:
□ User updated successfully
□ Name changed in list
□ Role changed in list
□ Success message shown

PASS/FAIL: _______

-----

## TEST 2.7: Deactivate User

STEPS:

1. Select "testuser2"
1. Click Deactivate (or change status to inactive)
1. Confirm deactivation

EXPECTED RESULTS:
□ User deactivated (not deleted)
□ User appears as "Inactive" in list
□ User count decreases to 2 active
□ Can no longer login with this user

PASS/FAIL: _______

-----

## TEST 2.8: Reactivate User

STEPS:

1. Select deactivated "testuser2"
1. Click Activate/Reactivate
1. Confirm

EXPECTED RESULTS:
□ User reactivated
□ Appears as active again
□ Can login again
□ Active user count increases to 3

PASS/FAIL: _______

# =============================================================================
SECTION 3: PRODUCT MANAGEMENT

## TEST 3.1: Add New Product

STEPS:

1. Navigate to Products → Add Product
1. Enter details:
- Name: "Test Product 1"
- Barcode: "1234567890123"
- Category: "Test Category"
- Price: 100.00
- Cost: 60.00
- Initial Stock: 50
- Min Stock Alert: 10
1. Click Save

EXPECTED RESULTS:
□ Product created successfully
□ Appears in product list
□ All data saved correctly
□ Stock quantity = 50
□ Success message shown

PASS/FAIL: _______

-----

## TEST 3.2: Barcode Uniqueness

STEPS:

1. Try to add another product with same barcode "1234567890123"

EXPECTED RESULTS:
□ Shows error message
□ Error says "Barcode already exists"
□ Product is NOT created
□ Existing product unchanged

PASS/FAIL: _______

-----

## TEST 3.3: Edit Product

STEPS:

1. Select "Test Product 1"
1. Click Edit
1. Change price to 120.00
1. Change stock to 75
1. Click Save

EXPECTED RESULTS:
□ Product updated successfully
□ Price changed to 120.00
□ Stock changed to 75
□ Other fields unchanged

PASS/FAIL: _______

-----

## TEST 3.4: Search Product by Name

STEPS:

1. In product search box, type "Test"

EXPECTED RESULTS:
□ Shows products matching "Test"
□ Shows "Test Product 1"
□ Other products filtered out
□ Search is case-insensitive

PASS/FAIL: _______

-----

## TEST 3.5: Search Product by Barcode

STEPS:

1. Clear search
1. Type barcode "1234567890123"

EXPECTED RESULTS:
□ Shows exact match product
□ Only "Test Product 1" displayed
□ Quick result (< 1 second)

PASS/FAIL: _______

-----

## TEST 3.6: Low Stock Alert

STEPS:

1. Edit "Test Product 1"
1. Set stock to 5 (below min stock of 10)
1. Save

EXPECTED RESULTS:
□ Product shows low stock indicator/warning
□ Appears in low stock report/alert
□ Visual indicator (red color or icon)

PASS/FAIL: _______

-----

## TEST 3.7: Add Product with Image

STEPS:

1. Add new product "Test Product 2"
1. Upload product image (JPG/PNG)
1. Save

EXPECTED RESULTS:
□ Image uploads successfully
□ Image displays in product details
□ Image displays in product list (thumbnail)
□ Image size reasonable (< 1 MB)

PASS/FAIL: _______

-----

## TEST 3.8: Delete Product (if allowed)

STEPS:

1. Create temporary product "Delete Test"
1. Try to delete it

EXPECTED RESULTS:
□ Shows confirmation dialog
□ Warns about implications
□ After confirmation, product deleted
□ Disappears from product list

PASS/FAIL: _______

# =============================================================================
SECTION 4: SALES / INVOICES (CASH)

## TEST 4.1: Open Day/Shift

PREREQUISITE: No day currently open

STEPS:

1. Navigate to Open Day/Shift
1. Enter opening cash: 1000.00
1. Click Open Day

EXPECTED RESULTS:
□ Day opened successfully
□ Shows day is now open
□ Opening cash recorded
□ Can now create invoices

PASS/FAIL: _______

-----

## TEST 4.2: Create Cash Invoice

STEPS:

1. Click "New Invoice"
1. Select "Cash" (نقدي)
1. Add "Test Product 1" (price 120, qty 50 available)
1. Enter quantity: 2
1. Verify subtotal: 240.00
1. Add another product if available, qty 1
1. Review total
1. Enter paid amount = total
1. Click Save/Complete

EXPECTED RESULTS:
□ Invoice created successfully
□ Invoice number generated
□ Total calculated correctly
□ Tax calculated (if applicable)
□ Stock decreased by sold quantities
□ Invoice saved to database
□ Receipt printed (if printer connected)
□ Success message shown

PASS/FAIL: _______

-----

## TEST 4.3: Cash Invoice with Change

STEPS:

1. Create new cash invoice
1. Total = 240.00
1. Enter paid amount = 300.00
1. Complete invoice

EXPECTED RESULTS:
□ Shows change due: 60.00
□ Change displayed clearly before save
□ Invoice completes successfully
□ Paid = 300, Change = 60 recorded

PASS/FAIL: _______

-----

## TEST 4.4: Insufficient Payment

STEPS:

1. Create new cash invoice
1. Total = 240.00
1. Enter paid amount = 100.00
1. Try to complete

EXPECTED RESULTS:
□ Shows error or warning
□ Does not allow completion
□ Asks for full payment (cash invoice)
□ Invoice NOT saved

PASS/FAIL: _______

-----

## TEST 4.5: Invoice Discount

STEPS:

1. Create new invoice
1. Subtotal = 240.00
1. Apply 10% discount
1. Complete invoice

EXPECTED RESULTS:
□ Discount applied correctly (24.00)
□ Total = 216.00
□ Discount shown on receipt
□ Saved correctly in database

PASS/FAIL: _______

-----

## TEST 4.6: View Invoice Details

STEPS:

1. Navigate to Invoices list
1. Find last created invoice
1. Click to view details

EXPECTED RESULTS:
□ Shows complete invoice information
□ Customer name (if applicable)
□ Date and time
□ Items with quantities and prices
□ Total, discount, tax
□ Payment method
□ Invoice number
□ All data matches original

PASS/FAIL: _______

-----

## TEST 4.7: Print Invoice/Receipt

PREREQUISITE: Printer connected

STEPS:

1. Open invoice details
1. Click Print/Receipt button

EXPECTED RESULTS:
□ Print dialog appears
□ Receipt prints successfully
□ All data legible
□ Formatting correct (Arabic/English)
□ Company header/logo (if configured)
□ Barcode/QR code (if configured)

PASS/FAIL: _______

-----

## TEST 4.8: Search Invoices

STEPS:

1. Navigate to Invoices
1. Search by invoice number
1. Search by date range
1. Search by customer name (if applicable)

EXPECTED RESULTS:
□ Search by invoice number works
□ Search by date range works
□ Results display correctly
□ Can clear search
□ Fast response (< 2 seconds)

PASS/FAIL: _______

# =============================================================================
SECTION 5: CREDIT SALES (آجل - Customer Debt)

## TEST 5.1: Create Customer

STEPS:

1. Navigate to Customers → Add Customer
1. Enter:
- Name: "Test Customer 1"
- Phone: "01234567890"
- Address: "Test Address"
1. Save

EXPECTED RESULTS:
□ Customer created successfully
□ Appears in customer list
□ Can be selected in invoices

PASS/FAIL: _______

-----

## TEST 5.2: Create Credit Invoice (Full Credit)

STEPS:

1. Click "New Invoice"
1. Select "Credit/آجل"
1. Select customer: "Test Customer 1"
1. Add products, total = 500.00
1. Paid amount = 0.00 (full credit)
1. Complete invoice

EXPECTED RESULTS:
□ Invoice created successfully
□ Remaining debt = 500.00
□ Debt recorded under customer
□ Stock decreased
□ Customer balance shows 500.00 debt

PASS/FAIL: _______

-----

## TEST 5.3: Create Credit Invoice (Partial Payment)

STEPS:

1. Create credit invoice for same customer
1. Total = 300.00
1. Paid = 100.00
1. Complete invoice

EXPECTED RESULTS:
□ Invoice saved successfully
□ Paid = 100, Remaining = 200
□ Customer total debt now = 700.00 (500 + 200)
□ Both invoices appear in customer history

PASS/FAIL: _______

-----

## TEST 5.4: Customer Payment (Pay Off Debt)

STEPS:

1. Navigate to Customers
1. Select "Test Customer 1"
1. Click "Add Payment"
1. Enter payment: 300.00
1. Save payment

EXPECTED RESULTS:
□ Payment recorded successfully
□ Customer debt decreased to 400.00
□ Payment appears in transaction history
□ Receipt generated (if configured)

PASS/FAIL: _______

-----

## TEST 5.5: Customer Statement

STEPS:

1. View "Test Customer 1" details
1. Click "Statement" or "Transaction History"

EXPECTED RESULTS:
□ Shows all transactions chronologically
□ Shows invoices (increases debt)
□ Shows payments (decreases debt)
□ Running balance displayed
□ Current balance = 400.00
□ Can print statement

PASS/FAIL: _______

-----

## TEST 5.6: Customer Debt Report

STEPS:

1. Navigate to Reports → Customer Debts
   OR Reports → Accounts Receivable

EXPECTED RESULTS:
□ Lists all customers with debt
□ Shows "Test Customer 1" with 400.00
□ Shows total debt across all customers
□ Can filter by date range
□ Can export to Excel/PDF

PASS/FAIL: _______

# =============================================================================
SECTION 6: PURCHASES/SUPPLY (توريد - NEW FEATURE)

## TEST 6.1: Create Supplier

STEPS:

1. Navigate to Suppliers → Add Supplier
1. Enter:
- Name: "Test Supplier 1"
- Phone: "01098765432"
- Address: "Supplier Address"
1. Save

EXPECTED RESULTS:
□ Supplier created successfully
□ Appears in supplier list
□ Can be selected in supply invoices

PASS/FAIL: _______

-----

## TEST 6.2: Create Supply Invoice

STEPS:

1. Click "New Invoice"
1. Select "Supply/توريد" (third button - NEW)
1. Select supplier: "Test Supplier 1"
1. Add products:
- Test Product 1, qty 20, cost 60 each
- Total = 1200.00
1. Paid = 500.00 (partial payment)
1. Complete invoice

EXPECTED RESULTS:
□ Supply invoice created successfully
□ Stock INCREASED by 20 (not decreased!)
□ Remaining debt to supplier = 700.00
□ Debt recorded as "payable" (we owe them)
□ Supplier balance shows 700.00 payable

PASS/FAIL: _______

-----

## TEST 6.3: Verify Stock Increase

STEPS:

1. Check "Test Product 1" stock before supply
1. Note: was 50 (or current amount)
1. After supply of 20 units
1. Check stock again

EXPECTED RESULTS:
□ Stock increased by exactly 20
□ New stock = previous + 20
□ No stock decrease
□ Inventory value updated

PASS/FAIL: _______

-----

## TEST 6.4: Supplier Payment

STEPS:

1. Navigate to Suppliers
1. Select "Test Supplier 1"
1. Click "Add Payment"
1. Pay 300.00
1. Save

EXPECTED RESULTS:
□ Payment recorded
□ Supplier debt decreased to 400.00
□ Payment in transaction history
□ Correct accounting

PASS/FAIL: _______

-----

## TEST 6.5: Supplier Statement

STEPS:

1. View "Test Supplier 1" details
1. View statement/history

EXPECTED RESULTS:
□ Shows supply invoices (we owe more)
□ Shows payments (we owe less)
□ Running balance correct
□ Current payable = 400.00

PASS/FAIL: _______

-----

## TEST 6.6: Supplier Debt Report

STEPS:

1. Navigate to Reports → Supplier Debts
   OR Reports → Accounts Payable

EXPECTED RESULTS:
□ Lists suppliers we owe money to
□ Shows "Test Supplier 1" with 400.00
□ Shows total payable
□ Can export report

PASS/FAIL: _______

# =============================================================================
SECTION 7: REPORTS

## TEST 7.1: Sales Report (Daily)

STEPS:

1. Navigate to Reports → Sales
1. Select date range: Today
1. Generate report

EXPECTED RESULTS:
□ Shows all sales for today
□ Shows total sales amount
□ Shows number of invoices
□ Shows payment methods breakdown
□ Can export to Excel/PDF
□ Report accurate

PASS/FAIL: _______

-----

## TEST 7.2: Sales Report (Date Range)

STEPS:

1. Select date range: Last 7 days
1. Generate report

EXPECTED RESULTS:
□ Shows sales for last 7 days
□ Daily breakdown visible
□ Total for period correct
□ Can filter by customer/product

PASS/FAIL: _______

-----

## TEST 7.3: Product Sales Report

STEPS:

1. Navigate to Reports → Product Sales
1. Generate for date range

EXPECTED RESULTS:
□ Lists all products sold
□ Shows quantities sold
□ Shows revenue per product
□ Sorted by revenue (highest first)
□ Can export

PASS/FAIL: _______

-----

## TEST 7.4: Inventory Report

STEPS:

1. Navigate to Reports → Inventory
1. Generate current inventory report

EXPECTED RESULTS:
□ Lists all products
□ Shows current stock levels
□ Shows products below minimum stock (highlighted)
□ Shows inventory value (qty × cost)
□ Total inventory value calculated

PASS/FAIL: _______

-----

## TEST 7.5: Profit Report

STEPS:

1. Navigate to Reports → Profit/Loss
1. Select date range
1. Generate

EXPECTED RESULTS:
□ Shows total revenue
□ Shows total cost of goods sold
□ Shows gross profit
□ Shows profit margin %
□ Accurate calculations

PASS/FAIL: _______

-----

## TEST 7.6: Customer Report

STEPS:

1. Navigate to Reports → Customers
1. Generate report

EXPECTED RESULTS:
□ Lists all customers
□ Shows total purchases per customer
□ Shows payments received
□ Shows outstanding debt
□ Sorted by total purchases

PASS/FAIL: _______

-----

## TEST 7.7: Supplier Report (NEW)

STEPS:

1. Navigate to Reports → Suppliers
1. Generate report

EXPECTED RESULTS:
□ Lists all suppliers
□ Shows total purchases from each
□ Shows payments made
□ Shows outstanding payables
□ Can export

PASS/FAIL: _______

-----

## TEST 7.8: Purchase Report (NEW)

STEPS:

1. Navigate to Reports → Purchases
1. Select date range
1. Generate

EXPECTED RESULTS:
□ Lists all supply invoices
□ Shows quantities purchased
□ Shows costs
□ Total purchases calculated
□ Can filter by supplier

PASS/FAIL: _______

-----

## TEST 7.9: Sales vs Purchases Comparison (NEW - Dashboard)

STEPS:

1. Go to home/dashboard screen
1. Observe comparison widget

EXPECTED RESULTS:
□ Shows today's sales total
□ Shows today's purchases total
□ Shows profit/loss for today
□ Color coded (green profit, red loss)
□ Refresh button works

PASS/FAIL: _______

# =============================================================================
SECTION 8: DAY/SHIFT MANAGEMENT

## TEST 8.1: Cannot Create Invoice Before Opening Day

STEPS:

1. Ensure no day is currently open
1. Try to click "New Invoice"

EXPECTED RESULTS:
□ Shows warning/error dialog
□ Says "Must open day first"
□ Offers to open day now
□ Cannot proceed to invoice without opening day

PASS/FAIL: _______

-----

## TEST 8.2: Open Day

STEPS:

1. Navigate to Open Day
1. Enter opening cash: 2000.00
1. Click Open

EXPECTED RESULTS:
□ Day opened successfully
□ Opening cash recorded
□ Date/time recorded
□ Can now create invoices
□ Dashboard shows "Day Open"

PASS/FAIL: _______

-----

## TEST 8.3: Day Summary

STEPS:

1. During open day, create a few transactions
1. Navigate to Day Summary/Report

EXPECTED RESULTS:
□ Shows opening cash
□ Shows total sales
□ Shows cash received
□ Shows credit sales
□ Shows expected cash (opening + cash sales)
□ All figures accurate

PASS/FAIL: _______

-----

## TEST 8.4: Close Day

STEPS:

1. Navigate to Close Day
1. Enter actual cash in drawer: (calculate expected)
1. Click Close Day

EXPECTED RESULTS:
□ Shows comparison: expected vs actual
□ Shows surplus/shortage
□ Day closes successfully
□ Cannot create new invoices after close
□ Day report saved

PASS/FAIL: _______

-----

## TEST 8.5: View Past Day Reports

STEPS:

1. Navigate to Day Reports/History
1. Select a closed day
1. View details

EXPECTED RESULTS:
□ Lists all closed days
□ Can view any past day
□ Shows complete summary
□ Shows all transactions for that day
□ Can print day report

PASS/FAIL: _______

# =============================================================================
SECTION 9: BACKUP & RESTORE

## TEST 9.1: Manual Backup

STEPS:

1. Navigate to Settings → Backup
1. Click "Create Backup Now"
1. Wait for completion

EXPECTED RESULTS:
□ Backup creates successfully
□ Shows success message
□ Backup file appears in list
□ File size reasonable (several MB)
□ Timestamp correct

PASS/FAIL: _______

-----

## TEST 9.2: Automatic Backup (Daily)

PREREQUISITE: Leave app running overnight OR change system time

STEPS:

1. Check backup folder next day
1. Verify automatic backup created

EXPECTED RESULTS:
□ Automatic backup file exists
□ Created around 11 PM (scheduled time)
□ File size correct
□ No errors in logs

PASS/FAIL: _______

-----

## TEST 9.3: Automatic Backup (Transaction Threshold)

STEPS:

1. Create 100+ invoices (use test data script if available)
1. Check for automatic backup

EXPECTED RESULTS:
□ Backup created after 100 transactions
□ Backup counter reset
□ File saved correctly

PASS/FAIL: _______

-----

## TEST 9.4: Backup Retention

STEPS:

1. Create multiple backups (8 or more)
1. Check backup folder

EXPECTED RESULTS:
□ Only last 7 backups kept
□ Older backups automatically deleted
□ Most recent backups preserved

PASS/FAIL: _______

-----

## TEST 9.5: Export Backup to USB

PREREQUISITE: USB drive connected

STEPS:

1. Click "Export to USB"
1. Select destination folder
1. Save

EXPECTED RESULTS:
□ File picker opens
□ Can select USB location
□ Backup file copied successfully
□ Success message shown

PASS/FAIL: _______

-----

## TEST 9.6: Restore Backup

⚠️ CRITICAL TEST - Can cause data loss if not careful!

STEPS:

1. Create fresh test data (5-10 invoices)
1. Create backup of this state
1. Add more data (5 more invoices)
1. Restore to earlier backup

EXPECTED RESULTS:
□ Shows warning before restore
□ Requires confirmation
□ Restore completes successfully
□ App restarts automatically
□ After restart: only first 5-10 invoices present
□ Recent invoices (after backup) are gone
□ Database intact, no corruption

PASS/FAIL: _______

-----

## TEST 9.7: Import Backup from External File

STEPS:

1. Copy backup file from another location
1. Click "Import Backup"
1. Select the backup file
1. Confirm restore

EXPECTED RESULTS:
□ Can select any .db file
□ Import proceeds
□ Shows warning about data loss
□ After import, data from that backup appears
□ App restarts

PASS/FAIL: _______

# =============================================================================
SECTION 10: SECURITY TESTS

## TEST 10.1: License Tampering - Wrong Device

STEPS:

1. Copy license key to different computer
   OR change hardware (if possible)
1. Try to activate

EXPECTED RESULTS:
□ Activation fails
□ Shows error: "License not valid for this device"
□ Cannot use software

PASS/FAIL: _______

-----

## TEST 10.2: Clock Tampering - Date Backward

⚠️ CRITICAL SECURITY TEST

STEPS:

1. Note current date
1. Use software normally
1. Close software
1. Change Windows date to yesterday
1. Restart software

EXPECTED RESULTS:
□ Software detects tampering
□ Shows red warning screen
□ Says "Clock tampering detected"
□ Blocks access to software
□ Cannot proceed

PASS/FAIL: _______

-----

## TEST 10.3: Clock Tampering - Date Forward

STEPS:

1. Close software
1. Change Windows date to tomorrow
1. Restart software

EXPECTED RESULTS:
□ Software works normally (forward is OK)
□ New date stored
□ No tampering warning

PASS/FAIL: _______

-----

## TEST 10.4: Database Encryption

STEPS:

1. Close software
1. Navigate to database folder:
   C:\Users\YourName\AppData\Local\YourApp\
1. Find .db file
1. Try to open with "DB Browser for SQLite"

EXPECTED RESULTS:
□ DB Browser cannot open file
□ Shows error: "file is not a database" OR
□ Shows error: "file is encrypted"
□ Data is protected

PASS/FAIL: _______

-----

## TEST 10.5: License Expiration

PREREQUISITE: Generate 1-day test license

STEPS:

1. Activate 1-day license
1. Wait 25+ hours OR change system date forward
1. Restart software

EXPECTED RESULTS:
□ Software detects expiration
□ Shows "License expired" message
□ Returns to activation screen
□ Cannot access features

PASS/FAIL: _______

-----

## TEST 10.6: Session Timeout

STEPS:

1. Login and leave idle for 8+ hours
   OR change system time forward 8 hours
1. Try to perform an action

EXPECTED RESULTS:
□ Session expires
□ Shows "Session expired" message
□ Redirects to login
□ Must re-login to continue

PASS/FAIL: _______

-----

## TEST 10.7: Audit Trail

STEPS:

1. Perform various actions:
- Create invoice
- Add product
- Edit customer
- Delete item (if allowed)
1. Navigate to Audit Log (if visible)
   OR query database: SELECT * FROM audit_log

EXPECTED RESULTS:
□ All actions logged
□ Logs include: user, action type, table, timestamp
□ Sensitive details encrypted
□ Cannot delete audit logs

PASS/FAIL: _______

# =============================================================================
SECTION 11: PERFORMANCE TESTS

## TEST 11.1: Large Product List

PREREQUISITE: 1000+ products in database

STEPS:

1. Navigate to Products list
1. Scroll through list
1. Search for product

EXPECTED RESULTS:
□ List loads in < 3 seconds
□ Scrolling is smooth
□ Search returns results in < 1 second
□ No lag or freezing

PASS/FAIL: _______

-----

## TEST 11.2: Large Invoice History

PREREQUISITE: 500+ invoices in database

STEPS:

1. Navigate to Invoices list
1. Scroll through
1. Search by date range

EXPECTED RESULTS:
□ Pagination works (if implemented)
□ Loads quickly (< 5 seconds)
□ No memory issues
□ Can view any invoice

PASS/FAIL: _______

-----

## TEST 11.3: Report Generation Speed

STEPS:

1. Generate sales report for 30 days
1. With significant data (100+ invoices)

EXPECTED RESULTS:
□ Report generates in < 10 seconds
□ Accurate results
□ Can export quickly

PASS/FAIL: _______

-----

## TEST 11.4: Database Size

STEPS:

1. After extensive testing, check .db file size

EXPECTED RESULTS:
□ Reasonable size (< 100 MB for test data)
□ Not bloated
□ Backup files reasonable size

PASS/FAIL: _______

-----

## TEST 11.5: Startup Time

STEPS:

1. Close application
1. Time how long to open and reach home screen

EXPECTED RESULTS:
□ Launches in < 5 seconds
□ No excessive loading time
□ Responsive immediately

PASS/FAIL: _______

# =============================================================================
SECTION 12: UI/UX TESTS

## TEST 12.1: Arabic Language Support

STEPS:

1. Check all screens
1. Verify text direction (RTL)

EXPECTED RESULTS:
□ All text in Arabic (or selected language)
□ Right-to-left alignment correct
□ Buttons aligned properly
□ Numbers display correctly
□ Dates formatted correctly

PASS/FAIL: _______

-----

## TEST 12.2: Responsive Design

STEPS:

1. Resize window to different sizes:
- Minimum size (800x600)
- Medium size (1366x768)
- Large size (1920x1080)

EXPECTED RESULTS:
□ All elements visible at all sizes
□ No overlapping text
□ Buttons accessible
□ Scrollbars appear when needed
□ Layout adapts appropriately

PASS/FAIL: _______

-----

## TEST 12.3: Error Messages

STEPS:

1. Trigger various errors intentionally:
- Invalid input
- Required field empty
- Duplicate entry

EXPECTED RESULTS:
□ Error messages clear and helpful
□ In correct language (Arabic/English)
□ Suggest how to fix
□ Polite and professional

PASS/FAIL: _______

-----

## TEST 12.4: Success Messages

STEPS:

1. Complete successful actions:
- Save product
- Complete invoice
- Create backup

EXPECTED RESULTS:
□ Success messages appear
□ Clear and concise
□ Auto-dismiss after 3-5 seconds
□ Green color or checkmark icon

PASS/FAIL: _______

-----

## TEST 12.5: Loading Indicators

STEPS:

1. Perform slow operations:
- Generate large report
- Load many records

EXPECTED RESULTS:
□ Loading spinner appears
□ User knows app is working
□ Cannot double-click during load
□ Spinner disappears when done

PASS/FAIL: _______

-----

## TEST 12.6: Keyboard Navigation

STEPS:

1. Use Tab key to navigate forms
1. Use Enter to submit
1. Use Esc to cancel

EXPECTED RESULTS:
□ Tab moves through fields logically
□ Enter submits forms
□ Esc closes dialogs
□ Focus visible

PASS/FAIL: _______

-----

## TEST 12.7: Tooltips and Help

STEPS:

1. Hover over buttons and icons
1. Look for help text

EXPECTED RESULTS:
□ Important buttons have tooltips
□ Tooltips are helpful
□ Help text available for complex features

PASS/FAIL: _______

# =============================================================================
SECTION 13: EDGE CASES & ERROR HANDLING

## TEST 13.1: Empty Database

STEPS:

1. Fresh install (or restore empty backup)
1. Try to generate reports
1. Try to view lists

EXPECTED RESULTS:
□ No crashes
□ Shows "No data" messages
□ Guides user to add data
□ All features accessible

PASS/FAIL: _______

-----

## TEST 13.2: Very Long Text

STEPS:

1. Enter very long product name (500+ characters)
1. Enter very long customer address
1. Save and retrieve

EXPECTED RESULTS:
□ Text is truncated or trimmed appropriately
□ OR shows validation error
□ No database errors
□ Display handles long text gracefully

PASS/FAIL: _______

-----

## TEST 13.3: Special Characters

STEPS:

1. Enter product name: "Test & Product #1 @ $100"
1. Enter Arabic diacritics: "مُنتَج"
1. Save and retrieve

EXPECTED RESULTS:
□ Special characters saved correctly
□ Display correctly
□ No encoding issues
□ Arabic diacritics preserved

PASS/FAIL: _______

-----

## TEST 13.4: Negative Numbers

STEPS:

1. Try to enter negative quantity
1. Try to enter negative price

EXPECTED RESULTS:
□ Validation prevents negative values
□ OR shows clear error
□ Cannot save invalid data

PASS/FAIL: _______

-----

## TEST 13.5: Zero Values

STEPS:

1. Create invoice with quantity = 0
1. Set product price = 0
1. Try to save

EXPECTED RESULTS:
□ Validation handles appropriately
□ Either prevents or warns
□ No calculation errors

PASS/FAIL: _______

-----

## TEST 13.6: Decimal Precision

STEPS:

1. Enter price: 10.999
1. Calculate total with multiple items

EXPECTED RESULTS:
□ Decimals handled correctly
□ Rounds appropriately (2 decimal places)
□ Totals accurate
□ No rounding errors accumulate

PASS/FAIL: _______

-----

## TEST 13.7: Concurrent Edits

PREREQUISITE: Two users logged in

STEPS:

1. User A opens product for edit
1. User B opens same product for edit
1. User A saves changes
1. User B saves changes

EXPECTED RESULTS:
□ Last save wins OR
□ Warning shown about concurrent edit
□ No data corruption
□ Both users notified appropriately

PASS/FAIL: _______

-----

## TEST 13.8: Power Loss Simulation

⚠️ CAUTION: May cause data loss

STEPS:

1. Start creating invoice
1. Add several items
1. DO NOT save
1. Force close application (Alt+F4 or Task Manager)
1. Restart application

EXPECTED RESULTS:
□ Unsaved invoice is lost (expected)
□ Database not corrupted
□ App starts normally
□ No lingering temp data

PASS/FAIL: _______

-----

## TEST 13.9: Disk Full Scenario

STEPS:

1. Fill disk to near capacity
1. Try to create backup
1. Try to save invoice

EXPECTED RESULTS:
□ Shows clear error: "Disk full" or similar
□ Does not crash
□ User can take action
□ No partial/corrupt saves

PASS/FAIL: _______

-----

## TEST 13.10: No Printer Connected

STEPS:

1. Disconnect printer
1. Try to print invoice

EXPECTED RESULTS:
□ Shows warning: "No printer found"
□ Offers to save as PDF instead
□ Does not crash
□ Invoice still saved in database

PASS/FAIL: _______

# =============================================================================
SECTION 14: UPDATE SYSTEM

## TEST 14.1: Check for Updates (No Update Available)

STEPS:

1. Ensure app is latest version
1. Manually check for updates

EXPECTED RESULTS:
□ Contacts update server
□ Shows "Already on latest version"
□ No errors if no internet
□ Fails gracefully if server down

PASS/FAIL: _______

-----

## TEST 14.2: Check for Updates (Update Available)

PREREQUISITE: Prepare test update server with higher version

STEPS:

1. Check for updates
1. New version detected

EXPECTED RESULTS:
□ Shows update dialog
□ Displays version number
□ Shows changelog
□ Shows download size
□ Can choose "Update Now" or "Later"

PASS/FAIL: _______

-----

## TEST 14.3: Download Update

STEPS:

1. Click "Update Now"
1. Watch progress

EXPECTED RESULTS:
□ Download starts
□ Progress bar shows percentage
□ Download completes
□ Checksum verified
□ No corruption

PASS/FAIL: _______

-----

## TEST 14.4: Install Update

STEPS:

1. After download, click Install
1. Follow prompts

EXPECTED RESULTS:
□ Installer runs
□ Application closes
□ Update installs
□ Can restart application
□ New version active

PASS/FAIL: _______

-----

## TEST 14.5: Critical Update (Forced)

PREREQUISITE: Set update as critical on server

STEPS:

1. Check for updates
1. Critical update detected

EXPECTED RESULTS:
□ Shows red warning
□ Cannot dismiss dialog
□ Must install to continue
□ Emphasizes importance

PASS/FAIL: _______

-----

## TEST 14.6: Auto-Check (Background)

STEPS:

1. Leave app running for 6+ hours
   (or reduce check interval in code for testing)

EXPECTED RESULTS:
□ Automatically checks for updates
□ Silent check (no interruption)
□ If update found, shows notification
□ User can choose to install or postpone

PASS/FAIL: _______

# =============================================================================
FINAL ACCEPTANCE CRITERIA

OVERALL SYSTEM STABILITY:
□ No crashes during any test
□ All features work as expected
□ Data integrity maintained
□ Performance acceptable
□ Security measures effective

CRITICAL FEATURES (MUST PASS):
□ License activation works
□ License persistence works
□ User management works
□ Product management works
□ Invoice creation works (all types)
□ Stock updates correctly
□ Reports generate accurately
□ Backup and restore work
□ Security protections active

IMPORTANT FEATURES (SHOULD PASS):
□ Search functions work
□ Export features work
□ Printing works
□ Update system works
□ Audit trail complete

NICE TO HAVE (CAN HAVE MINOR ISSUES):
□ UI perfect on all resolutions
□ All tooltips present
□ Every edge case handled

# =============================================================================
TEST COMPLETION SUMMARY

Total Tests: 140+
Tests Passed: _______
Tests Failed: _______
Pass Rate: _______%

CRITICAL FAILURES (MUST FIX BEFORE RELEASE):

1. -----
1. -----
1. -----

MINOR ISSUES (FIX IF TIME PERMITS):

1. -----
1. -----
1. -----

NOTES:

-----

-----

-----

TESTED BY: ____________________
DATE: __________________
VERSION: ________________

APPROVED FOR RELEASE: YES / NO

SIGNATURE: ____________________

# =============================================================================
END OF SOP
