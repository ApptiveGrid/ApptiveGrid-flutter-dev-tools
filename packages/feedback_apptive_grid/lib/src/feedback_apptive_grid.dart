import 'package:apptive_grid_core/apptive_grid_core.dart';
import 'package:collection/collection.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';

// coverage:ignore-start
/// This is an extension to make it easier to call
/// [showAndUploadToApptiveGrid].
extension BetterFeedbackX on FeedbackController {
  /// Example usage:
  /// ```dart
  /// import 'package:feedback_apptiveGrid/feedback_apptiveGrid.dart';
  ///
  /// RaisedButton(
  ///   child: Text('Click me'),
  ///   onPressed: (){
  ///     BetterFeedback.of(context).showAndUploadToApptiveGrid
  ///       formUri: 'Uri.parse('YOUR_FORM_LINK')',
  ///     );
  ///   }
  /// )
  void showAndUploadToApptiveGrid({
    required Uri formUri,
  }) {
    show(uploadToApptiveGrid(formUri: formUri));
  }
}
// coverage:ignore-end

/// See [BetterFeedbackX.showAndUploadToApptiveGrid].
/// This is just [visibleForTesting].
@visibleForTesting
OnFeedbackCallback uploadToApptiveGrid({
  required Uri formUri,
  ApptiveGridClient? client,
}) {
  return (UserFeedback feedback) async {
    final apptiveGridClient =
        client ?? ApptiveGridClient(); // coverage:ignore-line

    final formData = await apptiveGridClient.loadForm(uri: formUri);

    formData.components
        ?.firstWhereOrNull(
          (component) =>
              component.field.key == 'feedback' &&
              component.field.type == DataType.text,
        )
        ?.data
        .value = feedback.text;
    final attachmentField = formData.components?.firstWhereOrNull(
      (component) =>
          component.field.key == 'attachment' &&
          component.field.type == DataType.attachment,
    );

    final attachment = await apptiveGridClient.attachmentProcessor
        .createAttachment('attachment.png');
    (attachmentField?.data as AttachmentDataEntity?)?.value!.add(attachment);
    formData.attachmentActions[attachment] = AddAttachmentAction(
      attachment: attachment,
      byteData: feedback.screenshot,
    );

    await apptiveGridClient.submitForm(
      formData.links[ApptiveLinkType.submit]!,
      formData,
    );
  };
}
