import '../lib/core/membership_id.dart';

// Dependency-free check; also runnable while the shared package is unavailable.
void main() {
  for (final id in ['KE104000', 'KE104010', 'KE104999', ' ke104035 ']) {
    if (!isOfficialMembershipId(id)) throw StateError('Rejected valid ID: $id');
  }
  for (final id in [
    '',
    'ISTE-2026-0548',
    'KE10401',
    'KE1040100',
    'KE 104010',
    'KE104ABC',
  ]) {
    if (isOfficialMembershipId(id))
      throw StateError('Accepted invalid ID: $id');
  }
  if (normalizeMembershipId(' ke104010 ') != 'KE104010') {
    throw StateError('Normalization failed');
  }
  print('Membership ID checks passed (10 validation cases + normalization).');
}
