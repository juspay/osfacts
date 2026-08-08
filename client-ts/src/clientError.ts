/**
 * The errors this client raises, in a module that imports nothing but Effect.
 *
 * It sits below both `client.ts` (the parser and the spawn twins) and
 * `childFailure.ts` (the child boundary), because both raise these and a class
 * defined in either one would make the pair a cycle — which this repo's lint
 * refuses, rightly: a cycle would mean neither module could be read as standing
 * on the other. `client.ts` re-exports them, so every consumer's import is
 * unchanged and the package still has exactly one public root.
 *
 * Three classes, not one class with a `kind` field. The kind was always the
 * thing a caller branched on, and a string compared by hand is a discriminant
 * only by convention: nothing stopped `kind === "parse"` from being written
 * `"parsing"`, and nothing narrowed the value when it matched. As
 * `Schema.TaggedError`es the discriminant is the `_tag`, the classes are
 * `instanceof`-checkable at a `catch`, and an Effect verb can declare exactly
 * which of them it can fail with. They are still `Error`s, which is what lets
 * the SYNC island (see `client.ts`) go on throwing them.
 *
 * `message` rides as a schema FIELD rather than a `get message()` over
 * structured data, because these messages are composed at the raise site out of
 * the row, the field name, and the child's own stderr — there is no smaller set
 * of data the sentence could be rebuilt from, and the exact bytes are pinned by
 * tests.
 */

import { Schema } from "effect";

/** The child could not be launched, or would not answer: an empty binary path,
 *  a missing bake, an empty socket path, or a child that failed without leaving
 *  a document behind. `cause` carries the runtime's own spawn error where there
 *  was one. */
export class OsfactsSpawnError extends Schema.TaggedError<OsfactsSpawnError>(
  "osfacts-client/OsfactsSpawnError",
)("OsfactsSpawnError", {
  message: Schema.String,
  cause: Schema.optional(Schema.Unknown),
}) {}

/** The document does not begin with a version line this reader speaks. Its own
 *  class rather than a parse failure because it is the ONE failure that means
 *  "binary and client are from different sources" — a deployment fact, not a
 *  corrupt row. */
export class OsfactsVersionError extends Schema.TaggedError<OsfactsVersionError>(
  "osfacts-client/OsfactsVersionError",
)("OsfactsVersionError", { message: Schema.String }) {}

/** A row the reader cannot read: a bad arity, an unknown tag, a field that is
 *  not the number/JSON/status it must be, or a document whose rows contradict
 *  each other. `cause` carries `JSON.parse`'s own error where the field was
 *  meant to be JSON. */
export class OsfactsParseError extends Schema.TaggedError<OsfactsParseError>(
  "osfacts-client/OsfactsParseError",
)("OsfactsParseError", {
  message: Schema.String,
  cause: Schema.optional(Schema.Unknown),
}) {}

/** Every failure this client declares — the error channel of every Effect verb,
 *  and the closed set a `catch` around the sync island can see. */
export type OsfactsClientError =
  | OsfactsSpawnError
  | OsfactsVersionError
  | OsfactsParseError;

/** The runtime twin of {@link OsfactsClientError}: a TYPE GUARD, so a `catch`
 *  narrows rather than re-checking a tag by hand. Anything it rejects is a
 *  defect — this client's own throws are exactly these three. */
export function isOsfactsClientError(
  error: unknown,
): error is OsfactsClientError {
  return (
    error instanceof OsfactsSpawnError ||
    error instanceof OsfactsVersionError ||
    error instanceof OsfactsParseError
  );
}
