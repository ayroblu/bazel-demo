Map Design App
==============

Scan a space with an iPhone or iPad LiDAR camera and get a simple
architectural model: floors, walls, boxes for objects, and trunks plus
canopies for trees. It is not a point cloud or a mesh. People and things that
move are left out, while trees that sway are kept.

There are two scan modes:

- **Room** uses Apple's [RoomPlan](https://developer.apple.com/documentation/roomplan).
  It gives walls, doors, windows, openings, floors and furniture boxes, but it
  only works indoors.
- **Site** works indoors and outdoors. It fuses the LiDAR depth into 10 cm
  voxels and fits the model shapes to them. The live model is drawn over the
  camera view and refreshes every 2 seconds.

## How Site mode works

1. ARKit gives a depth map, its confidence and a person segmentation mask. The
   app samples them 10 times a second (`capture/site-scanner.swift`).
2. Each depth sample marks its voxel as hit. The ray from the camera to the
   sample marks the voxels it passes through as seen empty, but only when the
   ray passes close to the surface measured in that voxel. Pixels on people
   carve free space but never add hits (`reconstruction/reconstructor.swift`).
3. A voxel is kept if it was hit in at least half of the seconds in which it
   was observed. Someone walking past is hit for a second or two and then seen
   through, so their voxels are dropped. A swaying branch is hit most seconds
   but often seen through within a second, so it is kept and marked soft.
4. Shapes are fitted to the kept voxels (`reconstruction/extraction.swift`):
   - Horizontal planes at floor height, or above head height, become slabs.
   - Vertical planes at least 1 m high become walls, snapped to the main wall
     direction.
   - Groups of soft voxels become canopy ellipsoids.
   - Other groups become boxes, or cylinders if they are thin and tall. A
     cylinder under a canopy is a trunk.

People who stay still are removed only by the person mask. Someone who walks
through a place you never look at again stays in the model, so scan those
areas again.

## Building

```sh
bazel build //map-design-app
bazel run //map-design-app:xcodeproj && xed map-design-app/map-design-app.xcodeproj
```

Scanning needs a device with LiDAR. The simulator only shows the start screen.

```sh
cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision map-design-app/development.mobileprovision
bazel run --config=ios --ios_device=iphone //map-design-app
```
