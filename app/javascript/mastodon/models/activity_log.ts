// One entry in a student's Activity Log, as it arrives over the SSE stream from
// `GET /api/v1/activity_log`. The server side of this wire format is
// `app/lib/activity_log_event.rb`; changing either without the other is a
// breaking change.
//
// The shape is owned by `activitypub-visualization`, which renders it, so the
// type is taken from the package rather than restated here — that way a
// mismatch is a compile error instead of an empty column.
export type { ILogEvent as ActivityLogEvent } from 'activitypub-visualization/dist/src/types';

// The activity carried inside a log entry, and the same shape the Explorer takes
// as its seed when a student clicks through from the log. Taken from the package
// for the same reason.
export type { IActivity as ActivityLogActivity } from 'activitypub-visualization/dist/src/types';
