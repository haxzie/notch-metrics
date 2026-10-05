# Changesets

`pnpm changeset` on any pull request that changes behaviour.

Three things about this repository's setup are not the defaults, and each is
deliberate.

**`@notch/web` and `@notch/api` are ignored.** They are _deployed_, not
_released_: there is no version a user can observe, no install step, and no
rollback that a version number helps with. Versioning them would mean churn in
two CHANGELOGs nobody reads, and `changeset status` nagging for a changeset on
a CSS tweak.

**`@notch/mac` is a version-only shim** — a `package.json` with nothing in it
but a name and a version. It exists so a Swift app can be versioned by the same
mechanism as everything else; `scripts/sync-mac-version.mjs` turns that version
into `apps/mac/Config/Version.xcconfig`, which is what `Info.plist` reads.

A Swift app depends on nothing in this workspace, so `updateInternalDependencies`
will never bump it: **a change to the Mac app must name `@notch/mac`
explicitly**. That is easy to forget, so CI checks for it — see the
`changeset-guard` job in `ci.yml`.

**`privatePackages.tag` is false.** `changeset publish` would otherwise create
a `@notch/mac@0.2.0` tag, and the Mac release is driven by a `mac-v0.2.0` tag
that `version.yml` pushes on purpose. Two tags for one release is one too many.

## Choosing a bump

- **patch** — a fix, or anything a user would not notice.
- **minor** — anything a user _would_ notice.
- **major** — a conversation, not a checkbox.
