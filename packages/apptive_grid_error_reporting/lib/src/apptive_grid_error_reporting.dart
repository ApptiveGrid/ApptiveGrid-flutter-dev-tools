import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:apptive_grid_core/apptive_grid_core.dart';
import 'package:apptive_grid_error_reporting/src/keys.dart' as keys;
import 'package:apptive_grid_error_reporting/src/model/log_entry.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_io/io.dart' as uio;

/// A reporting tool for saving error events in ApptiveGrid
class ApptiveGridErrorReporting {
  ApptiveGridErrorReporting._({
    required this.reportingForm,
    required this.project,
    required this.maxLogEntries,
    required this.ignoreError,
    required this.formatError,
    required this.sendErrors,
    required this.avoidDuplicatePerSession,
    required ApptiveGridClient client,
  }) : _client = client;

  /// Creates a ApptiveGridErrorReporting
  /// Error reported through [reportError] are send using an ApptiveGridForm obtained by [reportingForm]
  /// [project] is used to identify this App Project so you can differentiate certain flavors or projects in the same ApptiveGrid Space
  factory ApptiveGridErrorReporting({
    required Uri reportingForm,
    required String project,
    int maxLogEntries = 25,
    bool Function(dynamic)? ignoreError,
    String Function(Object)? formatError,
    bool? avoidDuplicatePerSession,
    bool sendErrors = kReleaseMode,
    ApptiveGridClient? client,
  }) {
    final reporting = ApptiveGridErrorReporting._(
      reportingForm: reportingForm,
      project: project,
      maxLogEntries: maxLogEntries,
      ignoreError: ignoreError ?? (_) => false,
      formatError: formatError ?? (error) => error._errorName,
      sendErrors: sendErrors,
      avoidDuplicatePerSession: avoidDuplicatePerSession ?? false,
      client: client ?? ApptiveGridClient(), // coverage:ignore-line
    );

    reporting._init();

    return reporting;
  }

  /// Link to the Form that reports the Errors
  final Uri reportingForm;

  /// Identifier for the Project
  final String project;

  /// Override this to ignore specific errors. The tool will never report 401 Responses
  final bool Function(dynamic) ignoreError;

  /// Format the Default Error Description. By default this will format [Response] to show you the body and status code otherwise fall back to just `toString()` of the error
  final String Function(Object) formatError;

  /// The Max Length of Log entries that are send.
  /// Defaults to 25
  /// Note that sending an error successfully will always clear the current Log
  final int maxLogEntries;

  /// A flag if the errors should be send. Set this to false if errors should not be send
  /// Defaults to [kReleaseMode]
  bool sendErrors;

  /// Determines if the tool should avoid sending the same error multiple times per session
  final bool avoidDuplicatePerSession;

  final List<
          (DateTime, String errorName, StackTrace? stackTrace, String? message)>
      _mutedErrors = [];
  final List<
          (DateTime, String errorName, StackTrace? stackTrace, String? message)>
      _sendErrors = [];

  late final String? _appVersion;
  late final String? _os;
  late final String? _osVersion;
  late final String? _locale;

  /// Optional Stage Parameter.
  /// Set this to save which stage an error occurred on
  String? stage;

  final List<LogEntry> _log = [];

  final ApptiveGridClient _client;

  final _setupCompleter = Completer();

  /// A future that finishes once the initialization is completed
  @visibleForTesting
  Future get isInitialized => _setupCompleter.future;

  Future<void> _init() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    _os = uio.Platform.operatingSystem;
    _osVersion = uio.Platform.operatingSystemVersion;
    _locale = uio.Platform.localeName;

