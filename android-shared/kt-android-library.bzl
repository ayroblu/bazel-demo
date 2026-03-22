load("@rules_kotlin//kotlin:android.bzl", rules_kotlin_kt_android_library = "kt_android_library")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")

def kt_android_library(name, **kwargs):
    """
    For some reason, Android Studio bazel plugin doesn't recognise kt_android_library, but it does recognise kt_jvm_library
    kt_jvm_library may not work if the source code references android specific libraries, so we do both
    """
    rules_kotlin_kt_android_library(name = name, **kwargs)
    kt_jvm_library(name = "%s-jvm" % name, tags = ["manual"], **kwargs)
