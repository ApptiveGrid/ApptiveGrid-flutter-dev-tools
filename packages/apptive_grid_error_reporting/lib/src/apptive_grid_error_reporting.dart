import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:apptive_grid_core/apptive_grid_core.dart';
import 'package:apptive_grid_error_reporting/src/keys.dart' as keys;
import 'package:apptive_grid_error_reporting/src/model/log_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_io/io.dart' as uio;

class ApptiveGridErrorReporting {
  ApptiveGridErrorReporting._({
    required this.reportingForm,
    required this.project,
    required this.maxLogEntries,
    required this.httpClient,
    required this.ignoreError,
    required this.sendErrors,
  });

  factory ApptiveGridErrorReporting({
    required Uri reportingForm,
    required String project,
    int maxLogEntries = 25,
    http.Client? httpClient,
    bool Function(dynamic)? ignoreError,
    bool sendErrors = true,
  }) {
    final reporting = ApptiveGridErrorReporting._(
      reportingForm: reportingForm,
      project: project,
      maxLogEntries: maxLogEntries,
      httpClient: httpClient,
      ignoreError: ignoreError ?? (_) => false,
      sendErrors: sendErrors,
    );

    reporting._init();

    return reporting;
  }

  final Uri reportingForm;
  final String project;
  final bool Function(dynamic) ignoreError;
  final int maxLogEntries;
  final http.Client? httpClient;
  bool sendErrors = true;

  late final String? _appVersion;
  late final String? _os;
  late final String? _osVersion;
  late final String? _locale;

  String? stage;

  final List<LogEntry> _log = [];

  final _client = ApptiveGridClient();

  final _setupCompleter = Completer();

  Future<void> _init() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    _os = uio.Platform.operatingSystem;
    _osVersion = uio.Platform.operatingSystemVersion;
    _locale = uio.Platform.localeName;

    _setupCompleter.complete();
  }

  void log(String message) {
    if (_log.length > maxLogEntries) {
      _log.removeRange(0, _log.length - maxLogEntries);
    }

    _log.add(LogEntry(time: DateTime.now(), message: message));
  }

  Future<void> reportError(Object error,
      {StackTrace? stackTrace, String? message}) async {
    if (!_ignoreError(error)) {
      final reportingDate = DateTime.now();
      await _setupCompleter.future;
      try {
        if (sendErrors) {
          final formData = await _client.loadForm(
              uri: reportingForm.replace(
                  path: reportingForm.path.replaceAll(RegExp('/r/'), '/a/')));

          Uint8List? logFile;
          Uint8List? stackTraceFile;

          // Prepare Data
          await Future.wait([
            if (_log.isNotEmpty)
              _createLogFile().then((file) {
                logFile = file;
              }),
            if (stackTrace != null)
              _createStackTraceFile(stackTrace).then((file) {
                stackTraceFile = file;
              }),
          ]);

          // Send Data
          await _fillForm(
            formData: formData,
            reportingDate: reportingDate,
            error: error,
            message: message,
            logFile: logFile,
            stackTrace: stackTraceFile,
          );

          await _client.submitForm(
              formData.links[ApptiveLinkType.submit]!, formData);
        } else {
          debugPrint('AGErrorReporting: Error not sent. sendErrors is false.');
        }
        _log.removeWhere((element) => element.time.isBefore(reportingDate));
        debugPrint('AGErrorReporting: ${error.errorName} reported');
      } catch (e) {
        log('Could not Report Error: ${error.errorName}. Cause: ${e.errorName}');
        debugPrint(
            'AGErrorReport: Could not Report Error: ${error.errorName}. Cause: ${e.errorName}');
      }
    }
  }

  bool _ignoreError(Object error) {
    if (error is http.Response) {
      if (error.statusCode == 401) {
        return true;
      }
    }

    return ignoreError(error);
  }

  Future<Uint8List> _createLogFile() async {
    final port = ReceivePort();

    Isolate.spawn(_createLogFileIsolate, [port.sendPort, _log]);

    return await port.first as Uint8List;
  }

  static Future<void> _createLogFileIsolate(List<Object> args) async {
    final port = args[0] as SendPort;
    final log = args[1] as List<LogEntry>;

    final logString = log.reversed.map((e) => e.toString()).join('\n');

    final logBytes = utf8.encode(logString);

    Isolate.exit(port, logBytes);
  }

  Future<Uint8List> _createStackTraceFile(StackTrace stackTrace) async {
    final port = ReceivePort();

    Isolate.spawn(_createStackTraceFileIsolate, [port.sendPort, stackTrace]);

    return await port.first as Uint8List;
  }

  static Future<void> _createStackTraceFileIsolate(List<Object> args) async {
    final port = args[0] as SendPort;
    final stackTrace = args[1] as StackTrace;

    final stackBytes = utf8.encode(stackTrace.toString());

    Isolate.exit(port, stackBytes);
  }

  Future<void> _fillForm({
    required FormData formData,
    required DateTime reportingDate,
    required Object error,
    required String? message,
    required Uint8List? logFile,
    required Uint8List? stackTrace,
  }) async {
    formData.fillValue(key: keys.project, value: project);
    formData.fillValue(key: keys.name, value: error.errorName);
    formData.fillValue(key: keys.time, value: reportingDate);
    formData.fillValue(key: keys.appVersion, value: _appVersion);
    formData.fillValue(key: keys.os, value: _os);
    formData.fillValue(key: keys.osVersion, value: _osVersion);
    formData.fillValue(key: keys.stage, value: stage);
    formData.fillValue(key: keys.locale, value: _locale);
    formData.fillValue(key: keys.message, value: message);

    if (logFile != null) {
      final logAttachment =
          await _client.attachmentProcessor.createAttachment('log.txt');
      formData.attachmentActions[logAttachment] =
          AddAttachmentAction(byteData: logFile, attachment: logAttachment);
      (formData.components!
              .firstWhere((element) => element.field.key == keys.attachments)
              .data as AttachmentDataEntity)
          .value
          ?.add(logAttachment);
    }

    if (stackTrace != null) {
      final stackAttachment =
          await _client.attachmentProcessor.createAttachment('stackTrace.txt');
      formData.attachmentActions[stackAttachment] = AddAttachmentAction(
          byteData: stackTrace, attachment: stackAttachment);
      (formData.components!
              .firstWhere((element) => element.field.key == keys.attachments)
              .data as AttachmentDataEntity)
          .value
          ?.add(stackAttachment);
    }
  }
}

extension _FormDataX on FormData {
  void fillValue({required String key, required Object? value}) {
    if (components?.where((element) => element.field.key == key).isNotEmpty ==
        true) {
      final component =
          components!.firstWhere((element) => element.field.key == key);

      component.data.value = value;
    }
  }
}

extension _ErrorX on Object {
  String get errorName {
    if (this is http.Response) {
      return 'Response (${(this as http.Response).statusCode})\n${(this as http.Response).body})';
    }
    return toString();
  }
}
