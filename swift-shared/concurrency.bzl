_DEFINES = select({
    "//conditions:default": ["-DDEBUG"],
    "//:release_build": ["-DRELEASE"],
})

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

SWIFT6_FEATURES_COPTS = [
    "-swift-version",
    "6",
    "-enable-upcoming-feature",
    "NonisolatedNonsendingByDefault",
    "-enable-upcoming-feature",
    "InferIsolatedConformances",
]

STRICT_NONISOLATED_COPTS = _DEFINES + COMMON_FEATURES_COPTS + [
    "-default-isolation",
    "nonisolated",
]

STRICT_MAINACTOR_COPTS = _DEFINES + COMMON_FEATURES_COPTS + [
    "-default-isolation",
    "MainActor",
]

SWIFT6_NONISOLATED_COPTS = _DEFINES + SWIFT6_FEATURES_COPTS + [
    "-default-isolation",
    "nonisolated",
]

SWIFT6_MAINACTOR_COPTS = _DEFINES + SWIFT6_FEATURES_COPTS + [
    "-default-isolation",
    "MainActor",
]
