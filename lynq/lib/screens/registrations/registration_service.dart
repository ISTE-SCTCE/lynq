import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../models/task_models.dart';

class RegistrationService {
  static const List<Map<String, dynamic>> _cachedExcelData = [
    {"Timestamp":"2026-04-09T06:21:00.000Z","Name":"Gayathri AS ","DOB":"2007-02-09T18:30:00.000Z","Year":1,"Branch":"Electronics and Communication","Phone":9539338741,"Email":"asgayathri48@gmail.com","Membership":649,"TransactionID":1604247191,"Forum":"None Selected"},
    {"Timestamp":"2026-04-11T08:15:15.000Z","Name":"Parthasarathy","DOB":"2005-06-05T18:30:00.000Z","Year":2,"Branch":"Mechanical Engineering","Phone":8590467936,"Email":"parthasarathy03062005@gmail.com","Membership":649,"TransactionID":61013161514,"Forum":"None Selected"},
    {"Timestamp":"2026-04-11T16:43:52.000Z","Name":"Viswajith S S","DOB":"2006-08-17T18:30:00.000Z","Year":2,"Branch":"Electronics and Communication","Phone":6238969245,"Email":"viswajithss18@gmail.com","Membership":1199,"TransactionID":"CICAgNicmPmZBA","Forum":"EXIS Forum (149)"},
    {"Timestamp":"2026-04-12T04:30:10.000Z","Name":"Sreeram PS","DOB":"2006-09-15T18:30:00.000Z","Year":1,"Branch":"Electronics and Communication","Phone":8848360097,"Email":"sreeramps1609@gmail.com","Membership":649,"TransactionID":646857101286,"Forum":"EXIS Forum (149)"},
    {"Timestamp":"2026-04-17T12:31:13.000Z","Name":"Ganesh G","DOB":"2006-05-30T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":9446967119,"Email":"ganeshgopal3106@gmail.com","Membership":649,"TransactionID":610751875169,"Forum":"BITS Forum (129)"},
    {"Timestamp":"2026-04-18T11:12:25.000Z","Name":"ABHINANTH S NATH","DOB":"2006-03-27T18:30:00.000Z","Year":2,"Branch":"Electronics and Communication","Phone":7012826799,"Email":"abinanth@gmail.com","Membership":649,"TransactionID":646583738939,"Forum":"None Selected"},
    {"Timestamp":"2026-04-18T11:14:43.000Z","Name":"CHINAMAYI","DOB":"2006-03-27T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":9567440301,"Email":"chinmayi@gmail.com","Membership":649,"TransactionID":610126297897,"Forum":"None Selected"},
    {"Timestamp":"2026-04-21T05:32:42.000Z","Name":"ADARSH P VINOD","DOB":"2006-01-27T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":8547313055,"Email":"adarshcr4@gmail.com","Membership":1199,"TransactionID":611163459768,"Forum":"SWaS Forum (299)"},
    {"Timestamp":"2026-04-22T16:02:51.000Z","Name":"Manupriya prasad ","DOB":"2007-04-17T18:30:00.000Z","Year":1,"Branch":"Mechanical and Automobile Engineering","Phone":8075619064,"Email":"manupriyaa7prasad@gmail.com","Membership":1499,"TransactionID":611283130594,"Forum":"SWaS Forum (299), TORQ Forum (129)"},
    {"Timestamp":"2026-04-23T03:36:20.000Z","Name":"Arjun S","DOB":"2006-12-17T18:30:00.000Z","Year":2,"Branch":"Mechanical Engineering","Phone":9947584831,"Email":"arjuns8267@gmail.com","Membership":649,"TransactionID":90602688981,"Forum":"TORQ Forum (129)"},
    {"Timestamp":"2026-04-23T07:34:32.000Z","Name":"MOHAMMED FARHAN","DOB":"2006-07-26T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":7907726056,"Email":"farhanmohammed2706@gmail.com","Membership":649,"TransactionID":611309859624,"Forum":"None Selected"},
    {"Timestamp":"2026-04-23T08:13:56.000Z","Name":"Joneth Jills","DOB":"2006-05-29T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":8848615115,"Email":"jonethjillsff@gmail.com","Membership":649,"TransactionID":647975757708,"Forum":"None Selected"},
    {"Timestamp":"2026-04-23T15:52:56.000Z","Name":"THANU SREE N","DOB":"2006-08-14T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":7306961915,"Email":"thanusreenubi@gmail.com","Membership":649,"TransactionID":611347302744,"Forum":"None Selected"},
    {"Timestamp":"2026-05-06T09:47:29.000Z","Name":"Thejas Krishna","DOB":"2006-12-04T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":8129047109,"Email":"thejask9495@gmail.com","Membership":649,"TransactionID":612601555589,"Forum":"None Selected"},
    {"Timestamp":"2026-05-13T05:33:59.000Z","Name":"Ashishna Shahul S ","DOB":"2005-11-24T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":6374128384,"Email":"ars.suru786@gmail.com","Membership":1199,"TransactionID":613354433613,"Forum":"SWaS Forum (299), BITS Forum (129)"}
  ];

