HN Feed App
===========

A Hacker News reader with four tabs:

- **YC200** and **250+**: the last 100 posts of the
  [newsyc200](https://bsky.app/profile/newsyc200.bsky.social) and
  [newsyc250](https://bsky.app/profile/newsyc250.bsky.social) Bluesky accounts,
  which post each story when it reaches 200 or 250 points. They come from the
  public Bluesky API (`app.bsky.feed.getAuthorFeed`), which needs no account.
- **Front Page**: the top 30 stories from the
  [official HN API](https://github.com/HackerNews/API) (`topstories.json`), in
  front page order.
- **Experimental**: stories that gain points quickly. The feed is built by a
  GitHub Action in [ayroblu/hnfeed](https://github.com/ayroblu/hnfeed) and
  published to https://ayroblu.github.io/hnfeed/feed.jsonl.

Each tab shows its last downloaded feed from
`Library/Caches/hn-feed-<source>.jsonl` straight away, then refreshes it on
launch, when the app comes to the foreground, and on pull to refresh. Offline,
it keeps showing the cached feed.

Stories and their HN comments open in `SFSafariViewController`. Touching a link
calls `SFSafariViewController.prewarmConnections(to:)` before the finger lifts,
so the connection to the site is already being set up when Safari opens. The
last 5 opened pages are kept in memory, so closing and reopening one shows it
without reloading. They are lost when iOS terminates the app.

GitHub Pages caches the feed for up to 10 minutes, so new stories can take that
long to appear.

## Building

```sh
bazel build //hn-feed-app
bazel run //hn-feed-app:xcodeproj && xed hn-feed-app/hn-feed-app.xcodeproj
```

Run on a device

```sh
bazel run --config=ios --ios_device=Blu //hn-feed-app
```
