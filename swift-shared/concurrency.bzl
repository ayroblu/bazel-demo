COMMON_FEATURES_COPTS = [
    "-enable-upcoming-feature",
    "NonisolatedNonsendingByDefault",
    "-enable-upcoming-feature",
    "InferIsolatedConformances",
    "-enable-upcoming-feature",
    "InferSendableFromCaptures",
    "-enable-upcoming-feature",
    "DisableOutwardActorInference",
    "-enable-upcoming-feature",
    "GlobalActorIsolatedTypesUsability",
    "-enable-upcoming-feature",
    "StrictConcurrency",
]
STRICT_NONISOLATED_COPTS = select({
    "//conditions:default": ["-DDEBUG"],
    "//:release_build": ["-DRELEASE"],
}) + COMMON_FEATURES_COPTS + [
    "-default-isolation",
    "nonisolated",
]

STRICT_MAINACTOR_COPTS = select({
    "//conditions:default": ["-DDEBUG"],
    "//:release_build": ["-DRELEASE"],
}) + COMMON_FEATURES_COPTS + [
    "-default-isolation",
    "MainActor",
]
