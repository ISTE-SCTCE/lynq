import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/task_models.dart';
import '../../core/membership_id.dart';

/// Reads the central ISTE membership intake through an authenticated Edge
/// Function. Registrations are never exposed through the public data API.
class RegistrationService {
  static Future<Map<String, dynamic>> fetchRegistrationData(
    SupabaseClient supabase,
  ) async {
    final response = await supabase.functions.invoke(
      'manage-membership-registrations',
      body: {'action': 'list'},
    );
    final payload = response.data as Map<String, dynamic>;
    final rows = (payload['registrations'] as List<dynamic>? ?? const []);

    final registrations = rows.map((row) {
      final item = row as Map<String, dynamic>;
      final forums = (item['forums'] as List<dynamic>? ?? const [])
          .map((forum) => forum.toString())
          .join(', ');
      final id = item['id'].toString();

      return RegistrationQueueModel(
        // Existing visual components expect an int. The stable UUID remains in
        // rawData and is used for all write actions.
        id: id.hashCode,
        name: item['full_name']?.toString() ?? 'No name',
        email: item['email']?.toString() ?? '',
        phone: item['phone']?.toString(),
        branch: item['branch']?.toString(),
        year: item['academic_year']?.toString(),
        membershipType:
            '₹${item['membership_fee'] ?? 0} (${forums.isEmpty ? 'No forums' : forums})',
        paymentStatus: 'Receipt submitted',
        source: 'ISTE website',
        status: item['status']?.toString() ?? 'pending',
        createdAt: item['created_at'] != null
            ? DateTime.tryParse(item['created_at'].toString())
            : null,
        rawData: {
          'central_registration_id': id,
          'total_amount': item['total_amount'],
          'transaction_id': item['transaction_id'],
          'forums': forums,
        },
      );
    }).toList();

    final grouped = <String, List<RegistrationQueueModel>>{
      'Pending': registrations
          .where((item) => item.status == 'pending')
          .toList(),
      'Approved': registrations
          .where((item) => item.status == 'approved')
          .toList(),
      'Rejected': registrations
          .where((item) => item.status == 'rejected')
          .toList(),
    };

    return {
      'totalMembers': payload['totalMembers'] as int? ?? 0,
      'grouped': grouped,
    };
  }

  static Future<void> reviewRegistration(
    SupabaseClient supabase, {
    required String registrationId,
    required String status,
    String? membershipId,
  }) async {
    if (status != 'approved' && status != 'rejected') {
      throw ArgumentError('Unsupported review status.');
    }
    final officialId = normalizeMembershipId(membershipId ?? '');
    if (status == 'approved' && !isOfficialMembershipId(officialId)) {
      throw ArgumentError(
        'Enter the official membership ID, for example KE104010.',
      );
    }
    final response = await supabase.functions.invoke(
      'manage-membership-registrations',
      body: {
        'action': 'review',
        'registrationId': registrationId,
        'status': status,
        if (status == 'approved') 'membershipId': officialId,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('The review was not saved. Please try again.');
    }
  }
}
