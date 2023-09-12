import 'dart:convert';

import 'package:apptive_grid_core/apptive_grid_core.dart';
import 'package:apptive_grid_error_reporting/apptive_grid_error_reporting.dart';
import 'package:apptive_grid_error_reporting/src/keys.dart' as keys;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../tools/mocks.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  late ApptiveGridErrorReporting errorReporting;
  late ApptiveGridClient client;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'appName',
      packageName: 'packageName',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'buildSignature',
    );
    registerFallbackValue(fullForm);
    registerFallbackValue(Uri());
    registerFallbackValue(ApptiveLink(uri: Uri(), method: 'get'));
  });

  setUp(() {
    client = MockApptiveGridClient();
  });

  final reportingForm = Uri(path: '/path/to/Form');

  group('Send', () {
    setUp(() {
      when(() => client.loadForm(uri: reportingForm))
          .thenAnswer((invocation) async => fullForm);

      when(
        () => client.submitForm(fullForm.links[ApptiveLinkType.submit]!, any()),
      ).thenAnswer((invocation) async => Response('body', 201));
    });
    test('Send Error', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      const dummyError = 'Error';

      await errorReporting.reportError(dummyError);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      expect(
        sendForm.components!
            .firstWhere((element) => element.field.key == keys.name)
            .data
            .value,
        equals(dummyError),
      );
      expect(
        sendForm.components!
            .firstWhere((element) => element.field.key == keys.appVersion)
            .data
            .value,
        equals('1.0.0+1'),
      );
      expect(
        sendForm.components!
            .firstWhere((element) => element.field.key == keys.os)
            .data
            .value,
        isNot(isNull),
      );
      expect(
        sendForm.components!
            .firstWhere((element) => element.field.key == keys.osVersion)
            .data
            .value,
        isNot(isNull),
      );
    });
    test('Send Stage', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      errorReporting.stage = 'customStage';
      const dummyError = 'Error';

      await errorReporting.reportError(dummyError);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      expect(
        sendForm.components!
            .firstWhere((element) => element.field.key == keys.stage)
            .data
            .value,
        equals('customStage'),
      );
    });
    test('Send Message', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      const dummyError = 'Error';
      const message = 'Custom Message';

      await errorReporting.reportError(dummyError, message: 'Custom Message');

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      expect(
        sendForm.components!
            .firstWhere((element) => element.field.key == keys.message)
            .data
            .value,
        equals(message),
      );
    });
    test('Send Log', () async {
      final processor = MockAttachmentProcessor();
      when(() => client.attachmentProcessor).thenReturn(processor);

      when(() => processor.createAttachment('log.txt')).thenAnswer(
        (invocation) async => Attachment(
          name: 'log.txt',
          url: Uri(path: '/log/attachment'),
          type: 'text/plain',
        ),
      );
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      const logEntry = 'Log Entry';

      errorReporting.log(logEntry);

      const dummyError = 'Error';

      await errorReporting.reportError(dummyError);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final logBytes =
          (sendForm.attachmentActions.values.first as AddAttachmentAction)
              .byteData;

      final logString = utf8.decode(logBytes!);

      expect(logString, contains(logEntry));
    });

    test('Send StackTrace', () async {
      final processor = MockAttachmentProcessor();
      when(() => client.attachmentProcessor).thenReturn(processor);

      when(() => processor.createAttachment('stackTrace.txt')).thenAnswer(
        (invocation) async => Attachment(
          name: 'stackTrace.txt',
          url: Uri(path: '/stackTrace/attachment'),
          type: 'text/plain',
        ),
      );

      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      final stackTrace = StackTrace.current;

      const dummyError = 'Error';

      await errorReporting.reportError(dummyError, stackTrace: stackTrace);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final stackTraceBytes =
          (sendForm.attachmentActions.values.first as AddAttachmentAction)
              .byteData;

      final stackTraceString = utf8.decode(stackTraceBytes!);

      expect(stackTraceString, equals(stackTrace.toString()));
    });
  });

  group('Log', () {
    setUp(() {
      when(() => client.loadForm(uri: reportingForm))
          .thenAnswer((invocation) async => fullForm);

      when(
        () => client.submitForm(fullForm.links[ApptiveLinkType.submit]!, any()),
      ).thenAnswer((invocation) async => Response('body', 201));
    });
    test('Log has Max size', () async {
      final processor = MockAttachmentProcessor();
      when(() => client.attachmentProcessor).thenReturn(processor);

      when(() => processor.createAttachment('log.txt')).thenAnswer(
        (invocation) async => Attachment(
          name: 'log.txt',
          url: Uri(path: '/log/attachment'),
          type: 'text/plain',
        ),
      );
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        maxLogEntries: 10,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      for (int i = 0; i < 20; i++) {
        errorReporting.log('LogEntry$i');
      }

      const dummyError = 'Error';

      await errorReporting.reportError(dummyError);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final logBytes =
          (sendForm.attachmentActions.values.first as AddAttachmentAction)
              .byteData;

      final logString = utf8.decode(logBytes!);

      for (int i = 0; i < 20; i++) {
        final logEntry = 'LogEntry$i\n';
        if (i < 10) {
          expect(logString, isNot(contains(logEntry)));
        } else {
          expect(logString, contains(logEntry));
        }
      }
    });
  });

  group('Formatting', () {
    setUp(() {
      when(() => client.loadForm(uri: reportingForm))
          .thenAnswer((invocation) async => fullForm);

      when(
        () => client.submitForm(fullForm.links[ApptiveLinkType.submit]!, any()),
      ).thenAnswer((invocation) async => Response('body', 201));
    });
    test('Formats Response to Include Body and StatusCode', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      final error = Response('Response Body', 500);

      await errorReporting.reportError(error);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final sendName = sendForm.components!
          .firstWhere((element) => element.field.key == keys.name)
          .data
          .value!;

      expect(
        sendName,
        allOf(contains(error.body), contains(error.statusCode.toString())),
      );
    });

    test('Use custom Formatter', () async {
      const dummyFormat = 'dummyFormat';
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        formatError: (_) => dummyFormat,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      final error = Response('Response Body', 500);

      await errorReporting.reportError(error);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final sendName = sendForm.components!
          .firstWhere((element) => element.field.key == keys.name)
          .data
          .value!;

      expect(sendName, dummyFormat);
    });
  });

  group('Skipping', () {
    test('Do not send does not send/load', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: false,
      );

      await errorReporting.isInitialized;

      const dummyError = 'error';

      await errorReporting.reportError(dummyError);

      verifyNever(() => client.loadForm(uri: any(named: 'uri')));
      verifyNever(() => client.submitForm(any(), any()));
    });

    test('Skips 401 Error', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      final skipping401Error = Response('body', 401);

      await errorReporting.reportError(skipping401Error);

      verifyNever(() => client.loadForm(uri: any(named: 'uri')));
      verifyNever(() => client.submitForm(any(), any()));
    });

    test('Skips custom defined Error', () async {
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        ignoreError: (_) => true,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      const dummyError = 'error';

      await errorReporting.reportError(dummyError);

      verifyNever(() => client.loadForm(uri: any(named: 'uri')));
      verifyNever(() => client.submitForm(any(), any()));
    });
  });

  group('Errors', () {
    setUp(() {
      final processor = MockAttachmentProcessor();
      when(() => client.attachmentProcessor).thenReturn(processor);

      when(() => processor.createAttachment('log.txt')).thenAnswer(
        (invocation) async => Attachment(
          name: 'log.txt',
          url: Uri(path: '/log/attachment'),
          type: 'text/plain',
        ),
      );
    });

    test('Error while fetching form. Gets added to log', () async {
      when(() => client.loadForm(uri: reportingForm))
          .thenAnswer((invocation) async {
        when(() => client.loadForm(uri: reportingForm))
            .thenAnswer((invocation) async => fullForm);
        return Future.error('Could not send initially');
      });

      when(
        () => client.submitForm(fullForm.links[ApptiveLinkType.submit]!, any()),
      ).thenAnswer((invocation) async => Response('body', 201));
      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      const initialError = 'InitialError';

      await errorReporting.reportError(initialError);

      const retryError = 'RetryError';
      await errorReporting.reportError(retryError);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final logBytes =
          (sendForm.attachmentActions.values.first as AddAttachmentAction)
              .byteData;

      final logString = utf8.decode(logBytes!);

      expect(logString, contains('Could not send initially'));
      expect(logString, contains('InitialError'));
    });
    test('Error while sending form. Gets added to log', () async {
      when(() => client.loadForm(uri: reportingForm))
          .thenAnswer((invocation) async => fullForm);
      when(
        () => client.submitForm(fullForm.links[ApptiveLinkType.submit]!, any()),
      ).thenAnswer((invocation) async {
        when(
          () => client.submitForm(
            fullForm.links[ApptiveLinkType.submit]!,
            any(),
          ),
        ).thenAnswer((invocation) async => Response('body', 201));
        return Future.error('Could not send initially');
      });

      errorReporting = ApptiveGridErrorReporting(
        reportingForm: reportingForm,
        project: 'project',
        client: client,
        sendErrors: true,
      );

      await errorReporting.isInitialized;

      const initialError = 'InitialError';

      await errorReporting.reportError(initialError);

      clearInteractions(client);
      const retryError = 'RetryError';
      await errorReporting.reportError(retryError);

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final logBytes =
          (sendForm.attachmentActions.values.first as AddAttachmentAction)
              .byteData;

      final logString = utf8.decode(logBytes!);

      expect(logString, contains('Could not send initially'));
      expect(logString, contains('InitialError'));
    });
  });

  group('Ignore Duplicate Send', () {
    setUp(() {
      when(() => client.loadForm(uri: reportingForm))
          .thenAnswer((invocation) async => fullForm);

      when(
        () => client.submitForm(fullForm.links[ApptiveLinkType.submit]!, any()),
      ).thenAnswer((invocation) async => Response('body', 201));
    });
    test(
        'Do not send same error multiple times per session. Send Ignored Errors on next unique repoert',
        () async {
      final processor = MockAttachmentProcessor();
      when(() => client.attachmentProcessor).thenReturn(processor);

      when(() => processor.createAttachment('mutedErrors.txt')).thenAnswer(
        (invocation) async => Attachment(
          name: 'mutedErrors.txt',
          url: Uri(path: '/mutedErrors/attachment'),
          type: 'text/plain',
        ),
      );
      errorReporting = ApptiveGridErrorReporting(
          reportingForm: reportingForm,
          project: 'project',
          client: client,
          sendErrors: true,
          avoidDuplicatePerSession: true);

      await errorReporting.isInitialized;

      const dummyError = 'Original Error';

      await errorReporting.reportError(dummyError);
      // Resend Error should not trigger a send
      await errorReporting.reportError(dummyError);

      verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          any(),
        ),
      ).called(1);

      await errorReporting.reportError('New Unique Error');

      final sendForm = verify(
        () => client.submitForm(
          fullForm.links[ApptiveLinkType.submit]!,
          captureAny(),
        ),
      ).captured.first as FormData;

      final mutedErrorBytes =
          (sendForm.attachmentActions.values.first as AddAttachmentAction)
              .byteData;

      final mutedErrorString = utf8.decode(mutedErrorBytes!);
      expect(mutedErrorString, contains(dummyError));
    });
  });
}

