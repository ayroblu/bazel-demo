vimkeys
=======

This is a safari extension in the spirit of vimium-c

Getting started
---------------

```sh
gmake
```

Or with bazel (signs with your Apple Development certificate — Safari refuses
to persistently load web extensions from ad-hoc-signed apps, and vimkeys has
no provisioning profile for the signing identity to be inferred from):

```sh
gmake bazel-register
```


TODO
----

1. Build configuration panel
2. Build core features
  - Bookmarks list
  - open links with labels
    - https://gist.github.com/iiLaurens/81b1b47f6259485c93ce6f0cdd17490a
  - focus text inputs
  - edit url
  - keymap (question mark)

Reference
---------

- https://www.bedelstein.com/post/building-a-safari-app-extension-in-ios-15
- https://developer.apple.com/videos/play/wwdc2021/10104/
- https://developer.apple.com/documentation/safariservices/safari_web_extensions/assessing_your_safari_web_extension_s_browser_compatibility