  static Future<Map<String, dynamic>> fetchRegistrationData(SupabaseClient supabase) async {
    // 0. Fetch total member count
    final int totalMembers = await supabase.from('profiles').count(CountOption.exact);

    // 1. Fetch live queue from Supabase
    final data = await supabase
        .from('registration_queue')
        .select()
        .order('created_at', ascending: false);

    final list = (data as List)
        .map((e) => RegistrationQueueModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // 2. Fetch live data from Google Sheets Macro
    List<RegistrationQueueModel> sheetsList = [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(Uri.parse('https://script.google.com/macros/s/AKfycbwSaurzyOEbeJoKTVgCqVhy-esPWq2HpU6UOtfK_7Ds5p7Kisz736_m2k6UnwnWP2Jg/exec'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final List<dynamic> decoded = jsonDecode(responseBody);
        sheetsList = decoded.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value as Map<String, dynamic>;
          return RegistrationQueueModel(
            id: 9000 + idx,
            name: (item['Name'] as String?)?.trim() ?? 'No Name',
            email: (item['Email'] as String?)?.trim() ?? '',
            phone: item['Phone'] != null ? item['Phone'].toString() : '',
            branch: item['Branch'] as String? ?? '',
            year: item['Year'] != null ? item['Year'].toString() : '',
            membershipType: '₹${item["Membership "] ?? item["Membership"] ?? "649"} (${item["Forum"] ?? "None"})',
            paymentStatus: 'paid',
            rollNumber: item['TransactionID'] != null ? item['TransactionID'].toString() : '',
            source: 'Google Sheet Excel',
            status: 'excel_intake',
            createdAt: item['Timestamp'] != null ? DateTime.tryParse(item['Timestamp']) : DateTime.now(),
            rawData: {
              'raw_forum': item['Forum'] ?? 'None Selected',
              'raw_membership': (item['Membership '] ?? item['Membership'] ?? '649').toString(),
            },
          );
        }).toList();
      } else {
        throw Exception("Sheets fetch non-200");
      }
    } catch (e) {
      debugPrint('Mobile Sheet fetch error, loading cache fallback: $e');
      sheetsList = _cachedExcelData.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        return RegistrationQueueModel(
          id: 9000 + idx,
          name: (item['Name'] as String?)?.trim() ?? 'No Name',
          email: (item['Email'] as String?)?.trim() ?? '',
          phone: item['Phone'] != null ? item['Phone'].toString() : '',
          branch: item['Branch'] as String? ?? '',
          year: item['Year'] != null ? item['Year'].toString() : '',
          membershipType: '₹${item["Membership"] ?? "649"} (${item["Forum"] ?? "None"})',
          paymentStatus: 'paid',
          rollNumber: item['TransactionID'] != null ? item['TransactionID'].toString() : '',
          source: 'Google Sheet Excel',
          status: 'excel_intake',
          createdAt: item['Timestamp'] != null ? DateTime.tryParse(item['Timestamp']) : DateTime.now(),
          rawData: {
            'raw_forum': item['Forum'] ?? 'None Selected',
            'raw_membership': (item['Membership'] ?? '649').toString(),
          },
        );
      }).toList();
    }

    final grouped = {
      'Pending': list.where((r) => r.status == 'pending').toList(),
      'Payment': list.where((r) => r.status == 'payment_pending').toList(),
      'Approved': list.where((r) => r.status == 'approved').toList(),
      'Rejected': list.where((r) => r.status == 'rejected').toList(),
      'Excel Intake': sheetsList,
    };

    return {
      'totalMembers': totalMembers,
      'grouped': grouped,
    };
  }
}
