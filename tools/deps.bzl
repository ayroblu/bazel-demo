def rusqlite_deps():
    """
    load("//tools:deps.bzl", "rusqlite_deps")
    """
    return select({
        "@platforms//os:android": ["@crates-android//:rusqlite"],
        "//conditions:default": ["@crates//:rusqlite"],
    })
