# feedback_apptive_grid

This is a plugin to send user feedback gathered using [feedback](https://pub.dev/packages/feedback) to send to [ApptiveGrid](https://apptivegrid.de)

<img src="https://github.com/ApptiveGrid/ApptiveGrid-flutter-dev-tools/blob/main/.github/assets/feedback_apptive_grid/demo.gif?raw=true" width="1000px">

## Setup

1. Create a new Feedback Space on ApptiveGrid using [this template](https://app.apptivegrid.de/#/template/653666cfa579f6d120c4ad57)
2. Copy the Feedback Form Link
   <img src="https://github.com/ApptiveGrid/ApptiveGrid-flutter-dev-tools/blob/main/.github/assets/feedback_apptive_grid/copy_form_link.png?raw=true" width="1000px">
3. Wrap your App in a `BetterFeedback` Widget
    ```dart
   void main() {
      runApp(const BetterFeedback(child: MyApp()));
    }
    ```
4. Provide a way to show the feedback panel by calling
    ```dart
    BetterFeedback.of(context).showAndUploadToApptiveGrid(
      formUri: Uri.parse('YOUR_FEEDBACK_FORM_LINK'),
    );
    ```