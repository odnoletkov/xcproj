# xcodeproj-format

Format Xcode project files (.pbxproj) the same way Xcode would.

# Install

    brew install xcodeproj-format

# Usage

```
$ xcodeproj-format path/to/App.xcodeproj
```
```
$ xcodeproj-format path/to/App.xcodeproj/project.pbxproj
```
```
$ xcodeproj-format path1 path2 ...
```
```
$ cd path/to/project
$ xcodeproj-format
```

# Sample Use Cases

* Cleanup after other tools modifications
* Cleanup after merge conflict resolution
* Detect and reject misformatted or corrupted projects in CI

# Limitations

* Xcode's internal frameworks and private APIs are used so the tool may break
  with new Xcode version
* There is a ~1 second overhead to load and initialize Xcode state
* Project files are not fully self-contained - format may depend on .xcconfig
  files included with relative paths. Set `XCODEPROJ_PATH` environment variable
  to override path to the container .xcodeproj

# Credits

* [xcproj](https://github.com/0xced/xcproj)