const formFields = [
  GridField(
    id: keys.project,
    name: keys.project,
    type: DataType.text,
    key: keys.project,
  ),
  GridField(
    id: keys.name,
    name: keys.name,
    type: DataType.text,
    key: keys.name,
  ),
  GridField(
    id: keys.attachments,
    name: keys.attachments,
    type: DataType.attachment,
    key: keys.attachments,
  ),
  GridField(
    id: keys.appVersion,
    name: keys.appVersion,
    type: DataType.text,
    key: keys.appVersion,
  ),
  GridField(id: keys.os, name: keys.os, type: DataType.text, key: keys.os),
  GridField(
    id: keys.osVersion,
    name: keys.osVersion,
    type: DataType.text,
    key: keys.osVersion,
  ),
  GridField(
    id: keys.stage,
    name: keys.stage,
    type: DataType.text,
    key: keys.stage,
  ),
  GridField(
    id: keys.locale,
    name: keys.locale,
    type: DataType.text,
    key: keys.locale,
  ),
  GridField(
    id: keys.message,
    name: keys.message,
    type: DataType.text,
    key: keys.message,
  ),
];

FormData get fullForm => FormData(
      id: 'reportingForm',
      components: [
        FormComponent(
          property: keys.project,
          data: StringDataEntity(),
          field: formFields[0],
        ),
        FormComponent(
          property: keys.name,
          data: StringDataEntity(),
          field: formFields[1],
        ),
        FormComponent(
          property: keys.attachments,
          data: AttachmentDataEntity(),
          field: formFields[2],
        ),
        FormComponent(
          property: keys.appVersion,
          data: StringDataEntity(),
          field: formFields[3],
        ),
        FormComponent(
          property: keys.os,
          data: StringDataEntity(),
          field: formFields[4],
        ),
        FormComponent(
          property: keys.osVersion,
          data: StringDataEntity(),
          field: formFields[5],
        ),
        FormComponent(
          property: keys.stage,
          data: StringDataEntity(),
          field: formFields[6],
        ),
        FormComponent(
          property: keys.locale,
          data: StringDataEntity(),
          field: formFields[7],
        ),
        FormComponent(
          property: keys.message,
          data: StringDataEntity(),
          field: formFields[8],
        ),
      ],
      fields: formFields,
      links: {
        ApptiveLinkType.submit:
            ApptiveLink(uri: Uri(path: '/submit'), method: 'post'),
      },
    );