    _setupCompleter.complete();
  }

  /// Log [message]
  /// The log will hold a maximum of [maxLogEntries] entries and will be cleared when send to ApptiveGrid
  void log(String message) {
    if (_log.length > maxLogEntries) {
      _log.removeRange(0, _log.length - maxLogEntries);
    }

    _log.add(LogEntry(time: DateTime.now(), message: message));
  }

  /// Reports [error] to ApptiveGrid
  /// Provide [stackTrace] and [message] to get more information when looking at the Errors on ApptiveGrid
  Future<void> reportError(
    Object error, {
    StackTrace? stackTrace,
    String? message,
  }) async {
    if (!_ignoreError(error)) {
      final reportingDate = DateTime.now();
      await _setupCompleter.future;
      final errorName = formatError(error);
      if (avoidDuplicatePerSession &&
          _sendErrors.firstWhereOrNull((report) {
                // coverage:ignore-start
                final (_, mutedErrorName, _, mutedMessage) = report;
                // coverage:ignore-end

                return mutedErrorName == errorName && mutedMessage == message;
              }) !=
              null) {
        _mutedErrors.add((reportingDate, errorName, stackTrace, message));
        return;
      }
      try {
        if (sendErrors) {
          final formData = await _client.loadForm(
            uri: reportingForm.replace(
              path: reportingForm.path.replaceAll(RegExp('/r/'), '/a/'),
            ),
          );

          Uint8List? logFile;
          Uint8List? stackTraceFile;
          Uint8List? mutedErrorsFile;

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
            if (_mutedErrors.isNotEmpty)
              _createMutedFile().then((file) {
                mutedErrorsFile = file;
              }),
          ]);

          // Send Data
          await _fillForm(
            formData: formData,
            error: error,
            message: message,
            logFile: logFile,
            stackTrace: stackTraceFile,
            mutedErrors: mutedErrorsFile,
          );

          await _client.submitForm(
            formData.links[ApptiveLinkType.submit]!,
            formData,
          );
          _sendErrors.add((reportingDate, errorName, stackTrace, message));
          debugPrint('AGErrorReporting: $errorName reported');
        } else {
          debugPrint(
            'AGErrorReporting: Error $errorName not sent. sendErrors is false.',
          );
        }
        _log.removeWhere((element) => element.time.isBefore(reportingDate));
        _mutedErrors
            .removeWhere((element) => element.$1.isBefore(reportingDate));
      } catch (e) {
        log('Could not Report Error: $errorName. Cause: ${formatError(e)}');
        debugPrint(
          'AGErrorReport: Could not Report Error: $errorName. Cause: ${formatError(e)}',
        );
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

  Future<Uint8List> _createMutedFile() async {
    final port = ReceivePort();

    Isolate.spawn(_createMutedFileIsolate, [port.sendPort, _mutedErrors]);

    return await port.first as Uint8List;
  }

  static Future<void> _createMutedFileIsolate(List<Object> args) async {
    final port = args[0] as SendPort;
    final mutedFiles = args[1] as List<
        (DateTime, Object error, StackTrace? stackTrace, String? message)>;

    final stringBuffer = StringBuffer();
    for (final (time, name, stackTrace, message) in mutedFiles) {
      stringBuffer.writeln(time.toIso8601String());
      stringBuffer.writeln('Ignored: $name | Message: $message');
      stringBuffer.writeln(stackTrace.toString());
      stringBuffer.writeln('-' * 30);
    }

    final bytes = utf8.encode(stringBuffer.toString());

    Isolate.exit(port, bytes);
  }

  Future<void> _fillForm({
    required FormData formData,
    required Object error,
    required String? message,
    required Uint8List? logFile,
    required Uint8List? stackTrace,
    required Uint8List? mutedErrors,
  }) async {
    formData.fillValue(key: keys.project, value: project);
    formData.fillValue(key: keys.name, value: formatError(error));
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
        byteData: stackTrace,
        attachment: stackAttachment,
      );
      (formData.components!
              .firstWhere((element) => element.field.key == keys.attachments)
              .data as AttachmentDataEntity)
          .value
          ?.add(stackAttachment);
    }

    if (mutedErrors != null) {
      final mutedAttachment =
          await _client.attachmentProcessor.createAttachment('mutedErrors.txt');
      formData.attachmentActions[mutedAttachment] = AddAttachmentAction(
        byteData: mutedErrors,
        attachment: mutedAttachment,
      );
      (formData.components!
              .firstWhere((element) => element.field.key == keys.attachments)
              .data as AttachmentDataEntity)
          .value
          ?.add(mutedAttachment);
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
  String get _errorName {
    if (this is http.Response) {
      return 'Response (${(this as http.Response).statusCode})\n${(this as http.Response).body})';
    }
    return toString();
  }
}
