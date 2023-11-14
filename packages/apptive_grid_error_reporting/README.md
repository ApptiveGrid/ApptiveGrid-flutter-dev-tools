# ApptiveGrid ErrorReporting

With `ApptiveGridErrorReporting` it is super easy to Log Errors to ApptiveGrid

## Setup
1. [Create a new Error Reporting Space on ApptiveGrid using this Template](https://app.apptivegrid.de/#/template/65005ff33e85a232b5c17517)

   _(Don't worry if you don't have an ApptiveGrid Account yet, you can create on there. Try it out. It's free)_
2. Copy the Reporting Form Link

   <img src="https://github.com/ApptiveGrid/ApptiveGrid-flutter-dev-tools/blob/main/.github/assets/apptive_grid_error_reporting/copy_form_link.png?raw=true" width="1000px">
3. Create a new instance of `ApptiveGridErrorReporting`
   
    ```dart
    final reporting = ApptiveGridErrorReporting(
      reportingForm: Uri.parse('FORM_LINK'),
      project: 'myProject',
    );
    ```
   
## Report Errors
Send Errors with a single command
```dart
reporting.report(error); 
```
This will send the error to ApptiveGrid. You can provide additional Infos like a `Stacktrace` or a custom `message` to get more context when looking at the reports on ApptiveGrid

```dart
reporting.report(
  error,
  stackTrace: StackTrace.current,
  message: 'Error when doing a demo',
); 
```

### Repord Flutter Errors

To report Flutter Errors set the `FlutterError.onError` reporting callback like this:

```dart
FlutterError.onError = reporting.reportFlutterError;
```

## Log Events
You can provide additional Log Entries to further know what a user might have done leading to an error.
```dart
reporting.log('Something was clicked'); 
```
    