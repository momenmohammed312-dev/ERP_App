import 'package:drift/drift.dart';

/// Staff table for employee management
@DataClassName('Staff')
class StaffTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text().unique()(); // Unique staff identifier

  TextColumn get name => text()(); // Employee full name

  TextColumn get nationalId => text().nullable()(); // National ID number

  TextColumn get phone => text().nullable()(); // Phone number

  TextColumn get email => text().nullable()(); // Email address

  TextColumn get address => text().nullable()(); // Home address

  TextColumn get position => text()(); // Job position/title

  TextColumn get department => text().nullable()(); // Department

  TextColumn get employmentType =>
      text()(); // 'full_time', 'part_time', 'contract'

  RealColumn get basicSalary => real()(); // Basic salary

  RealColumn get hourlyRate => real().nullable()(); // Hourly rate for part-time

  DateTimeColumn get hireDate => dateTime()(); // Hire date

  DateTimeColumn get contractEndDate =>
      dateTime().nullable()(); // Contract end date

  TextColumn get status => text()(); // 'active', 'terminated', 'on_leave'

  TextColumn get bankName =>
      text().nullable()(); // Bank name for salary transfer

  TextColumn get bankAccount => text().nullable()(); // Bank account number

  TextColumn get emergencyContact =>
      text().nullable()(); // Emergency contact name

  TextColumn get emergencyPhone =>
      text().nullable()(); // Emergency contact phone

  TextColumn get notes => text().nullable()(); // Additional notes

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Attendance table for tracking employee attendance
@DataClassName('Attendance')
class AttendanceTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  DateTimeColumn get date => dateTime()(); // Attendance date

  DateTimeColumn get checkInTime => dateTime().nullable()(); // Check-in time

  DateTimeColumn get checkOutTime => dateTime().nullable()(); // Check-out time

  TextColumn get checkInLocation =>
      text().nullable()(); // GPS location or notes

  TextColumn get checkOutLocation =>
      text().nullable()(); // GPS location or notes

  RealColumn get workingHours => real().nullable()(); // Total working hours

  TextColumn get status =>
      text()(); // 'present', 'absent', 'late', 'half_day', 'leave'

  TextColumn get leaveType =>
      text().nullable()(); // 'sick', 'annual', 'emergency', 'unpaid'

  TextColumn get notes => text().nullable()(); // Attendance notes

  RealColumn get overtimeHours =>
      real().withDefault(const Constant(0))(); // Overtime hours

  TextColumn get approvedBy => text().nullable()(); // Manager who approved

  DateTimeColumn get approvedAt =>
      dateTime().nullable()(); // Approval timestamp

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  // No custom primaryKey needed - using default composite key
}

/// Vacations table for managing employee leave requests
@DataClassName('Vacation')
class Vacations extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  TextColumn get vacationType =>
      text()(); // 'annual', 'sick', 'emergency', 'unpaid', 'maternity'

  DateTimeColumn get startDate => dateTime()(); // Vacation start date

  DateTimeColumn get endDate => dateTime()(); // Vacation end date

  IntColumn get totalDays => integer()(); // Total vacation days

  TextColumn get reason => text().nullable()(); // Vacation reason

  TextColumn get status =>
      text()(); // 'pending', 'approved', 'rejected', 'cancelled'

  TextColumn get approvedBy =>
      text().nullable()(); // Manager who approved/rejected

  DateTimeColumn get approvedAt =>
      dateTime().nullable()(); // Approval timestamp

  TextColumn get rejectionReason => text().nullable()(); // Reason for rejection

  TextColumn get contactDuringVacation =>
      text().nullable()(); // Contact info during vacation

  TextColumn get handoverTo => text().nullable()(); // Who handles their work

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// Staff advances table for managing salary advances
@DataClassName('StaffAdvance')
class StaffAdvances extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  RealColumn get amount => real()(); // Advance amount

  TextColumn get reason => text().nullable()(); // Reason for advance

  DateTimeColumn get requestDate => dateTime()(); // Request date

  DateTimeColumn get paymentDate =>
      dateTime().nullable()(); // Actual payment date

  TextColumn get status =>
      text()(); // 'pending', 'approved', 'rejected', 'paid'

  TextColumn get approvedBy => text().nullable()(); // Manager who approved

  DateTimeColumn get approvedAt =>
      dateTime().nullable()(); // Approval timestamp

  TextColumn get rejectionReason => text().nullable()(); // Reason for rejection

  TextColumn get paymentMethod =>
      text().nullable()(); // 'cash', 'bank_transfer', 'check'

  TextColumn get transactionReference =>
      text().nullable()(); // Payment reference

  IntColumn get installmentMonths =>
      integer().nullable()(); // If paid in installments

  RealColumn get monthlyDeduction =>
      real().nullable()(); // Monthly installment amount

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// Payroll table for managing salary payments
@DataClassName('Payroll')
class PayrollTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  TextColumn get payrollPeriod => text()(); // e.g., '2024-01', '2024-01-W1'

  DateTimeColumn get periodStart => dateTime()(); // Payroll period start

  DateTimeColumn get periodEnd => dateTime()(); // Payroll period end

  RealColumn get basicSalary => real()(); // Basic salary

  RealColumn get overtimeHours =>
      real().withDefault(const Constant(0))(); // Overtime hours

  RealColumn get overtimeRate => real().nullable()(); // Overtime hourly rate

  RealColumn get overtimePay =>
      real().withDefault(const Constant(0))(); // Overtime payment

  RealColumn get allowances =>
      real().withDefault(const Constant(0))(); // Total allowances

  RealColumn get deductions =>
      real().withDefault(const Constant(0))(); // Total deductions

  RealColumn get advances =>
      real().withDefault(const Constant(0))(); // Advance deductions

  RealColumn get taxes =>
      real().withDefault(const Constant(0))(); // Tax deductions

  RealColumn get insurance =>
      real().withDefault(const Constant(0))(); // Insurance deductions

  RealColumn get otherDeductions =>
      real().withDefault(const Constant(0))(); // Other deductions

  RealColumn get netSalary => real()(); // Net salary after all deductions

  IntColumn get workingDays =>
      integer().withDefault(const Constant(0))(); // Working days in period

  IntColumn get presentDays =>
      integer().withDefault(const Constant(0))(); // Days present

  IntColumn get absentDays =>
      integer().withDefault(const Constant(0))(); // Days absent

  IntColumn get leaveDays =>
      integer().withDefault(const Constant(0))(); // Leave days

  TextColumn get status =>
      text()(); // 'draft', 'calculated', 'approved', 'paid', 'cancelled'

  DateTimeColumn get paymentDate => dateTime().nullable()(); // Payment date

  TextColumn get paymentMethod =>
      text().nullable()(); // 'cash', 'bank_transfer', 'check'

  TextColumn get transactionReference =>
      text().nullable()(); // Payment reference

  TextColumn get approvedBy => text().nullable()(); // Manager who approved

  DateTimeColumn get approvedAt =>
      dateTime().nullable()(); // Approval timestamp

  TextColumn get notes => text().nullable()(); // Payroll notes

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  // No custom primaryKey needed - using default composite key
}

