# Yueli

A local-first reading tracker that combines reading plans, a timer, and reading stats in one app.

[中文](README.md)

The problem it tries to solve is simple: you may be reading several books at once, some with deadlines and some without. You want to time a reading session without much friction, then see where your time went and how long the current pace will take you to finish.

No account and no cloud. Everything stays on your device.

## Features

- **Bookshelf**: organize books as Want to Read, Reading, Finished, or Shelved. Filter by multiple tags and search by title or author. A book is marked Finished automatically when you reach the last page. The pencil on each card opens the editor directly.
- **Reading plans**: schedule by minutes per day or pages per day. Set a deadline or leave it open, choose reading days, and add rest days. Remaining pages are redistributed after your progress changes.
- **Today**: tap the checkbox to mark a task done, no input required. To record the page you actually reached and the time spent, use “Complete and record” in the card menu, or tap the task text afterwards to fill it in. Tap the checkbox again to undo, or skip the task.
- **Timer**: pause and resume, or start the timer first and pick the book later. When stopping, you can edit the duration or log pages without recording time.
- **Manual page entry**: record pages read on a given day without timing the session. It appears in history and page stats, but does not affect the measured reading speed.
- **Fix a record**: every reading record in stats, calendar, and book detail can be opened to change the page, duration, or date, or to delete it; finished tasks can be corrected too. Before saving you see what the book's progress will become, and the progress and upcoming schedule are recalculated afterwards.
- **Stats**: per-book and overall, switchable between time and pages. Supports the last 7/30/90 days or a custom range, with a reading heatmap and an estimated finish date based on your measured pace.
- **Calendar**: shows both planned tasks and actual reading sessions, including days with reading history but no plan.
- **Re-reading**: a book can have multiple reading rounds, each with its own progress. A round can be deleted along with its reading history, and later rounds shift up automatically.
- **Backup**: one ZIP export containing a full backup that can be imported again, plus a CSV of reading history for Excel.
- **Day cutoff**: set a time such as 4:00 AM as the start of a new day, so late-night reading stays on the previous day.

## Install

Download the latest Android APK from [Releases](https://github.com/bigshans/yueli/releases) and install it over the previous version. The database migrates automatically on launch.

The app is primarily built for Android. Flutter project folders for Windows, macOS, Linux, and Web are also included.

## Data

- Data lives in a local SQLite database. There is no account or server upload.
- Export a backup from Settings → Data Backup before switching devices or reinstalling.
- Importing a backup replaces the current data, so check the file before confirming.

## Development

Built with Flutter, Drift (SQLite), and Riverpod.

```bash
flutter pub get
flutter run
flutter test
flutter build apk --release
```

Bug reports and suggestions are welcome in [Issues](https://github.com/bigshans/yueli/issues).
