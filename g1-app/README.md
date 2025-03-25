G1 App
======

This is an app for the Even Reality G1 glasses based on their demo app: https://github.com/even-realities/EvenDemoApp

Note that for bazel and sourcekit-lsp, we manually add each package to our vim config so that it finds the packages

## TODO
* Create a bmp
* Voice control
* Navigate - Map
    * https://docs.mapbox.com/ios/maps/examples/static-map-snapshot/
* On device translation

### Navigation thoughts:
1. On start, fetch the "whole" map. Note that for a large map, where you move diagonally, this could be a lot of data.
2. Render roads as lines, using number of lanes etc to represent thickness. PERHAPS, should also show impediments in some way (river, buildings etc)