/// Rewards and penalties table
@DataClassName('RewardPenalty')
class RewardsPenalties extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  TextColumn get type => text()(); // 'reward' or 'penalty'

  TextColumn get category =>
      text()(); // e.g., 'performance', 'attendance', 'behavior'

  TextColumn get title => text()(); // Title/description

  TextColumn get description => text().nullable()(); // Detailed description

  RealColumn get amount =>
      real().nullable()(); // Monetary value (if applicable)

  DateTimeColumn get incidentDate => dateTime()(); // Date of incident

  TextColumn get issuedBy => text()(); // Who issued this

  TextColumn get status => text()(); // 'active', 'appealed', 'cancelled'

  DateTimeColumn get effectiveDate => dateTime()(); // When it takes effect

  DateTimeColumn get expiryDate =>
      dateTime().nullable()(); // When it expires (if applicable)

  TextColumn get evidence =>
      text().nullable()(); // Evidence or documentation reference

  TextColumn get notes => text().nullable()(); // Additional notes

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// Performance reviews table
@DataClassName('PerformanceReview')
class PerformanceReviews extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  TextColumn get reviewPeriod => text()(); // e.g., '2024-Q1', '2024-H1', '2024'

  DateTimeColumn get reviewDate => dateTime()(); // Review date

  TextColumn get reviewerId => text()(); // Who conducted the review

  RealColumn get overallRating => real()(); // Overall rating (1-5)

  RealColumn get workQualityRating => real()(); // Work quality rating (1-5)

  RealColumn get productivityRating => real()(); // Productivity rating (1-5)

  RealColumn get teamworkRating => real()(); // Teamwork rating (1-5)

  RealColumn get punctualityRating => real()(); // Punctuality rating (1-5)

  RealColumn get initiativeRating => real()(); // Initiative rating (1-5)

  TextColumn get strengths => text().nullable()(); // Strengths

  TextColumn get weaknesses => text().nullable()(); // Areas for improvement

  TextColumn get goals => text().nullable()(); // Goals for next period

  TextColumn get recommendations => text().nullable()(); // Recommendations

  TextColumn get employeeComments => text().nullable()(); // Employee feedback

  TextColumn get status =>
      text()(); // 'draft', 'submitted', 'acknowledged', 'completed'

  DateTimeColumn get acknowledgedAt =>
      dateTime().nullable()(); // When employee acknowledged

  DateTimeColumn get nextReviewDate =>
      dateTime().nullable()(); // Next review date

  TextColumn get actionPlan =>
      text().nullable()(); // Action plan for improvement

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// Staff documents table for storing employee documents
@DataClassName('StaffDocument')
class StaffDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // Reference to staff.id

  TextColumn get documentType =>
      text()(); // 'cv', 'contract', 'id_card', 'passport', 'certificate', etc.

  TextColumn get documentName => text()(); // Document name/title

  TextColumn get filePath => text()(); // Path to stored file

  TextColumn get fileName => text()(); // Original file name

  TextColumn get fileType => text()(); // File extension/type

  IntColumn get fileSize => integer()(); // File size in bytes

  DateTimeColumn get issueDate =>
      dateTime().nullable()(); // Document issue date

  DateTimeColumn get expiryDate =>
      dateTime().nullable()(); // Document expiry date

  TextColumn get issuingAuthority =>
      text().nullable()(); // Who issued the document

  TextColumn get documentNumber => text().nullable()(); // Document number/ID

  TextColumn get status =>
      text()(); // 'active', 'expired', 'pending', 'rejected'

  TextColumn get notes => text().nullable()(); // Notes about the document

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}
