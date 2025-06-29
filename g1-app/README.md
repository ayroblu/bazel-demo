G1 App
======

This is an app for the Even Reality G1 glasses based on their demo app: https://github.com/even-realities/EvenDemoApp

Note that for bazel and sourcekit-lsp, we manually add each package to our vim config so that it finds the packages

## TODO

* Listen
    * Mic indicator when using mic
    * Turn off mic when leaving listen screen
    * keep past speech

* Create a bmp
* Voice control
* Navigate - Map
    * https://docs.mapbox.com/ios/maps/examples/static-map-snapshot/
    * Update position / instructions based on where you are
    * Update speed based on location history
* On device translation

## Even app features

* [ ] In App Preview
* [x] QuickNote
* [ ] Translate (I think this needs to be online)
* [x] Navigate
* [ ] Teleprompt
* [ ] Even AI
* [ ] Transcribe
* [x] Dashboard
    * [x] notes
    * [ ] stock
    * [ ] map

## Navigate:
### Cache

Example: 1 - 4 lat, 1 - 4 lng, (16 squares)
Cache key = top-left lat,lng
1.5 <-> 2.5: 1 - 3 (1, 2 cache key)

1. saved files: cache-key + mtime for file if file is more than 1 year old, invalidate it
2. grab all necessary times into memory, and build whole OverpassResult from combination

