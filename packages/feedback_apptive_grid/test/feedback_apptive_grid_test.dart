import 'dart:typed_data';

import 'package:apptive_grid_core/apptive_grid_core.dart';
import 'package:apptive_grid_core/src/network/attachment_processor.dart';
import 'package:feedback_apptive_grid/feedback_apptive_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApptiveGridClient extends Mock implements ApptiveGridClient {}

class MockAttachmentProcessor extends Mock implements AttachmentProcessor {}

void main() {
  late ApptiveGridClient client;
  late AttachmentProcessor attachmentProcessor;

  setUpAll(() {
    registerFallbackValue(
      FormData(id: 'id', components: [], fields: [], links: {}),
    );
  });

  setUp(() {
    client = MockApptiveGridClient();
    attachmentProcessor = MockAttachmentProcessor();

    when(() => client.attachmentProcessor).thenReturn(attachmentProcessor);
  });

  test('Sends Feedback via Form', () async {
    final formUri = Uri.parse('/form');
    const textField = GridField(
      id: 'text',
      name: 'text',
      type: DataType.text,
      key: 'feedback',
    );
    const attachmentField = GridField(
      id: 'attachment',
      name: 'attachment',
      type: DataType.attachment,
      key: 'attachment',
    );
    final formData = FormData(
      id: 'id',
      components: [
        FormComponent(
          property: 'text',
          data: StringDataEntity(),
          field: textField,
        ),
        FormComponent(
          property: 'attachment',
          data: AttachmentDataEntity(),
          field: attachmentField,
        ),
      ],
      fields: [
        textField,
        attachmentField,
      ],
      links: {
        ApptiveLinkType.submit: ApptiveLink(uri: Uri(), method: 'post'),
      },
    );

    final attachment = Attachment(name: 'name', url: Uri(), type: 'image/png');
    when(() => attachmentProcessor.createAttachment(any()))
        .thenAnswer((_) async => attachment);

    when(() => client.loadForm(uri: formUri)).thenAnswer((_) async => formData);
    when(
      () => client.submitForm(formData.links[ApptiveLinkType.submit]!, any()),
    ).thenAnswer((_) async => null);

    const feedbackText = 'Feedback Test';
    final data = Uint8List(8);
    final feedback = UserFeedback(text: feedbackText, screenshot: data);

    final onFeedback = uploadToApptiveGrid(formUri: formUri, client: client);

    await onFeedback.call(feedback);

    final sendFormData = verify(
      () => client.submitForm(
        formData.links[ApptiveLinkType.submit]!,
        captureAny(),
      ),
    ).captured.first as FormData;

    expect(
      (sendFormData.components!.first.data as StringDataEntity).value,
      feedbackText,
    );
    expect(
      (sendFormData.components!.last.data as AttachmentDataEntity).value,
      [attachment],
    );
  });
}
