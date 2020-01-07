# 🔔 taskwarrior-reminders

Bi-directional replication of [Taskwarrior](http://taskwarrior.org) tasks
across iOS/macOS devices, by way of iCloud Reminders.

**IMPORTANT** - This is still experimental and buggy, please back up your data
before playing around with it!

![demo](https://s5.gifyu.com/images/demo-gif.gif "Demo")

## How it Works

A process runs in the background on your Mac and responds to changes made in
Reminders or Taskwarrior. When a change is detected it is persisted back to the
other system. If `taskd` is configured, tasks are automatically sync'd before
and after any changes to Reminders are detected.

Below is a breakdown of how Taskwarrior concepts map to the Reminders data
model, along with the current status of bi-directional replication support.

| Taskwarrior     | Reminders    |Status|
|:----------------|:-------------|:----:|
| Description     | Title        |  ✅  |
| Project         | List         |  ✅  |
| Priority        | Priority     |  ✅  |
| Status          | Completed    |  ✅  |
| Due             | Notification |  ✅  |
| Annotations     | Notes        |  ✅  |
| Deletion        | Deletion     |  ✅  |
| Urgency         | Sort Order   |  ⚠️   |
| +next           | Flagged      |  ⚠️   |
| Dependencies    | Subtasks     |  ⚠️   |
| Tags            | ???          |  ❌  |
| Wait            | ???          |  ❌  |
| UDA             | ???          |  ❌  |

Legend:
* ✅ Supported
* ⚠️ Unsupported (no public API from Apple yet)
* ❌ Not planned

## Installation

You will need the latest XCode and [Command Line Tools] (for Xcode 11.3) from
Apple in order to build and install.

Once you have those, run:

```
$ make install
```

If everything went well you should automatically be prompted for permission to
access Reminders.

If you see an error like `dyld: Library not loaded`, go back and install the
CLI tools.

**NOTE** - This won't automatically sync your whole Taskwarrior database to
Reminders, only the new items you create after installing. If you're feeling
adventurous, run `task-reminders-sync --all` once to mirror all your tasks and
reminders across both systems.

### `taskd` and Multiple Macs

You shouldn't install this on more than one Mac unless you have `taskd`
configured – otherwise tasks will become duplicated.

To prevent task duplication, `sync` is automatically called when any changes to
Reminders are detected. This means your local Taskwarrior snapshot should
stay up to date with your other online Macs, and you can safely remove any
`cron` jobs or hooks that previously called `task sync` for you.

## Notes on [Taskwarrior Hooks]

The tool doesn't take an opinion on projects versus tags... but included is an
optional hook I find very useful. For Reminders created in the "Life" list it
will automatically add a `+life` tag; and for tasks created under the "life"
context it will automatically add them to the "Life" list in reminders.
Install with something like:

```
    ln -s $PWD/hooks/on-add.context ~/.task/hooks/on-add.context
```

(Let me know if you feel strongly the agent should handle this for you
automatically.)

If you notice reminders are not propagating back to Taskwarrior, it may be
because you have failing hooks. The agent doesn't run in your shell – so if a
hook executes `task` instead of `/usr/bin/local/task`, this will fail when
being run by the agent. Fix this by ensuring your hooks don't require user
login.

## TODO & Known Issues
[ ] Deleting a Reminder list with outstanding items in it will cause all of
    the items to be deleted (expected), but the list will be re-created empty.
    Simply delete it again to completely remove it.

[Command Line Tools]: https://developer.apple.com/download/more/?=command%20line%20tools
[Taskwarrior Hooks]: https://taskwarrior.org/docs/hooks_guide.html
