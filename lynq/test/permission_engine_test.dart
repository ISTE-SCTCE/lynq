import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynq/core/constants.dart';
import 'package:lynq/core/permission_engine.dart';
import 'package:lynq/models/user_model.dart';
import 'package:lynq/models/folder_model.dart';

void main() {
  late Map<String, dynamic> matrix;

  setUpAll(() {
    final file = File('../shared/permission_matrix.json');
    if (!file.existsSync()) {
      fail('Shared permission matrix not found at: ${file.absolute.path}');
    }
    matrix = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('Role Parsing Tests', () {
    test('Verifies role parsing rules from JSON matrix', () {
      final roleTests = matrix['role_tests'] as List;
      for (var testCase in roleTests) {
        final input = testCase['input'] as String?;
        final expectedStr = testCase['expected'] as String;
        
        final expected = AppRole.values.firstWhere((e) => e.name == expectedStr);
        final parsed = AppRole.fromString(input);
        
        expect(parsed, expected, reason: 'Failed parsing "$input", expected $expectedStr');
      }
    });
  });

  group('Global Permissions Tests', () {
    test('Verifies global permission cases', () {
      final permTests = matrix['permission_tests'] as List;
      for (var testCase in permTests) {
        final description = testCase['description'] as String;
        final userData = testCase['user'] as Map<String, dynamic>;
        final expected = testCase['expected'] as Map<String, dynamic>;

        final user = UserModel(
          id: userData['id'] as String,
          name: userData['name'] as String,
          email: userData['email'] as String,
          role: userData['role'] as String,
          isSudo: userData['is_sudo'] as bool? ?? false,
          status: userData['status'] as String? ?? 'active',
          suspendedUntil: userData['suspended_until'] != null ? DateTime.parse(userData['suspended_until'] as String) : null,
        );

        final engine = PermissionEngine(user: user);

        if (expected.containsKey('isSuspended')) {
          expect(engine.isSuspended, expected['isSuspended'], reason: '$description: isSuspended mismatch');
        }
        if (expected.containsKey('isEffectivelyTier1')) {
          expect(engine.isEffectivelyTier1, expected['isEffectivelyTier1'], reason: '$description: isEffectivelyTier1 mismatch');
        }

        // Test dynamic permission getters
        expected.forEach((key, val) {
          if (key == 'isSuspended' || key == 'isEffectivelyTier1') return;
          
          // Use reflection or standard manual mappings
          bool actualVal = false;
          switch (key) {
            case 'canAddMembers': actualVal = engine.canAddMembers; break;
            case 'canRemoveMembers': actualVal = engine.canRemoveMembers; break;
            case 'canEditMembers': actualVal = engine.canEditMembers; break;
            case 'canAssignRoles': actualVal = engine.canAssignRoles; break;
            case 'canManageFolders': actualVal = engine.canManageFolders; break;
            case 'canManageGlobalPermissions': actualVal = engine.canManageGlobalPermissions; break;
            case 'canManageFolderPermissions': actualVal = engine.canManageFolderPermissions; break;
            case 'canManagePermissions': actualVal = engine.canManagePermissions; break;
            case 'canCreateEvents': actualVal = engine.canCreateEvents; break;
            case 'canReadReports': actualVal = engine.canReadReports; break;
            case 'canUploadReports': actualVal = engine.canUploadReports; break;
            case 'canViewTotalBudget': actualVal = engine.canViewTotalBudget; break;
            case 'canAccessScopedBudget': actualVal = engine.canAccessScopedBudget; break;
            case 'canViewMembers': actualVal = engine.canViewMembers; break;
            case 'canRequestBudget': actualVal = engine.canRequestBudget; break;
            case 'canManageBudget': actualVal = engine.canManageBudget; break;
            case 'canViewInternalAnnouncements': actualVal = engine.canViewInternalAnnouncements; break;
            case 'canManageAnnouncements': actualVal = engine.canManageAnnouncements; break;
            case 'canOverride': actualVal = engine.canOverride; break;
            case 'canAccessChat': actualVal = engine.canAccessChat; break;
            case 'canApproveBudget': actualVal = engine.canApproveBudget; break;
          }
          expect(actualVal, val, reason: '$description: Permission "$key" mismatch');
        });
      }
    });
  });

  group('Folder Permissions Tests', () {
    test('Verifies folder permission cases', () {
      final folderTests = matrix['folder_permission_tests'] as List;
      for (var testCase in folderTests) {
        final description = testCase['description'] as String;
        final userData = testCase['user'] as Map<String, dynamic>;
        final membershipsData = testCase['memberships'] as List;
        final permissionsData = testCase['permissions'] as List;
        final checks = testCase['checks'] as List;

        final user = UserModel(
          id: userData['id'] as String,
          name: userData['name'] as String,
          email: userData['email'] as String,
          role: userData['role'] as String,
          isSudo: userData['is_sudo'] as bool? ?? false,
          status: userData['status'] as String? ?? 'active',
        );

        final memberships = membershipsData.map((m) => FolderMemberModel(
          id: 0,
          folderId: m['folder_id'] as int,
          userId: user.id,
          folderRole: m['folder_role'] as String,
        )).toList();

        final permissionsMap = <int, List<FolderPermissionModel>>{};
        for (var p in permissionsData) {
          final fid = p['folder_id'] as int;
          permissionsMap.putIfAbsent(fid, () => []).add(FolderPermissionModel(
            id: 0,
            folderId: fid,
            feature: p['feature'] as String,
            allowed: p['allowed'] as bool,
          ));
        }

        final engine = PermissionEngine(
          user: user,
          userFolderMemberships: memberships,
          folderPermissions: permissionsMap,
        );

        for (var check in checks) {
          final fid = check['folder_id'] as int;
          final expected = check['expected'] as bool;
          
          if (check.containsKey('check_type') && check['check_type'] == 'canManageMembersInFolder') {
            expect(engine.canManageMembersInFolder(fid), expected, reason: '$description: canManageMembersInFolder mismatch');
          } else {
            final feature = check['feature'] as String;
            expect(engine.canDoInFolder(fid, feature), expected, reason: '$description: canDoInFolder("$feature") mismatch');
          }
        }
      }
    });
  });
}
